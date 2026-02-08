# TUI Implementation Plan

Based on the analysis in [RADDBG_UI_REPORT.md](./RADDBG_UI_REPORT.md), this plan breaks the
implementation into phases with clear deliverables. Each phase builds on the previous one and
can be validated independently.

The target architecture has two build modules (`ui` and `tui`) plus the existing `base`:

```
┌─────────────────────────────────────────────────┐
│  Application                                     │
│  Builds widget tree each frame via UI API        │
├─────────────────────────────────────────────────┤
│  ui module  (src/ui/)                            │
│  ┌ widgets: button, label, line_edit, etc.       │
│  └ core: box tree, layout, key hash, signals     │
├─────────────────────────────────────────────────┤
│  tui module  (src/tui/)                          │
│  TUI Draw: walks box tree → fills Cell grid      │
│  Terminal: raw mode, alt screen, input, flush     │
│  Frame loop: poll → build → layout → draw → flush │
└─────────────────────────────────────────────────┘
```

The `ui` module is rendering-agnostic — it operates purely on abstract cell coordinates
and has no knowledge of the terminal. It contains two sublayers: `core` (box tree, layout,
stacks, signals — the direct port of raddbg's `ui/`) and `widgets` (a submodule within
`ui` that provides common widget helpers on top of core). The application can bypass the
widgets submodule entirely and compose boxes directly for anything custom.

The `tui` module imports `ui` and provides the terminal-specific rendering, I/O, and
frame loop. It owns the cell grid, the draw pass that interprets box flags into cell
writes, and the terminal backend (raw mode, input parsing, diff+flush).

Both modules are declared in `build.zig` alongside `base` and `bin`:

```zig
const module_specs = [_]ModuleSpec{
    .{ .name = "bin", .path = "src/bin/bin.zig" },
    .{ .name = "tui_test", .path = "src/tui_test/tui_test.zig" },
    .{ .name = "tui", .path = "src/tui/tui.zig" },
    .{ .name = "ui",  .path = "src/ui/ui.zig" },
    .{ .name = "base", .path = "src/base/base.zig" },
};
```

The `tui_test` module is a separate executable for interactive test/demo applications.
Run with `zig build testing -- <name>` (e.g. `zig build testing -- grid`).

---

## Phase 1: Terminal Backend ✅

**Goal**: Own the terminal. Enter/exit alternate screen + raw mode cleanly, detect size,
parse input, and flush a cell grid to the screen with minimal I/O.

**Files**: `src/tui/term.zig`, `src/tui_test/tui_test.zig`, `src/tui_test/grid.zig`

**Status**: Complete.

### 1.1 — Raw Mode & Alternate Screen

`Term.init(arena)` opens `/dev/tty` (falls back to stdin), saves the original termios,
and enters raw mode by disabling ECHO, ICANON, IEXTEN, ISIG, ICRNL, IXON, OPOST and
setting CS8 / VMIN=0 / VTIME=0. A composite `mode.enter_all` escape string enables
alternate screen, hides the cursor, enables button-event mouse tracking (1002),
SGR mouse mode (1006), and bracketed paste (2004) in a single write.

`Term.deinit()` writes `mode.exit_all` (the reverse sequence) and restores the saved
termios. A global `emergency_cleanup()` performs the same restore and is called from
signal handlers for SIGTERM, SIGHUP, and SIGINT. The signal handlers reset the handler
to SIG_DFL and re-raise so the process exits with the correct signal status. All escape
sequences and their enable/disable pairs are declared as named constants in the `mode`
struct to avoid duplication.

### 1.2 — Terminal Size

`query_size(fd)` calls `ioctl(TIOCGWINSZ)` via `std.c.ioctl` and falls back to
80×24 (`default_cols` / `default_rows`) when the ioctl returns zero dimensions.

A `SIGWINCH` handler atomically sets `resize_pending`. `Term.check_resize()` reads and
clears the flag, re-queries the size, and if it changed, allocates fresh front/back
grids from the arena (old grids become dead arena memory — fine since resizes are rare).
Returns `true` when the size changed so the caller can adjust.

`cols` and `rows` are `u16` fields on `Term`.

### 1.3 — Cell Grid

```
const Ansi = enum(u8) {
    black = 0, red = 1, green = 2, yellow = 3,
    blue = 4, magenta = 5, cyan = 6, white = 7,
    bright_black = 8, bright_red = 9, bright_green = 10, bright_yellow = 11,
    bright_blue = 12, bright_magenta = 13, bright_cyan = 14, bright_white = 15,
    _,  // 16-255 extended palette via @enumFromInt
};

const Color = union(enum) {
    default,
    ansi: Ansi,      // named 0-15, extensible to 255
    rgb: [3]u8,      // 24-bit truecolor
};

const Attrs = packed struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    reverse: bool = false,
    strikethrough: bool = false,
    _pad: u2 = 0,
};

const Cell = struct {
    codepoint: u21 = ' ',
    fg: Color = .default,
    bg: Color = .default,
    attrs: Attrs = .{},
};
```

