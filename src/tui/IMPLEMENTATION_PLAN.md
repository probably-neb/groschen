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
    .{ .name = "tui", .path = "src/tui/tui.zig" },
    .{ .name = "ui",  .path = "src/ui/ui.zig" },
    .{ .name = "base", .path = "src/base/base.zig" },
};
```

---

## Phase 1: Terminal Backend

**Goal**: Own the terminal. Enter/exit alternate screen + raw mode cleanly, detect size,
parse input, and flush a cell grid to the screen with minimal I/O.

**Files**: `src/tui/term.zig`

### 1.1 — Raw Mode & Alternate Screen

- Save and restore original termios state
- Enter raw mode (disable echo, canonical mode, signal generation)
- Enter alternate screen (`\x1b[?1049h`) on init, exit (`\x1b[?1049l`) on deinit
- Hide cursor on init, show on deinit
- Ensure cleanup runs on panic / signal (SIGINT, SIGTERM) via a global handler or `defer`

### 1.2 — Terminal Size

- Query terminal size via `ioctl(TIOCGWINSZ)`
- Handle `SIGWINCH` to detect resize (set an atomic flag, check at frame top)
- Expose `cols: u16, rows: u16`

### 1.3 — Cell Grid

```
const Cell = struct {
    codepoint: u21 = ' ',
    fg: Color = .default,
    bg: Color = .default,
    attrs: Attrs = .{},
};

const Color = union(enum) {
    default,
    ansi: u8,        // 0-15 basic, 16-255 extended
    rgb: [3]u8,      // 24-bit truecolor
};

const Attrs = packed struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    reverse: bool = false,
    strikethrough: bool = false,
};
```

- 2D grid backed by a flat `[]Cell` arena allocation
- `fill_rect(rect, cell)` — fill a rectangular region
- `write_text(col, row, max_width, string, fg, bg, attrs)` — write UTF-8 into cells,
  return number of columns consumed. Handle wide characters (mark second cell as continuation).
- `clear()` — reset all cells to default

### 1.4 — Grid Diffing & Flush

- Compare current grid against previous grid cell-by-cell
- Emit minimal ANSI escape sequences:
  - Track cursor position; only emit movement when non-sequential
  - Track current fg/bg/attrs; only emit SGR when style changes
  - Batch writes into a buffered writer, flush once at end
- Use CSI sequences for cursor positioning (`\x1b[row;colH`)
- Use SGR sequences for styling (`\x1b[38;2;r;g;bm` for truecolor fg, etc.)
- Double-buffer: swap current/previous grids after flush

### 1.5 — Input Parsing

- Read from stdin in non-blocking mode (poll with timeout)
- Parse ANSI escape sequences into structured events:

```
const InputEvent = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    paste: []const u8,
    resize,
};

const KeyEvent = struct {
    key: Key,              // enum: letters, arrows, tab, enter, escape, f1-f12, etc.
    mods: Modifiers,       // shift, ctrl, alt
    text: ?[]const u8,     // UTF-8 bytes for text input (null for special keys)
};

const MouseEvent = struct {
    kind: enum { press, release, move, scroll_up, scroll_down },
    button: enum { left, middle, right, none },
    col: u16,
    row: u16,
    mods: Modifiers,
};
```

- Enable mouse reporting (`\x1b[?1006h` SGR mouse mode)
- Enable bracketed paste (`\x1b[?2004h`)
- Parse Kitty keyboard protocol if available, fall back to legacy

### 1.6 — Validation

Write a small test harness that:
1. Enters alternate screen
2. Fills the cell grid with a colored checkerboard pattern
3. Responds to keyboard input by moving a highlighted cell
4. Handles resize
5. Exits cleanly on `q` or Ctrl-C

---

## Phase 2: UI Module — Data Structures

**Goal**: Define the core types that the entire UI system operates on. These are the Zig
equivalents of raddbg's `UI_Box`, `UI_Key`, `UI_Size`, `UI_Signal`, and `UI_State`.

**Files**: `src/ui/ui.zig`, `src/ui/key.zig`, `src/ui/box.zig`, `src/ui/signal.zig`

### 2.1 — Key

```
const Key = struct {
    value: u64,

    const zero: Key = .{ .value = 0 };

    fn from_string(seed: u64, string: []const u8) Key { ... }
    fn is_zero(self: Key) bool { ... }
    fn eql(self: Key, other: Key) bool { ... }
};
```

- Hash function: use a good 64-bit hash (e.g. wyhash or FNV-1a)
- Seed with parent key to create hierarchical keys
- Parse `##` and `###` separators to split display text from hash portion

### 2.2 — Size

```
const SizeKind = enum { null, cells, text_content, parent_pct, children_sum };

const Size = struct {
    kind: SizeKind = .null,
    value: f32 = 0,
    strictness: f32 = 1,
};
```

Helper constructors: `Size.cells(n, strictness)`, `Size.text(pad, strictness)`,
`Size.pct(frac, strictness)`, `Size.children(strictness)`.

### 2.3 — BoxFlags

A packed struct (or integer bitfield) with all relevant flags. Drop GPU-only flags from raddbg.

Keep:
- `clickable`, `keyboard_clickable`, `view_scroll`, `focus_hot`, `focus_active`
- `draw_background`, `draw_border`, `draw_text`, `draw_hot_effects`, `draw_active_effects`
- `draw_side_top`, `draw_side_bottom`, `draw_side_left`, `draw_side_right`
- `clip`, `overflow_x`, `overflow_y`
- `floating_x`, `floating_y`
- `allow_overflow_x`, `allow_overflow_y`
- `disabled`, `focus_nav_skip`
- `has_display_string` (for `##` separator support)

Drop: `draw_drop_shadow`, `draw_background_blur`, `draw_bucket`, `draw_text_fastpath_codepoint`

### 2.4 — Box

```
const Box = struct {
    // hash table links
    hash_next: ?*Box = null,
    hash_prev: ?*Box = null,

    // tree links
    first: ?*Box = null,
    last: ?*Box = null,
    next: ?*Box = null,
    prev: ?*Box = null,
    parent: ?*Box = null,
    child_count: u32 = 0,

    // identity & config (set during build)
    key: Key = Key.zero,
    flags: BoxFlags = .{},
    string: []const u8 = "",
    display_string: []const u8 = "",    // portion before ## if present
    text_align: TextAlign = .left,
    pref_size: [2]Size = .{ .{}, .{} }, // [x, y]
    child_layout_axis: Axis = .y,
    fixed_position: [2]f32 = .{ 0, 0 },
    fixed_size: [2]f32 = .{ 0, 0 },
    min_size: [2]f32 = .{ 0, 0 },

    // styling
    bg_color: Color = .default,
    fg_color: Color = .default,
    border_color: Color = .default,
    text_padding: u16 = 0,

    // computed by layout
    rect: Rect = .{},
    position_delta: [2]f32 = .{ 0, 0 },

    // persistent state (survives across frames)
    first_touched_build_index: u64 = 0,
    last_touched_build_index: u64 = 0,
    hot_t: f32 = 0,
    active_t: f32 = 0,
    disabled_t: f32 = 0,
    focus_hot_t: f32 = 0,
    focus_active_t: f32 = 0,
    view_off: [2]f32 = .{ 0, 0 },
    view_off_target: [2]f32 = .{ 0, 0 },
    view_bounds: [2]f32 = .{ 0, 0 },
};
```

### 2.5 — Rect

```
const Rect = struct {
    col: u16 = 0,
    row: u16 = 0,
    w: u16 = 0,
    h: u16 = 0,

    fn contains(self: Rect, col: u16, row: u16) bool { ... }
    fn intersect(self: Rect, other: Rect) Rect { ... }
};
```

### 2.6 — Signal

```
const Signal = struct {
    flags: SignalFlags,
    mouse_pos: [2]u16,
    scroll: [2]i16,
};

const SignalFlags = packed struct {
    left_pressed: bool = false,
    left_released: bool = false,
    left_clicked: bool = false,
    right_pressed: bool = false,
    right_clicked: bool = false,
    keyboard_pressed: bool = false,
    hovering: bool = false,
    mouse_over: bool = false,
    dragging: bool = false,
    commit: bool = false,
    // ... as needed
};
```

### 2.7 — Validation

Unit tests for:
- Key hashing determinism, `##`/`###` parsing
- Size helper constructors
- Rect intersection/containment
- Box tree linking (add child, remove child, verify traversal order)

---

## Phase 3: UI Module — Stacks & Box Construction

**Goal**: Implement the implicit state stack system and the box builder API that lets
application code declare a tree of boxes each frame.

**Files**: `src/ui/stacks.zig`, `src/ui/build.zig`, extends `src/ui/ui.zig`

### 3.1 — Stack System

Use Zig comptime to generate all stacks from a single declaration table:

```
const stack_decls = .{
    .{ "parent",            *Box,      null },
    .{ "child_layout_axis", Axis,      .y },
    .{ "pref_width",        Size,      Size.cells(10, 1) },
    .{ "pref_height",       Size,      Size.cells(1, 1) },
    .{ "flags",             BoxFlags,  .{} },
    .{ "bg_color",          Color,     .default },
    .{ "fg_color",          Color,     .default },
    .{ "border_color",      Color,     .default },
    .{ "text_padding",      u16,       0 },
    .{ "text_align",        TextAlign, .left },
    .{ "focus_hot",         FocusKind, .null },
    .{ "focus_active",      FocusKind, .null },
    .{ "fixed_x",           f32,       0 },
    .{ "fixed_y",           f32,       0 },
    .{ "fixed_width",       f32,       0 },
    .{ "fixed_height",      f32,       0 },
    .{ "min_width",         f32,       0 },
    .{ "min_height",        f32,       0 },
};
```

Each stack provides:
- `push(value) -> old_top` — push value, return previous top
- `pop() -> popped` — pop and return
- `top() -> current` — peek at current value
- `set_next(value)` — push, auto-pop after next box construction

A stack entry has a flag to mark "auto-pop" entries. After each `build_box` call,
all stacks with an auto-pop entry at the top get popped.

### 3.2 — State

The `State` struct holds all per-frame and persistent data:

```
const State = struct {
    build_arenas: [2]*Arena,
    build_index: u64,
    current_arena_index: u1,

    // box hash table (for cross-frame persistence)
    box_table: [BOX_TABLE_SIZE]?*Box,
    box_free_list: ?*Box,

    // stacks (generated via comptime)
    stacks: Stacks,

    // frame parameters
    screen_size: [2]u16,
    events: *EventList,
    dt: f32,

    // interaction state
    hot_key: Key,
    active_key: [3]Key,      // per mouse button
    focus_hot_key: Key,
    focus_active_key: Key,
};
```

Double-buffered arenas: each frame, the "current" arena is reset. Boxes from the
previous frame survive in the other arena until pruned.

### 3.3 — Box Construction

```
fn build_box_from_string(flags: BoxFlags, string: []const u8) *Box { ... }
fn build_box_from_key(flags: BoxFlags, key: Key) *Box { ... }
```

Steps:
1. Compute key from string (seeded with parent key)
2. Look up in hash table — reuse if found, allocate if not
3. Zero per-build fields, copy persistent fields from previous frame's box
4. Apply all stack tops to the box (flags, sizes, colors, etc.)
5. Link as child of current parent
6. Pop all auto-pop stack entries
7. Return the box

### 3.4 — Scoped Helpers

Zig doesn't have C's `DeferLoop`, but we can use a struct with `init`/`deinit`:

```
const Row = struct {
    fn open() void {
        push_child_layout_axis(.x);
        // push a container box as parent
    }
    fn close() void {
        pop_parent();
        pop_child_layout_axis();
    }
};

// Usage:
{
    Row.open();
    defer Row.close();
    // children laid out horizontally
}
```

Or a `with_*` pattern that takes a callback — whichever is more ergonomic. Evaluate both.

### 3.5 — Validation

Test that:
- Building a tree of boxes produces the correct parent/child/sibling links
- `set_next` auto-pops after one box
- The hash table persists boxes across frames (call begin/build/end twice, check same pointer)
- Stack push/pop ordering is correct

---

## Phase 4: UI Module — Layout

**Goal**: Implement the 5-pass layout algorithm that computes integer cell rectangles
for every box in the tree.

**Files**: `src/ui/layout.zig`

### 4.1 — Pass 1: Standalone Sizes

For each axis, walk all boxes. If `pref_size[axis].kind` is:
- `cells` → `fixed_size[axis] = value`
- `text_content` → `fixed_size[axis] = display_string.len + text_padding * 2` (for X axis),
  `1` (for Y axis, since a single line of text is 1 row)

Handle wide characters in text width measurement (count display columns, not bytes).

### 4.2 — Pass 2: Upwards-Dependent Sizes

Walk all boxes. If `pref_size[axis].kind` is `parent_pct`:
- Walk up to nearest ancestor with a determined size
- `fixed_size[axis] = @round(ancestor.fixed_size[axis] * value)`

### 4.3 — Pass 3: Downwards-Dependent Sizes

Walk all boxes in **post-order** (children before parents). If `pref_size[axis].kind` is `children_sum`:
- Along layout axis: sum children's `fixed_size[axis]`
- Perpendicular to layout axis: max of children's `fixed_size[axis]`
- Skip floating children

### 4.4 — Pass 4: Constraint Enforcement

For each parent along its layout axis:
- Sum children's `fixed_size[axis]`
- If sum > parent's `fixed_size[axis]`, distribute overflow proportionally by `(1 - strictness)`
- Children with `strictness = 1.0` don't shrink
- On the non-layout axis, clamp each child to parent's size (unless `allow_overflow`)

Snap all sizes to integers after this pass.

### 4.5 — Pass 5: Positioning

Walk the tree. For each parent's children:
- Along layout axis: place sequentially, accumulating position
- Perpendicular: position = 0 (relative to parent)
- Floating children: use `fixed_position` directly
- Apply `view_off` scroll offset
- Compute final `rect` as parent origin + position

### 4.6 — End-of-Build

`end_build()`:
1. Run layout (X axis, then Y axis, all 5 passes each)
2. Prune boxes not touched this frame from the hash table
3. Update animation floats (`hot_t`, `active_t`, etc.) — snap to target for TUI

### 4.7 — Validation

Test cases:
- Three equal-width children in a row, parent = 30 cells → each gets 10
- `parent_pct(0.5)` child in a 20-cell parent → child gets 10
- `children_sum` parent with children of 5, 10, 8 → parent gets 23
- Overflow: children sum to 40, parent is 30, various strictness values
- Nested layouts: row inside column, verify final rects
- Floating box positioned at absolute coordinates

---

## Phase 5: UI Module — Interaction

**Goal**: Implement event processing and signal generation so boxes can respond to
keyboard and mouse input.

**Files**: `src/ui/interaction.zig`

### 5.1 — Event Conversion

Convert terminal `InputEvent` (from Phase 1) into `UiEvent`:

```
const UiEvent = struct {
    kind: enum { press, release, text, scroll, mouse_move },
    key: Key,                // which key/button
    mods: Modifiers,
    pos: [2]u16,             // mouse position in cells
    scroll: [2]i16,
    text: []const u8,
};
```

Build an `UiEventList` (arena-allocated linked list) at the start of each frame.

### 5.2 — Signal Computation

`signal_from_box(box: *Box) Signal`:
1. Iterate over the event list
2. For mouse events: check if `box.rect.contains(event.pos)`
3. For press in bounds + `clickable` flag → set `active_key`, mark pressed
4. For release while active + in bounds → mark clicked
5. For keyboard events: check focus state + `keyboard_clickable` flag
6. For scroll events: check `view_scroll` flag + in bounds → accumulate scroll delta
7. Eat consumed events from the list
8. Compute `hovering`, `mouse_over` based on current mouse position

Update `hot_t` / `active_t` floats based on whether the box is hot/active this frame.

### 5.3 — Focus Navigation

- Track `focus_hot_key` and `focus_active_key` in state
- Tab / Shift-Tab cycle through focusable boxes (those with `focus_hot` or `focus_active` flags)
- Arrow keys navigate between siblings or parent/child depending on layout axis
- Enter / Space on a focused `keyboard_clickable` box → keyboard press signal
- Focus order = tree order (depth-first pre-order)

### 5.4 — Validation

Test:
- Mouse click inside a button box → `left_clicked` signal
- Mouse click outside → no signal
- Tab cycles focus between three focusable boxes
- Keyboard enter on focused box → `keyboard_pressed` signal
- Scroll event on scrollable box → scroll delta in signal


---

## Phase 6: TUI Draw Layer

**Goal**: Walk the computed box tree and render it into the cell grid from Phase 1.

**Files**: `src/tui/draw.zig`

### 6.1 — Tree Walk

Depth-first post-order walk of the box tree (same as raddbg). For each box, interpret
its flags and fill the corresponding region of the cell grid.

### 6.2 — Background Fill

`draw_background` flag → fill `box.rect` region with `box.bg_color`. If `hot_t > 0`,
blend/brighten. If `active_t > 0`, darken or invert.

### 6.3 — Border Rendering

`draw_border` flag → write box-drawing characters along edges of `box.rect`:

```
┌──────┐
│      │    Uses: ─ │ ┌ ┐ └ ┘
│      │
└──────┘
```

Individual side flags (`draw_side_top`, etc.) allow partial borders (e.g. just a top separator line).

When two borders are adjacent, resolve junction characters:
- T-junctions: ├ ┤ ┬ ┴
- Cross: ┼

For a single-height box with a border, the box is at minimum 1 row (the border itself
consumes space). Content is inside the border.

### 6.4 — Text Rendering

`draw_text` flag → write `box.display_string` into the cell grid within `box.rect`:
- Apply `text_padding` (offset from left/right edge)
- Apply `text_align` (left/center/right)
- Truncate if text is wider than available space; append `…` if truncated
- Apply `box.fg_color` and current `box.bg_color` to each cell
- Handle wide characters (CJK/emoji take 2 columns)

### 6.5 — Clip Stack

`clip` flag → push `box.rect` as a clip rectangle. All child drawing is clamped to
this rectangle. Clip rects are intersected (nested clips narrow the visible area).
Pop when leaving the box's subtree.

### 6.6 — Hot/Active Effects

- `draw_hot_effects` + `hot_t > 0` → bold text, brighter bg, or reverse video
- `draw_active_effects` + `active_t > 0` → reverse video or distinct bg color
- These are simple attribute modifications applied on top of the base style

### 6.7 — Floating Boxes

Floating boxes (tooltips, context menus) are drawn last, on top of everything else.
They use absolute positioning and should be clamped to screen bounds.

### 6.8 — Validation

Visual test: build a tree with nested rows/columns, borders, colored backgrounds, and
text. Render to grid. Verify grid contents match expected output (write a `grid_to_string`
helper for test assertions).

---

## Phase 7: Frame Loop Integration

**Goal**: Wire everything together into a working frame loop.

**Files**: `src/tui/tui.zig` (replaces the current stub)

### 7.1 — Frame Loop

```
pub fn run() !void {
    // init terminal backend
    var term = try Term.init();
    defer term.deinit();

    // init UI state
    var ui = try UiState.init(&arena);

    var running = true;
    while (running) {
        // 1. poll input
        const events = try term.poll_events(&arena);

        // 2. convert to UI events
        var ui_events = convert_events(events);

        // 3. begin build
        ui.begin_build(term.size(), &ui_events, dt);

        // 4. application builds UI
        app_build(&ui);

        // 5. end build (layout)
        ui.end_build();

        // 6. draw to cell grid
        ui_draw.draw_tree(ui.root(), &term.grid);

        // 7. flush (diff + write)
        try term.flush();

        // 8. wait for next event or timeout
        if (!ui.animating()) term.wait_for_input();
    }
}
```

### 7.2 — Delta Time

Track time between frames for animation floats. Use `std.time.Instant`.
For TUI, most animations are instant (`rate = 1.0`), but smooth scroll can use real dt.

### 7.3 — Validation

End-to-end test: start the TUI, display a simple UI (a bordered box with text and
a focusable region), navigate with Tab, click with Enter, verify focus cycling works.

---

## Phase 8: Widget Submodule

**Goal**: Build common widget helpers as a submodule within the `ui` module, layered on
top of the core box-building API. These are thin wrappers — the application can always
bypass them and compose boxes directly.

**Files**: `src/ui/widgets.zig`

### 8.1 — Basic Widgets

- **`label(string)`** — non-interactive text box
- **`button(string) Signal`** — clickable box with border, background, text
- **`spacer(size)`** — invisible box for layout spacing
- **`separator()`** — horizontal or vertical line (uses box-drawing chars via flag)

### 8.2 — Text Input

- **`line_edit(buffer, cursor) Signal`** — single-line editable text field
  - Draws text with cursor position indicator
  - Handles text input events, backspace, delete, home/end, left/right
  - Selection (shift+arrows) is a stretch goal

### 8.3 — Scroll List

- **`scroll_list_begin(count, row_height, scroll_pt)` / `scroll_list_end()`**
  - Virtual scrolling: only builds boxes for visible rows
  - Scroll bar indicator
  - Mouse wheel + keyboard (page up/down, arrow keys) scroll support

### 8.4 — Container Widgets

- **`panel_begin(title)` / `panel_end()`** — bordered container with title
- **`collapsible_header(title, open) Signal`** — expandable section

### 8.5 — Validation

- `button("OK")` returns a signal with `left_clicked` when clicked
- `label("hello")` produces a box with correct text and no interaction flags
- `scroll_list` with 100 items only builds boxes for the visible window
- Build a demo application exercising every widget as an ongoing test harness

---

## Dependency Graph

```
                    ┌─ Phase 2: UI Data Structures ─┐
                    │                                │
Phase 1: Terminal ──┤  Phase 3: Stacks & Box Build ──┤ (depends on 2)
    Backend         │                                │
                    │  Phase 4: Layout ──────────────┤ (depends on 3)
                    │                                │
                    │  Phase 5: Interaction ──────────┤ (depends on 3, 1 for events)
                    │                                │
                    └─ Phase 6: TUI Draw Layer ──────┤ (depends on 1, 4)
                                                     │
                       Phase 7: Frame Loop ──────────┤ (depends on all above)
                                                     │
                       Phase 8: Widget Submodule ────┘ (depends on 7)
```

Phases 1 and 2 can be developed in parallel — they live in different modules (`tui` and
`ui` respectively). Phase 3 depends on 2. Phase 4 and 5 depend on 3 and can be developed
in parallel with each other. Phase 6 depends on 1 and 4. Phase 7 integrates everything.
Phase 8 builds the widget submodule on top of the working frame loop.

---

## File Layout

```
src/ui/                          # ui build module — rendering-agnostic
├── ui.zig                       # Root: public API, re-exports core + widgets
├── key.zig                      # Key hashing, ## / ### parsing
├── box.zig                      # Box, BoxFlags, Rect, Size, SizeKind
├── signal.zig                   # Signal, SignalFlags, UiEvent
├── stacks.zig                   # Comptime-generated implicit state stacks
├── build.zig                    # State, box construction, begin/end build
├── layout.zig                   # 5-pass layout algorithm
├── interaction.zig              # Event processing, signal_from_box, focus nav
└── widgets.zig                  # Submodule: button, label, line_edit, etc. (Phase 8)

src/tui/                         # tui build module — terminal-specific
├── tui.zig                      # Root: public API, frame loop, init/deinit
├── term.zig                     # Terminal backend (raw mode, input, cell grid, flush)
├── draw.zig                     # Box tree → cell grid rendering
├── RADDBG_UI_REPORT.md          # Architecture analysis (reference)
└── IMPLEMENTATION_PLAN.md       # This file
```

The split across two build modules is intentional. The `ui` module has zero knowledge of
the terminal and operates purely on abstract cell coordinates — it could back a GUI just
as easily. Within `ui`, the core files (Phases 2–5) provide the box-building and layout
engine, while `widgets.zig` (Phase 8) is a submodule of convenience helpers built on
that core. The `tui` module imports `ui` and provides the terminal-specific bridge:
`term.zig` handles raw I/O, `draw.zig` interprets box flags into cell grid writes, and
`tui.zig` orchestrates the frame loop. The application imports both modules.

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

### Color Strategy

The `ui` module uses an abstract `Color` type (default, indexed, RGB). The `tui` module's
draw layer maps these to actual terminal escape sequences. Support all three tiers:
16-color ANSI, 256-color, and 24-bit truecolor. Detect terminal capability via `COLORTERM`
env var (or similar). The theme system maps semantic colors (e.g. "button background",
"focused border") to `Color` values. Applications set semantic colors; the `tui` draw
layer resolves them to terminal colors.

### No Threads

The entire TUI runs on a single thread. Input polling uses non-blocking I/O with a timeout.
This keeps the implementation simple and avoids synchronization. If background work is needed
(e.g. async data loading), it communicates via a channel/queue that the frame loop checks.