Two flat `[]Cell` slices (`front` and `back`) are allocated from the arena, sized
`cols * rows`. The application draws into `back`; `front` tracks what is on screen.

Grid operations (all methods on `Term`):
- `cell_at(col, row) -> ?*Cell` — direct cell access with bounds check
- `fill_rect(x, y, w, h, cell)` — fill a rectangular region, clamped to grid bounds
- `write_text(col, row, max_width, text, fg, bg, attrs) -> u16` — decode UTF-8 into
  cells, return columns consumed. Wide characters (CJK etc.) occupy two cells; the
  second cell is marked with `codepoint = 0` as a continuation marker.
- `clear()` — reset all cells in `back` to the default blank cell

### 1.4 — Grid Diffing & Flush

`Term.flush()` obtains a scratch arena (conflicting with the term's own arena), records
the arena position, and pushes ANSI output bytes directly into the scratch arena via
`emit()` / `emit_fmt()`. At the end it slices `arena.memory[start..end]` and writes it
to the tty in a single `writeAll`. The scratch arena is released after the write.

The diff loop walks every cell. For each cell where `back` differs from `front`:
- Cursor positioning: tracks the logical cursor position; emits `\x1b[row;colH` only
  when the cursor is not already at the right location (skips sequential writes).
- SGR state: tracks current fg, bg, and attrs. Only emits SGR codes when they change.
  When an attribute is turned *off*, a full reset (`\x1b[0m`) is emitted first, then
  the still-active attributes are re-emitted. All SGR codes are named constants in the
  `sgr` struct.
- Color encoding: standard ANSI 0-7 uses `\x1b[3x/4xm`, bright 8-15 uses `\x1b[9x/10xm`,
  extended 16-255 uses `\x1b[38;5;n / 48;5;nm`, truecolor uses `\x1b[38;2;r;g;b / 48;2;r;g;bm`.
  The numeric bases are named constants (`sgr.fg_base`, `sgr.bg_base`, etc.).

After writing, `front` and `back` pointers are swapped (no memcpy). The caller calls
`clear()` on the now-stale `back` buffer at the start of the next frame.

### 1.5 — Input Parsing

`Term.poll_event(timeout_ms)` checks the atomic resize flag first, then checks for
buffered bytes from a previous read, then calls `posix.poll` + `File.read` on the tty.
The only method that touches `Term` state is `drain_next()`, which loops calling the
free function `parse_input(buf)` and advancing `input_pos` until an event is produced
or the buffer is exhausted.

All parsing is implemented as free functions on `[]const u8`, returning a `ParseResult`
(event + bytes consumed):

| Function | Handles |
|---|---|
| `parse_input` | Dispatches first byte: escape sequences, control chars, UTF-8 |
| `parse_csi` | CSI sequences: arrows, home/end, function keys, tilde-params, SGR mouse, bracketed paste |
| `parse_ss3` | SS3 sequences: F1–F4, arrows (alternate encoding) |
| `parse_sgr_mouse` | SGR mouse param parsing, delegates to `decode_sgr_mouse` |
| `decode_sgr_mouse` | Interprets mouse button/modifier/motion/scroll bitmasks into `MouseEvent` |
| `tilde_param_to_key` | Maps CSI `~` parameter numbers to `Key` enum values |
| `char_to_key_event` | Maps a single byte to `KeyEvent` (enter, tab, backspace, ctrl+letter, printable) |
| `decode_xterm_mods` | Decodes xterm modifier parameter (value-1 bitmask) into `Modifiers` |

Byte classification is factored into named predicates: `is_escape`, `is_newline`,
`is_tab`, `is_backspace`, `is_ctrl_char`, `is_digit`, `is_csi_final`, `is_sgr_mouse_final`,
`is_mouse_release`, and `ctrl_to_letter`. Protocol bitmask constants live in `mouse_bits`
and `xterm_mod_bits` structs.

Event types:

```
const InputEvent = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    resize,
};

const KeyEvent = struct {
    key: Key = .none,       // .codepoint for printable, or a named special key
    codepoint: u21 = 0,    // the actual character (when key == .codepoint)
    mods: Modifiers = .{},
};

const MouseEvent = struct {
    kind: MouseKind,        // press, release, move, scroll_up, scroll_down
    button: MouseButton,    // left, middle, right, none
    col: u16,
    row: u16,
    mods: Modifiers,
};
```

Enabled on init: SGR mouse mode (1006), button-event tracking (1002), bracketed paste
(2004). Bracketed paste content is consumed and discarded (no paste event emitted yet).
Kitty keyboard protocol is not implemented; legacy xterm parsing covers the current needs.

### 1.6 — Validation

The `tui_test` build module (`src/tui_test/`) provides interactive test applications,
run via `zig build testing -- <name>`. The dispatch table in `tui_test.zig` maps names
to entry points; adding a test is one file + one tuple entry.

The **grid** test (`zig build testing -- grid`) validates Phase 1:
1. Enters alternate screen with raw mode
2. Fills the cell grid with a blue/red checkerboard pattern
3. Draws a yellow highlighted cell that moves with arrow keys
4. Shows a bold status bar with instructions
5. Handles terminal resize (re-clamps cursor position)
6. Exits cleanly on `q` or Ctrl-C (ISIG is disabled; Ctrl-C is parsed as input)

---

## Phase 2: UI Module — Data Structures, Stacks, Box Construction & Layout ✅

**Goal**: Implement the full immediate-mode UI core: data types, implicit state stacks,
box construction with cross-frame persistence, and the layout algorithm.

**Files**: `src/ui/ui.zig`, `src/ui/layout.zig`

**Status**: Complete.

### 2.1 — Data Structures (`src/ui/ui.zig`)

All types live in a single file rather than split across `key.zig`, `box.zig`, `signal.zig`
as originally planned — the types are small and tightly coupled.

`Key` wraps a `u64` hash. `Key.from_string(seed, string)` uses `std.hash.Wyhash` seeded
with the parent key to produce hierarchical keys. `parse_tag` splits strings on `##`
(display / hash separation) and `###` (display / whole-string-as-hash) separators,
returning a `Tag` with `display`, `hash_string`, and `has_display_string`.

`SizeKind` is `enum { null, cells, text_content, parent_pct, children_sum }`. `Size`
bundles `kind`, `value: f32`, and `strictness: f32` with constructors `Size.cells`,
`Size.text`, `Size.pct`, `Size.children`.

`BoxFlags` is a `packed struct` with 24 boolean flags covering interaction (`clickable`,
`keyboard_clickable`, `view_scroll`, `focus_hot`, `focus_active`), drawing (`draw_background`,
`draw_border`, `draw_text`, `draw_hot_effects`, `draw_active_effects`, `draw_side_*`),
clipping (`clip`, `overflow_x/y`), floating (`floating_x/y`), overflow permission
(`allow_overflow_x/y`), and metadata (`disabled`, `focus_nav_skip`, `has_display_string`).
Provides `with_border()` (sets draw_border + all four sides) and `merge()` (OR two flag sets).

`Box` has hash table links (`hash_next`/`hash_prev`), tree links (`first`/`last`/`next`/
`prev`/`parent`/`child_count`), identity fields (`key`, `flags`, `string`, `display_string`,
`text_align`, `pref_size[2]`, `child_layout_axis`, `fixed_position[2]`, `fixed_size[2]`,
`min_size[2]`), styling (`bg_color`, `fg_color`, `border_color`, `text_padding`), layout
output (`rect`, `position_delta[2]`), and persistent state that survives across frames
(`first/last_touched_build_index`, `hot_t`, `active_t`, `disabled_t`, `focus_hot_t`,
`focus_active_t`, `view_off[2]`, `view_off_target[2]`, `view_bounds[2]`).

`Color` is `union(enum) { default, ansi: Ansi, rgb: [3]u8 }` where `Ansi` is `enum(u8)`
with named values 0–15 and an extensible `_` variant. Both `ui.zig` and `term.zig` define
structurally identical but independent `Color`/`Ansi` types; demos use `to_term_color()`
converter functions to bridge between them.

`Rect` has `col`, `row`, `w`, `h` (all `u16`) with `contains` and `intersect`.

`Signal` has `flags: SignalFlags`, `mouse_pos: [2]u16`, `scroll: [2]i16`. `SignalFlags`
is a `packed struct` with `left_pressed/released/clicked`, `right_pressed/released/clicked`,
`keyboard_pressed`, `hovering`, `mouse_over`, `dragging`, `commit`, plus `any()` and
`merge()` helpers.

Free functions for tree manipulation: `push_child`, `remove_child`, `tree_next`
(depth-first pre-order).

### 2.2 — Stack System (`src/ui/ui.zig`)

`Stack(T)` is a generic fixed-capacity (64) stack. The bottom entry is the default and
cannot be popped. Each entry carries an `auto_pop` flag. Operations: `push` (returns old
top), `pop`, `top_val`, `set_next` (pushes with `auto_pop = true`), `auto_pop_if_set`,
`reset`.

`stack_decls` is a comptime tuple of 16 stacks: `parent` (`?*Box`), `child_layout_axis`,
`pref_width`, `pref_height`, `flags`, `bg_color`, `fg_color`, `border_color`,
`text_padding`, `text_align`, `fixed_x/y`, `fixed_width/height`, `min_width/height`.
The `focus_hot` and `focus_active` stacks from the original plan are omitted — focus
handling will be added with Phase 3 (Interaction).

`Stacks` is a struct generated at comptime from `stack_decls` via `@Type`. Helper
functions `init_stacks`, `auto_pop_all`, `reset_stacks` operate over all stacks via
`inline for`. `StackName` is a comptime `FieldEnum(Stacks)`.

Named helpers come in two flavors:

- **Persistent** (`push_*`/`pop_*`): stay on the stack until explicitly popped.
  `push_color`/`pop_color` (fg), `push_bg`/`pop_bg`, `push_border_color`/`pop_border_color`,
  `push_width`/`pop_width`, `push_height`/`pop_height`, `push_flags`/`pop_flags`,
  `push_axis`/`pop_axis`, `push_text_padding`/`pop_text_padding`,
  `push_text_align`/`pop_text_align`, `push_parent`/`pop_parent`.

- **Auto-pop** (`next_*`): consumed by the next `build_box` call.
  `next_color`, `next_bg`, `next_border_color`, `next_width`, `next_height`,
  `next_size(w, h)` (convenience for both), `next_flags`, `next_axis`,
  `next_text_padding`, `next_text_align`, `next_fixed_x/y`, `next_fixed_width/height`,
  `next_min_width/height`.

A generic interface (`push_stack`/`pop_stack`/`top_stack`/`set_next_stack` taking
a comptime `StackName`) is available for anything not covered by a named helper.

### 2.3 — Global State & Cross-Frame Persistence (`src/ui/ui.zig`)

File-level global `State` holds two `Arena` values (double-buffered), an `arena_index: u1`,
a `build_index: u64` frame counter, a box hash table (`[4096]?*Box` with chained buckets
via `hash_next`/`hash_prev`), the `Stacks`, a `root: ?*Box`, `screen_size`, and an
`active: bool` guard that tracks whether a build is in progress.

Two init paths:
- `init_all()` — allocates two internal arenas for the full `begin_build`/`end_build`
  cycle with cross-frame persistence. Paired with `deinit()`.
- `init(arena)` — lightweight single-arena init for tests that don't need persistence.

`begin_build(screen_w, screen_h)` bumps `build_index`, swaps `arena_index`, clears the
current arena, resets stacks, builds a root box sized to the screen, and pushes it as
parent. Returns `*Box` (cannot fail — box allocation panics on OOM).

`end_build()` runs layout via `layout_mod.layout(root, w, h)`, then prunes stale boxes
from the hash table (any box whose `last_touched_build_index < build_index`).

`get_root()` returns the current frame's root box. `get_build_arena()` exposes the
current frame's arena for callers that need to allocate alongside the build.

### 2.4 — Box Construction (`src/ui/ui.zig`)

`build_box(string, extra_flags) *Box` (panics on OOM):
1. Allocate a fresh `Box` on the current arena (panics on OOM) and zero it.
2. Parse the tag string for display/hash portions.
3. Compute `Key` from hash string seeded with parent key.
4. Look up key in the box hash table. If found, copy persistent fields from the
   previous frame's box (`hot_t`, `active_t`, `disabled_t`, `focus_hot/active_t`,
   `view_off`, `view_off_target`, `view_bounds`, `first_touched_build_index`) and
   compute `position_delta`. Remove the old entry from the table.
5. Stamp `last_touched_build_index = build_index`.
6. Apply all stack tops (flags merged with `extra_flags`, axis, sizes, colors, etc.).
7. Insert into box hash table.
8. Link as child of current parent.
9. Auto-pop all stacks with `auto_pop` set.

`push_parent_box` (returns `*Box`) combines `build_box` + `push_parent`.
`spacer(axis, amount)` (returns `void`) builds an empty box with appropriate fixed sizes.

String helpers: `arena_dupe`, `arena_print` (uses scratch arena for intermediate
formatting, then copies to the frame arena).

### 2.5 — Layout Algorithm (`src/ui/layout.zig`)

`layout(root, screen_w, screen_h)` sets the root rect to screen bounds, then runs five
passes for the X axis followed by five passes for the Y axis. The `axis` parameter is
`comptime axis: Axis` (where `Axis` is `enum(u1) { x, y }`) so all indexing compiles
to direct field access and comparisons read as `axis == .x` / `axis == b.child_layout_axis`.

**Pass 1 — Standalone Sizes**: Pre-order walk. `cells` → `fixed_size[axis] = value`.
`text_content` → `fixed_size[x] = display_string.len + size.value + text_padding * 2`,
`fixed_size[y] = 1 + size.value`. Display width currently counts bytes (correct for
ASCII; proper unicode / East Asian Width handling is a TODO).

**Pass 2 — Upwards-Dependent Sizes**: Pre-order walk. `parent_pct` → walk up to the
nearest ancestor whose size kind is `cells`, `text_content`, `null`, or an already-resolved
`parent_pct`. Use that ancestor's `fixed_size` minus border insets as the available space,
then `fixed_size[axis] = @round(avail * frac)`.

**Pass 3 — Downwards-Dependent Sizes**: Post-order (recursive). `children_sum` along
the layout axis sums non-floating children's `fixed_size`; perpendicular takes the max.
Border insets are added to the total.

**Pass 4 — Constraint Enforcement**: Pre-order. Along the layout axis: if children's
total exceeds available space, the overflow is distributed proportionally among children
with `strictness < 1.0`, weighted by `(1 - strictness) * (child_size / shrinkable_total)`.
Children with `strictness = 1.0` never shrink. On the cross axis: children are clamped to
the parent's available size unless `allow_overflow_x/y` is set.

**Pass 5 — Positioning**: Pre-order. Along the layout axis a cursor accumulates position;
on the cross axis children start at the border inset. Floating children use `fixed_position`
directly. `view_off` is subtracted from the cursor for scroll support. Sizes are snapped
to integer via `@trunc` and the final `Rect` is written with `u16` clamping.

After positioning, each child's `fixed_size[axis]` is re-synced from the snapped rect so
downstream layout on the other axis sees consistent integer sizes.

### 2.6 — Demo (`src/tui_test/basic_ui.zig`)

Interactive TUI app (`zig build testing -- basic_ui`) exercising the full stack: 3 counters
with +/− buttons, reset, theme toggle, mouse + keyboard focus navigation. Originally
contained its own minimal layout engine and interaction handling; those were removed in
Phase 3 when the real `layout.zig` and `interaction.zig` modules replaced them. Retains
its own draw pass (throwaway — kept until Phase 4 `draw.zig` exists).

### 2.7 — Validation

Unit tests in `src/ui/ui.zig`:
- Stack push/pop/top, set_next auto-pop behavior
- `build_box` applies stack tops and auto-pops set_next entries
- `push_parent_box` links children correctly
- `parse_tag` `##`/`###` separators
- `Rect.intersect` overlap and no-overlap cases
- Cross-frame persistence: `begin_build`/`end_build` twice, verify `hot_t` and `view_off`
  carry over on matching keys
- Stale box pruning: box not rebuilt on frame 2 is absent from hash table after `end_build`
- `begin_build` creates root, `end_build` runs layout, verify child rects

Unit tests in `src/ui/layout.zig`:
- Three equal-width children in a 30-cell row → each gets 10
- `parent_pct(0.5)` child in a 20-cell parent → child gets 10
- `children_sum` container sums 5 + 10 + 8 = 23, cross axis = max = 8
- Overflow with strictness: strict child keeps 20, flex child absorbs reduction
- Nested row inside column: verify both levels of rects
- Floating box positioned at absolute coordinates
- Border insets reduce available space for children
- `text_content` sizing: "Hello" + padding 1 → width 7, height 1

---

## Phase 3: UI Module — Interaction ✅

**Goal**: Implement event processing and signal generation so boxes can respond to
keyboard and mouse input. Integrate into demos, replacing their throwaway interaction code.

**Files**: `src/ui/interaction.zig` (new), `src/ui/ui.zig` (minor additions),
`src/ui/layout.zig` (bugfix + test), `src/tui_test/basic_ui.zig` (refactored),
`src/tui_test/scroll.zig` (new demo)

### 3.1 — Event Conversion

`push_event(arena, InputEvent)` converts a terminal `InputEvent` into a `UiEvent` and
appends it to the frame's arena-allocated linked list (`UiEventList`). Event kinds are
more granular than the plan originally sketched:

```
const UiEventKind = enum { mouse_press, mouse_release, key_press, text, scroll, mouse_move };

const UiEvent = struct {
    kind: UiEventKind,
    key: term.Key,
    codepoint: u21,
    mods: term.Modifiers,
    mouse_button: term.MouseButton,
    pos: [2]u16,
    scroll: [2]i16,
    consumed: bool,
    next: ?*UiEvent,           // intrusive linked list
};
```

Codepoint key-presses with no modifiers are classified as `.text`; everything else is
`.key_press`. Mouse events map to `.mouse_press` / `.mouse_release` / `.mouse_move` /
`.scroll`. Terminal `.resize` events are not converted — they are handled separately by
`Term.check_resize` in the frame loop.

`begin_frame()` clears the event list. `reset()` zeroes all interaction state.

### 3.2 — Signal Computation

`signal_from_box(box: *Box) Signal` iterates the event list and produces a signal:

1. Mouse press in bounds + `clickable` + topmost (`hot_box_key`) → `left_pressed` /
   `right_pressed`, sets the per-button `active_box_key` (`[2]Key`, indexed by left/right)
2. Mouse release while active → `left_released` / `right_released`; if still in bounds →
   `left_clicked` / `right_clicked`
3. Scroll events in bounds on `view_scroll` boxes → accumulate `scroll[0..1]`
4. Keyboard enter/space on focused `keyboard_clickable` box → `keyboard_pressed` + `commit`
5. Consumed events are skipped; events are marked consumed when handled
6. `hovering` set when mouse is in bounds and box is the hot box; `mouse_over` when just
   in bounds
7. `dragging` set while an active press is held

Animates `hot_t`, `active_t`, `focus_hot_t`, `focus_active_t`, `disabled_t` each frame
via `animate(current, target_on, step)` with a fixed rate of 15 × (1/60) per call.

`update_hot_box(root)` walks the tree pre-order and picks the deepest `clickable`,
non-disabled box under the current mouse position as `hot_box_key`.

### 3.3 — Focus Navigation

`process_events(root)` runs three sub-passes in order:

1. **`update_hot_box`** — find hot box under mouse (see above).
2. **`process_mouse_focus`** — on `mouse_press`, find the deepest `focus_hot`/`focus_active`
   box at the click position and set `focus_hot_key`.
3. **`process_focus_navigation`** — collect all focusable boxes in tree order (depth-first
   pre-order, up to 256). Tab / Shift-Tab cycle `focus_hot_key` through the list.
   `focus_active_key` follows `focus_hot_key` when the focused box has `focus_active`.

Arrow-key navigation between siblings was deferred (not needed by current demos).

### 3.4 — Demo Integration

**`basic_ui.zig`** (renamed from `ui_demo.zig`): Removed the local layout engine
(`layout_tree`, `resolve_sizes`, `position_children`), local interaction system
(`FocusableList`, `hit_test`, `signal_for_box`), and per-frame event switch. Now uses:
- `ui.begin_build` / `ui.end_build` (which calls `layout_mod.layout`)
- `interaction.begin_frame` / `interaction.push_event` / `interaction.process_events`
- `interaction.signal_from_box` per interactive box in `handle_all_signals`
- Stable `##` hash tags on the theme button to preserve focus across label changes

**`scroll.zig`** (new): Virtualized scrollable list of 1000 items demonstrating
`view_scroll`, mouse wheel + keyboard scrolling (up/down/page/home/end), click-to-select,
and a scrollbar thumb. Uses `interaction.signal_from_box` for scroll deltas and item clicks.

Both demos share a common frame loop pattern:
1. `interaction.begin_frame()` clears events
2. `poll_event` → `is_quit` check → `push_event`; drain remaining events (breaking on
   `.resize` to avoid infinite loop since `poll_event` returns `.resize` without clearing
   the flag)
3. `check_resize` / `clear` / `begin_build` / build / `end_build`
4. `process_events` / signal handling
5. draw / `flush`

### 3.5 — Layout Bugfix

`layout.zig` `ancestor_resolved_size`: fixed to return 0 when encountering a
`children_sum` ancestor, preventing `parent_pct` children from resolving against the root
when nested inside `children_sum` containers (the pct child would get screen-height
instead of the row height set by fixed-size siblings). The position pass already handles
`fixed_size ≤ 0` on the cross axis by filling to available space, so this produces the
correct result. Added a regression test covering the exact pattern from `basic_ui`'s
counter rows.

### 3.6 — Validation

Unit tests in `src/ui/interaction.zig`:
- Mouse click inside a button box → `left_clicked` signal
- Mouse click outside a button box → no signal
- Tab cycles focus between three focusable boxes
- Keyboard enter on focused box → `keyboard_pressed` signal
- Scroll event on scrollable box → scroll delta in signal
- Scroll event outside scrollable box → no delta
- Disabled box → no signal
- Mouse click transfers focus to clicked focusable box
- Right click inside a button box → `right_clicked` signal
- Press inside, release outside → `released` but not `clicked`

Unit test in `src/ui/layout.zig`:
- `parent_pct` child inside `children_sum` row fills sibling height (3), not root height (24)


---

## Phase 4: TUI Draw Layer ✅

**Goal**: Walk the computed box tree and render it into the cell grid from Phase 1.

**Files**: `src/tui/draw.zig` (grid primitives, color effects, text measurement),
`src/ui/render.zig` (tree walk, box rendering)

Split across two modules: `draw.zig` lives in the `tui` layer and provides low-level
grid operations that know nothing about UI boxes. `render.zig` lives in the `ui` layer,
walks the box tree, and calls into `draw` primitives.

Also unified the color type — `ui.Color` and `ui.Ansi` are now re-exports of
`tui.term.Color` / `tui.term.Ansi` instead of separate duplicate definitions.
Moved `Term.init` and the `emit*` ANSI helpers from methods to free functions
(aligning with the project style of preferring free functions over methods).
Removed inline draw code from demo apps (`basic_ui.zig`, `scroll.zig`) — they now
call `ui.render.render(&grid, root)` with a `tui.draw.Grid.from_term(&t)`.

### 4.1 — Grid Primitives (`src/tui/draw.zig`)

`Grid` struct: a plain data view over a `[]Cell` buffer with `cols`/`rows`. Constructed
from a `Term` via `Grid.from_term(&t)` (borrows the back buffer).

Free functions on `Grid`:
- `cell_at(grid, col, row) → ?*Cell` — bounds-checked single cell access
- `write_cell(grid, col, row, cell)` — write a single cell (no-op if out of bounds)
- `fill_rect(grid, col, row, w, h, cell)` — fill a rectangular region, clamped to bounds

Also in `draw.zig`:
- `brighten_color(color, amount) → Color` — brightens RGB by `amount * 80` per channel
  (clamped to 255); promotes dark ANSI colors (0–7) to bright (8–15)
- `text_display_width(text) → u16` — UTF-8 aware display width
- `codepoint_width(cp) → u16` — single codepoint width (0 for control, 2 for CJK/wide, 1 otherwise)
- `grid_to_string(grid, buf) → []const u8` — test helper, dumps grid to printable string

### 4.2 — Tree Walk (`src/ui/render.zig`)

Pre-order depth-first walk (parent drawn first, children overlay on top). A `RenderCtx`
carries the grid pointer, a fixed-size clip stack (max 64 deep), and a deferred floating
box list (max 64). The public entry point is `render(grid, root)`.

For each box: skip if zero-sized, defer if floating (unless already at top level),
then draw background → border → text in order. After drawing, if `clip` flag is set,
push the box rect as a clip, recurse into children, then pop.

### 4.3 — Background Fill

`draw_background` flag → fill `box.rect` with `box.bg_color`, intersected with the
current clip rect. If `active_t > 0` and `draw_active_effects`, brighten bg by
`active_t * 0.3`. Else if `hot_t > 0` and `draw_hot_effects`, brighten bg by
`hot_t * 0.15`.

### 4.4 — Border Rendering

`draw_border` flag → write box-drawing characters along edges of `box.rect`:

Normal borders:
```
┌──────┐
│      │    Uses: ─ │ ┌ ┐ └ ┘
│      │
└──────┘
```

Focused borders (`focus_hot_t > 0.5`) use double-line characters with bold attribute:
```
╔══════╗
║      ║    Uses: ═ ║ ╔ ╗ ╚ ╝
║      ║
╚══════╝
```

Individual side flags (`draw_side_top`, etc.) allow partial borders (e.g. just a top
separator line). Corner characters are only placed when both adjacent sides are drawn.
Hot effect brightens `border_color` by 0.2.

### 4.5 — Text Rendering

`draw_text` flag → write `box.display_string` into the cell grid within `box.rect`:
- Compute inner area by subtracting border insets (if border sides are drawn) and `text_padding`
- Vertically center text within the inner area
- Apply `text_align` (left/center/right) to determine starting column
- Iterate codepoints with `codepoint_width` for accurate column tracking
- Truncate if text is wider than available space; write `…` (U+2026) at the cutoff point
- Wide characters (CJK/emoji, 2 columns) write a zero-codepoint spacer in the second cell
- Apply `box.fg_color`; bg inherits from `box.bg_color` if `draw_background` is set
- Hot/active: brighten bg, set bold attribute
- Focused (`focus_hot_t > 0.5`): bold attribute

### 4.6 — Clip Stack

`clip` flag → push `Rect.intersect(current_clip, box.rect)` onto the clip stack. All
child drawing is clamped to this rectangle via `clipped_write` and `clipped_fill` helpers.
Pop when leaving the box's subtree. Stack initialized with a full-screen clip rect.

### 4.7 — Hot/Active Effects

- `draw_hot_effects` + `hot_t > 0` → brighten bg by `hot_t * 0.15`, bold text
- `draw_active_effects` + `active_t > 0` → brighten bg by `active_t * 0.3`, bold text
- Active takes priority over hot (else-if, not both)
- These are applied in both `render_background` and `render_text`

### 4.8 — Floating Boxes

Floating boxes (`floating_x` or `floating_y`) encountered during the tree walk are
deferred into the `RenderCtx.floating` array. After the main tree walk completes, they
are rendered in order with the clip stack reset to a full-screen rect so they draw on
top of everything.

### 4.9 — Validation

Unit tests in both `draw.zig` and `render.zig`:
- `draw.zig`: `cell_at` bounds, `write_cell`, `fill_rect` with clamping,
  `grid_to_string`, `text_display_width`, `codepoint_width`, `brighten_color` (RGB,
  ANSI promotion, default passthrough, clamp to 255)
- `render.zig`: background fills rect, border renders box-drawing characters, text
  left/center/right alignment, truncation with ellipsis, clip restricts child drawing,
  border with text inside, children draw on top of parent, partial border (top-only)

Demo apps (`basic_ui.zig`, `scroll.zig`) updated to use the new render system as
end-to-end validation.

---

## Phase 5: Frame Loop Integration

**Goal**: Wire everything together into a working frame loop.

**Files**: `src/bin/bin.zig` (replaces the current stub)

### 5.1 — Frame Loop

```
pub fn run() !void {
    // init terminal backend
    var t = try term.init(&arena);
    defer t.deinit();

    // init UI state
    try ui.init_all();
    defer ui.deinit();

    var running = true;
    while (running) {
        // 1. poll input
        const event = try t.poll_event(timeout_ms);

        // 2. convert to UI events
        ui.interaction.convert_event(event);

        // 3. begin build
        ui.begin_build(t.cols, t.rows, dt);

        // 4. application builds UI
        app_build();

        // 5. end build (layout)
        const root = ui.end_build();

        // 6. draw to cell grid
        var grid = tui.draw.Grid.from_term(&t);
        ui.render.render(&grid, root);

        // 7. flush (diff + write)
        try t.flush();

        // 8. wait for next event or timeout
        if (!ui.animating()) t.wait_for_input();
    }
}
```

### 5.2 — Delta Time

Track time between frames for animation floats. Use `std.time.Instant`.
For TUI, most animations are instant (`rate = 1.0`), but smooth scroll can use real dt.

### 5.3 — Validation

End-to-end test: start the TUI, display a simple UI (a bordered box with text and
a focusable region), navigate with Tab, click with Enter, verify focus cycling works.

---

## Phase 6: Widget Submodule

**Goal**: Build common widget helpers as a submodule within the `ui` module, layered on
top of the core box-building API. These are thin wrappers — the application can always
bypass them and compose boxes directly.

**Files**: `src/ui/widgets.zig`

### 6.1 — Basic Widgets

- **`label(string)`** — non-interactive text box
- **`button(string) Signal`** — clickable box with border, background, text
- **`spacer(size)`** — invisible box for layout spacing
- **`separator()`** — horizontal or vertical line (uses box-drawing chars via flag)

### 6.2 — Text Input

- **`line_edit(buffer, cursor) Signal`** — single-line editable text field
  - Draws text with cursor position indicator
  - Handles text input events, backspace, delete, home/end, left/right
  - Selection (shift+arrows) is a stretch goal

### 6.3 — Scroll List

- **`scroll_list_begin(count, row_height, scroll_pt)` / `scroll_list_end()`**
  - Virtual scrolling: only builds boxes for visible rows
  - Scroll bar indicator
  - Mouse wheel + keyboard (page up/down, arrow keys) scroll support

### 6.4 — Container Widgets

- **`panel_begin(title)` / `panel_end()`** — bordered container with title
- **`collapsible_header(title, open) Signal`** — expandable section

### 6.5 — Validation

- `button("OK")` returns a signal with `left_clicked` when clicked
- `label("hello")` produces a box with correct text and no interaction flags
- `scroll_list` with 100 items only builds boxes for the visible window
- Build a demo application exercising every widget as an ongoing test harness

---

## Dependency Graph

```
Phase 1: Terminal Backend ✅ ─┐
                              │
Phase 2: UI Core ✅ ──────────┤
                              │
Phase 3: Interaction ✅ ──────┤ (depends on 2, 1 for events)
                              │
Phase 4: TUI Draw Layer ✅ ───┤ (depends on 1, 2, 3 for focus)
                              │
Phase 5: Frame Loop ──────────┤ (depends on all above)
                              │
Phase 6: Widget Submodule ────┘ (depends on 5)
```

Phases 3 and 4 were developed roughly in parallel. Phase 4 ended up depending on
Phase 3's `focus_hot_t` for focused-border styling. Phase 5 integrates everything.
Phase 6 builds convenience widgets on top of the working frame loop.

---

## File Layout

```
src/ui/                          # ui build module
├── ui.zig                       # Root: types, stacks, state, box construction
├── layout.zig                   # 5-pass layout algorithm
├── interaction.zig              # Event processing, signal_from_box, focus nav
├── render.zig                   # Box tree → grid rendering (clip, bg, border, text)
└── widgets.zig                  # button, label, line_edit, etc. (Phase 6, not yet created)

src/tui/                         # tui build module — terminal-specific
├── tui.zig                      # Root: re-exports term and draw
├── term.zig                     # Terminal backend (raw mode, input, cell grid, flush)
├── draw.zig                     # Grid primitives, color effects, text measurement
├── RADDBG_UI_REPORT.md          # Architecture analysis (reference)
└── IMPLEMENTATION_PLAN.md       # This file

src/tui_test/                    # tui_test build module — interactive test apps
├── tui_test.zig                 # Entry point: dispatches on CLI arg to test runners
├── grid.zig                     # Phase 1 validation: checkerboard + cursor movement
├── basic_ui.zig                 # Phase 2–4 validation: counters, focus, theme toggle
└── scroll.zig                   # Phase 3–4 validation: virtualized scroll list, selection
```

The split across two build modules is intentional. The `ui` module knows about terminal
types only through `tui.term.Color` (re-exported as `ui.Color`), which serves as the
single color type across both layers. `render.zig` lives in `ui` because it operates on
box-tree semantics and clip rects — it calls into `tui.draw` only for low-level grid
writes. The `tui` module provides the terminal-specific bridge: `term.zig` handles raw
I/O, `draw.zig` provides grid primitives and color utilities, and `tui.zig` re-exports
both. The application imports both modules.

The `tui_test` module is a separate executable (`zig build testing -- <name>`) containing
interactive test/demo applications. Each test is a standalone file with a `run()` function,
registered in a dispatch table in `tui_test.zig`. This keeps validation demos out of the
library modules while making them easy to build and run.

---

## Design Decisions

### Integer vs Float for Layout

The layout algorithm uses `f32` internally (matching raddbg) so that `parent_pct` and
`strictness` math works naturally. Final rects are snapped to integer cell coordinates
at the end of Pass 5. This avoids accumulated rounding errors during intermediate passes.

### Arena Allocation

All per-frame data (box nodes, strings, event lists) is arena-allocated using the project's
`base.Arena`. Two arenas are double-buffered so that previous-frame boxes remain accessible
for state persistence. This matches raddbg's approach and integrates with the existing base layer.

### Comptime Stack Generation

Rather than raddbg's mdesk code generation, use Zig's comptime to generate the ~15 TUI-relevant
stacks from a declaration tuple. Each stack is a fixed-capacity array (e.g. 64 entries) stored
inline in the `State` struct — no heap allocation, no pointers to chase.


### No Threads

The entire TUI runs on a single thread. Input polling uses non-blocking I/O with a timeout.
This keeps the implementation simple and avoids synchronization. If background work is needed
(e.g. async data loading), it communicates via a channel/queue that the frame loop checks.
