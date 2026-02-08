# Raddebugger UI System — Architecture Report & TUI Applicability

## Overview

The raddebugger UI (`src/ui/`) is an **immediate-mode, retained-state** box-tree UI system.
Each frame, the application declares a tree of `UI_Box` nodes using builder calls. The system
hashes boxes by key to persist animation/interaction state across frames, runs a constraint-based
layout algorithm, and then a separate draw pass walks the tree to emit GPU draw commands.

The UI layer itself has **zero knowledge of rendering**. It produces a tree of boxes with
computed rectangles. A separate draw layer interprets box flags into draw calls. This clean
separation is the key reason the architecture can be adapted to a terminal.

---

## Layer Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Application  (raddbg/)                                      │
│  Builds the box tree each frame using the UI API             │
├──────────────────────────────────────────────────────────────┤
│  UI Core  (ui/)                                              │
│  Box tree construction, layout, interaction/signals           │
├──────────────────────────────────────────────────────────────┤
│  Draw Layer  (draw/)                                         │
│  Walks box tree, interprets flags, emits rect/text/blur cmds │
├──────────────────────────────────────────────────────────────┤
│  Render Layer  (render/)                                     │
│  GPU backend (D3D11, OpenGL, stub)                           │
└──────────────────────────────────────────────────────────────┘
```

For a TUI, the bottom two layers are replaced entirely. The UI Core layer survives
almost intact, with sizing adapted from pixels to character cells.

---

## Frame Lifecycle

Each frame follows this sequence:

### 1. `ui_begin_build()`
- Resets all implicit-state stacks (parent, axis, sizes, colors, font, etc.)
- Prunes box cache (removes boxes not touched last frame)
- Prunes animation caches (LRU eviction)
- Stores per-frame parameters: window handle, events, mouse position, theme, dt

### 2. Box Tree Construction (application code)
- Application calls `ui_build_box_from_string()` / `ui_build_box_from_stringf()` / `ui_build_box_from_key()`
- Each call creates or reuses a `UI_Box` node, hooks it into the tree under the current parent
- Flags, sizes, colors, and all styling come from the implicit state stacks
- Higher-level widgets (`ui_button()`, `ui_label()`, `ui_line_edit()`, etc.) are thin wrappers
- `ui_signal_from_box(box)` processes queued events against the box and returns interaction info

### 3. `ui_end_build()`
- **Layout pass** runs per-axis (X then Y), consisting of 5 sub-passes:
  1. Standalone sizes (pixels, text content)
  2. Upwards-dependent sizes (parent percentage)
  3. Downwards-dependent sizes (children sum)
  4. Constraint enforcement (overflow redistribution via strictness weights)
  5. Positioning (sequential placement along layout axis, view-scroll offsets)
- Handles floating roots (tooltips, context menus) — clamps to window bounds
- Prunes untouched/transient boxes from the hash table

### 4. Draw Pass (in application code, after `ui_end_build()`)
- Creates a `DR_Bucket` (draw command list)
- Walks the box tree in depth-first **post-order** (`ui_box_rec_df_post`)
- For each box, interprets flags to emit draw calls:
  - `UI_BoxFlag_DrawBackground` → `dr_rect()` with background color
  - `UI_BoxFlag_DrawBorder` / `DrawSide*` → `dr_rect()` with border params
  - `UI_BoxFlag_DrawText` → `dr_truncated_fancy_run_list()` at computed text position
  - `UI_BoxFlag_DrawDropShadow` → shadow rectangle
  - `UI_BoxFlag_DrawBackgroundBlur` → `dr_blur()`
  - `UI_BoxFlag_DrawHotEffects` / `DrawActiveEffects` → visual feedback using `hot_t` / `active_t`
  - `UI_BoxFlag_Clip` → push/pop clip rectangles
  - `UI_BoxFlag_DrawBucket` → inline sub-bucket of custom draw commands
  - `custom_draw` callback → arbitrary draw logic
- Manages transform stack for squish animations

### 5. Render Submission
- `r_begin_frame()` / `r_window_begin_frame()`
- `dr_submit_bucket()` — flattens draw bucket into render pass list
- `r_window_submit()` — sends passes to GPU backend
- `r_window_end_frame()` / `r_end_frame()`

---

## Core Data Structures

### `UI_Box`
The fundamental node. Every widget, container, spacer, and layout element is a box.

```c
struct UI_Box {
    // --- persistent links (hash table chain) ---
    UI_Box *hash_next, *hash_prev;

    // --- per-build tree links ---
    UI_Box *first, *last, *next, *prev, *parent;
    U64 child_count;

    // --- per-build equipment (set during construction) ---
    UI_Key key;
    UI_BoxFlags flags;           // ~53 flag bits
    String8 string;
    UI_TextAlign text_align;
    Vec2F32 fixed_position, fixed_size, min_size;
    UI_Size pref_size[2];       // preferred size per axis
    Axis2 child_layout_axis;    // X or Y
    // ... colors, font, corner radii, blur, transparency, squish, custom draw, etc.

    // --- per-build artifacts (computed by layout) ---
    Rng2F32 rect;               // final screen rectangle
    Vec2F32 position_delta;     // frame-over-frame movement

    // --- persistent state (survives across frames) ---
    U64 first_touched_build_index, last_touched_build_index;
    F32 hot_t, active_t, disabled_t;
    F32 focus_hot_t, focus_active_t;
    Vec2F32 view_off, view_off_target, view_bounds;
    // ... default nav focus keys
};
```

### `UI_Key`
A 64-bit hash identifying a box across frames. Computed from a string with parent-chain seeding.

Supports ImGui-style `##` / `###` separators:
- `"Display Text##unique_id"` — display and hash portions separated
- `"###stable_key"` — hash portion replaces everything

### `UI_Size`
```c
struct UI_Size {
    UI_SizeKind kind;   // Null, Pixels, TextContent, ParentPct, ChildrenSum
    F32 value;          // meaning depends on kind
    F32 strictness;     // 0.0 = fully flexible, 1.0 = rigid (won't shrink under overflow)
};
```

### `UI_Signal`
Returned by `ui_signal_from_box()`. Contains ~28 signal flag bits:
- Press, release, click (per mouse button: left/middle/right)
- Double-click, triple-click
- Dragging, double-dragging, triple-dragging
- Keyboard press
- Hovering, mouse-over
- Commit
- Scroll delta (`Vec2S16`)

Convenience macros: `ui_pressed(sig)`, `ui_clicked(sig)`, `ui_hovering(sig)`, etc.

### `UI_State`
Thread-local singleton holding all per-build and persistent state:
- Build arenas (double-buffered)
- Box hash table + free list
- Animation cache (LRU)
- Active/hot/drop-hot key tracking
- Press history (for double/triple click detection)
- Drag state
- Tooltip / context menu state
- All implicit style stacks (~35 stacks)

---

## Implicit State Stacks

The system uses ~35 stacks to set styling contextually. Each stack has three operations:
- `ui_push_X(value)` — push onto stack, returns old top
- `ui_pop_X()` — pop from stack, returns popped value
- `ui_set_next_X(value)` — push, but auto-pop after next box construction

All stacks are **code-generated** from a table in `ui.mdesk`. The table defines:

| Stack Name         | Type              | Default               |
|--------------------|-------------------|-----------------------|
| Parent             | `UI_Box *`        | `&ui_nil_box`         |
| ChildLayoutAxis    | `Axis2`           | `Axis2_X`             |
| PrefWidth          | `UI_Size`         | `ui_px(250, 1.0)`     |
| PrefHeight         | `UI_Size`         | `ui_px(30, 1.0)`      |
| Flags              | `UI_BoxFlags`     | 0                     |
| FocusHot           | `UI_FocusKind`    | Null                  |
| FocusActive        | `UI_FocusKind`    | Null                  |
| BackgroundColor    | `Vec4F32`         | transparent           |
| TextColor          | `Vec4F32`         | transparent           |
| BorderColor        | `Vec4F32`         | transparent           |
| Font               | `FNT_Tag`         | zero                  |
| FontSize           | `F32`             | 24.0                  |
| CornerRadius00..11 | `F32`             | 0                     |
| BlurSize           | `F32`             | 0                     |
| TextPadding        | `F32`             | 0                     |
| TextAlignment      | `UI_TextAlign`    | Left                  |
| ... and more       |                   |                       |

Scoped wrappers use C's `DeferLoop` macro (a `for` loop that runs begin/end):
```c
#define UI_Row          DeferLoop(ui_row_begin(), ui_row_end())
#define UI_Column       DeferLoop(ui_column_begin(), ui_column_end())
#define UI_Parent(b)    DeferLoop(ui_push_parent(b), ui_pop_parent())
#define UI_Font(f)      DeferLoop(ui_push_font(f), ui_pop_font())
#define UI_PrefWidth(s) DeferLoop(ui_push_pref_width(s), ui_pop_pref_width())
// ... etc
```

---

## Layout Algorithm Detail

Layout runs independently per axis (X, then Y). For each axis:

### Pass 1: Standalone Sizes
Boxes with `Pixels` or `TextContent` size kind get their `fixed_size` computed directly.
- `Pixels`: `fixed_size = pref_size.value`
- `TextContent`: `fixed_size = padding + rendered_text_width + text_padding*2`

### Pass 2: Upwards-Dependent Sizes
Boxes with `ParentPct` walk up the tree to find the nearest ancestor with a determined size,
then multiply: `fixed_size = ancestor.fixed_size * pref_size.value`.

### Pass 3: Downwards-Dependent Sizes
Boxes with `ChildrenSum` size compute by summing children (along the layout axis) or taking
the max (perpendicular to layout axis). Floating children are excluded.

### Pass 4: Constraint Enforcement
When children overflow their parent (along the layout axis), the overflow is redistributed
proportionally based on `(1 - strictness)`. A child with `strictness=1.0` will not shrink.
On the non-layout axis, children are simply clamped to the parent's size.

### Pass 5: Positioning
Children are placed sequentially along the layout axis. Non-floating children accumulate
position. Floating children use their `fixed_position` directly. View scroll offsets are
applied. Final `rect` is computed as parent origin + position offset.

---

## Event System

Events are collected into a `UI_EventList` before the build phase. During the build,
`ui_signal_from_box()` iterates events and matches them against the box:

- Mouse press in bounds + `MouseClickable` → sets hot/active key, records press history
- Mouse release while active + in bounds → clicked
- Mouse release while active + out of bounds → released (not clicked)
- Keyboard accept while `FocusHot` + `KeyboardClickable` → keyboard pressed
- Scroll while `Scroll`/`ViewScroll` + in bounds → scroll delta accumulated
- Events are "eaten" (removed from the list) when consumed, so later boxes won't see them

The blacklist rectangle system prevents clicks through context menus.

---

## Widget Composition Pattern

Widgets are composed by combining box construction with stack manipulation:

```c
// A button is just a box with specific flags
internal UI_Signal ui_button(String8 string) {
    UI_Box *box = ui_build_box_from_string(
        UI_BoxFlag_Clickable |
        UI_BoxFlag_DrawBackground |
        UI_BoxFlag_DrawBorder |
        UI_BoxFlag_DrawText |
        UI_BoxFlag_DrawHotEffects |
        UI_BoxFlag_DrawActiveEffects,
        string);
    UI_Signal interact = ui_signal_from_box(box);
    return interact;
}

// A scroll list composes multiple boxes with layout stacks
internal void ui_scroll_list_begin(params, scroll_pt, cursor, ...) {
    // outer container
    ui_set_next_child_layout_axis(Axis2_Y);
    UI_Box *container = ui_build_box_from_key(...);
    // scroll bar alongside content
    // ... push parent, set sizes, etc.
}
```

Complex widgets like `ui_line_edit` use `custom_draw` callbacks to render cursors and
selections on top of the normal box rendering.

---

## TUI Adaptation Strategy

### What Stays the Same

The following concepts map directly to a TUI:

| Concept | GUI | TUI |
|---------|-----|-----|
| Box tree | Unchanged | Unchanged |
| Key system | Unchanged | Unchanged |
| Parent/child hierarchy | Unchanged | Unchanged |
| Layout algorithm | Unchanged | Unchanged (but integer cells) |
| Signal/interaction | Unchanged | Unchanged |
| Implicit stacks | Unchanged | Reduced set |
| Focus system | Unchanged | More important (keyboard-driven) |
| Scroll management | Unchanged | Unchanged |
| Context menus | Unchanged | Unchanged |

### What Changes

#### Sizing: Pixels → Character Cells

Replace the unit system. Everything is measured in integer character cell coordinates.

| `UI_SizeKind` | GUI meaning | TUI meaning |
|---------------|-------------|-------------|
| `Pixels` | Exact pixel count | Exact column/row count |
| `TextContent` | Rendered text pixel width + padding | `string.len + padding` (integer) |
| `ParentPct` | Fraction of parent pixel size | Fraction of parent cell count (round) |
| `ChildrenSum` | Sum of child pixel sizes | Sum of child cell counts |

All `fixed_size`, `fixed_position`, and `rect` values become integers. The layout
algorithm works identically — it's just math on sizes — but results are snapped to
integer cell boundaries. The `strictness` and overflow redistribution logic works as-is.

A Zig equivalent might look like:
```zig
const Size = struct {
    kind: SizeKind,
    value: f32,      // can remain float for fractional ParentPct
    strictness: f32,
};

// After layout, all rects are integer:
const Rect = struct {
    col: u16, row: u16,
    w: u16, h: u16,
};
```

#### Drawing: GPU Commands → Terminal Output

The draw pass becomes a terminal cell buffer write pass. Instead of emitting `dr_rect()`
and `dr_text()` calls, we write into a 2D cell grid:

```
struct Cell {
    codepoint: u21,
    fg: Color,
    bg: Color,
    attrs: Attrs, // bold, underline, etc.
};

grid: [rows][cols]Cell
```

Flag interpretation becomes:

| Box Flag | GUI Draw | TUI Draw |
|----------|----------|----------|
| `DrawBackground` | Filled rectangle | Fill cells with `bg` color |
| `DrawBorder` | Rectangle with border thickness | Box-drawing characters (│─┌┐└┘├┤┬┴┼) |
| `DrawSideTop/Bottom/Left/Right` | Single edge line | Single box-drawing line |
| `DrawText` | GPU text rendering | Write string bytes into cell grid |
| `DrawHotEffects` | Glow / soft circle | Reverse video, bold, or highlight color |
| `DrawActiveEffects` | Inset shadow | Reverse video or different bg color |
| `DrawDropShadow` | Offset blurred shadow | Not applicable (skip) |
| `DrawBackgroundBlur` | Gaussian blur | Not applicable (skip) |
| `Clip` | GPU scissor rect | Clamp writes to rect during grid fill |

The traversal is the same depth-first walk. For each box, we fill its `rect` region in
the cell grid based on its flags.

#### Input: OS Events → Terminal Input

Terminal input (from raw mode / termios) maps to `UI_Event`:

| Terminal Input | UI_Event |
|----------------|----------|
| Key press | `kind=Press, key=mapped_key` |
| Key release | Not available in most terminals (skip) |
| Mouse click (if enabled) | `kind=Press, key=LeftMouseButton, pos=cell_coords` |
| Mouse release | `kind=Release` |
| Mouse move | `kind=MouseMove, pos=cell_coords` |
| Scroll (mouse wheel) | `kind=Scroll, delta=...` |
| Text input | `kind=Text, string=utf8_bytes` |
| Paste | `kind=Text` with bracketed paste content |
| Resize | Re-query terminal size, rebuild |

Since terminals are primarily keyboard-driven, the **focus navigation system** becomes
the primary interaction mode. The `DefaultFocusNav` box flags and the automatic focus
traversal in `ui_begin_build()` handle arrow-key navigation between focusable boxes.

#### Stacks That Don't Apply

Many stacks can be dropped or simplified for TUI:

| Stack | TUI Status |
|-------|------------|
| Font, FontSize, TextRasterFlags | Drop (terminal has one font) |
| CornerRadius00..11 | Drop (use box-drawing characters instead) |
| BlurSize | Drop |
| Transparency | Drop or approximate with color blending |
| Squish | Drop |
| HoverCursor | Drop (terminal cursor is fixed) |
| TabSize | Keep (tab stops in cells) |
| TextPadding | Keep (padding in cells) |
| TextAlignment | Keep |
| BackgroundColor, TextColor, BorderColor | Keep (map to terminal colors) |
| ChildLayoutAxis, PrefWidth, PrefHeight | Keep |
| Flags, OmitFlags, PermissionFlags | Keep |
| FocusHot, FocusActive | Keep (essential for keyboard nav) |
| Parent | Keep |
| FixedX/Y/Width/Height, MinWidth/Height | Keep |

#### Animation

Most animation is irrelevant in a terminal. However, a few are still useful:

- **`hot_t` / `active_t`**: Can drive highlight/reverse-video intensity
- **`view_off` scrolling**: Smooth scrolling can be kept as instant-snap
- **Cursor blink**: Can be done via terminal escape codes
- **`focus_hot_t` / `focus_active_t`**: Drive focus indicator visibility

The `UI_AnimationInfo` rates can all be set to `1.0` (instant) for TUI.

---

## Proposed TUI Architecture

```
┌────────────────────────────────────────────────────┐
│  Application                                        │
│  Uses the same ui_build_box / ui_signal_from_box    │
│  API to declare widgets each frame                  │
├────────────────────────────────────────────────────┤
│  UI Core (ported to Zig)                            │
│  Box tree, layout, key hashing, signals, stacks     │
│  Sizes in character cells instead of pixels          │
├────────────────────────────────────────────────────┤
│  TUI Draw Layer                                      │
│  Walks box tree → fills Cell grid                    │
│  Box-drawing characters for borders                  │
│  ANSI color codes for styling                        │
├────────────────────────────────────────────────────┤
│  Terminal Backend                                    │
│  Raw mode I/O, input parsing, cell grid diff+flush   │
│  (e.g. using Zig's std.posix or a thin termios lib) │
└────────────────────────────────────────────────────┘
```

### Frame Loop (TUI)

```
loop {
    // 1. Collect terminal input, convert to UI events
    poll_terminal_input(&event_list);

    // 2. Begin build
    ui_begin_build(terminal_size, &event_list, dt);

    // 3. Application builds box tree
    app_build_ui();

    // 4. End build (layout)
    ui_end_build();

    // 5. Walk tree, fill cell grid
    tui_draw_box_tree(ui_root(), &cell_grid);

    // 6. Diff against previous frame, emit minimal ANSI escape sequences
    tui_flush_grid(&cell_grid, &prev_grid, writer);

    // 7. Swap grids
    swap(&cell_grid, &prev_grid);

    // 8. Sleep or wait for next input
    if (!ui_animating()) wait_for_input();
}
```

### Key Implementation Notes

**Cell Grid Diffing**: Only write cells that changed since last frame. This minimizes
terminal I/O and prevents flicker. Compare `(codepoint, fg, bg, attrs)` per cell.

**Box-Drawing Border Rendering**: When a box has border flags, write box-drawing
characters along its edges. Corner characters should be resolved by checking adjacency
(e.g., a T-junction where two borders meet).

**Text Truncation**: The GUI system truncates text with `"..."`. In TUI, truncate to
the box width minus 1, append `…` (single Unicode ellipsis) if truncated.

**Wide Characters**: CJK and emoji take 2 cells. The cell grid needs to handle this
(mark the second cell as a "continuation" cell that doesn't get independently written).

**Color Mapping**: The theme system (`ui_color_from_name()`) returns `Vec4F32` RGBA.
For TUI, map these to the closest terminal color:
- 16 colors (basic ANSI)
- 256 colors (extended)
- 24-bit truecolor (most modern terminals)

---

## Summary of What to Port vs Replace

| Component | Action |
|-----------|--------|
| `UI_Box` struct | Port to Zig, remove GPU-specific fields (blur, corner_radii, font_tag, draw_bucket) |
| `UI_Key` + hashing | Port directly |
| `UI_Size` + size kinds | Port directly, interpret Pixels as cells |
| `UI_Signal` + event processing | Port directly |
| `UI_State` + stacks | Port, remove irrelevant stacks |
| Layout algorithm (5 passes) | Port directly, snap to integers |
| `ui_build_box_from_*` | Port directly |
| `ui_signal_from_box` | Port directly |
| Basic widgets (button, label, line_edit, scroll_list, table) | Port directly |
| Tooltip / context menu | Port (render as floating boxes in cell grid) |
| `draw/` layer | **Replace** with cell grid writer |
| `render/` layer | **Replace** with terminal I/O backend |
| Animation system | Simplify (instant transitions, optional smooth scroll) |
| Font system | **Remove** entirely |
| mdesk code generation | **Replace** with Zig comptime |

The raddebugger UI is remarkably well-suited for TUI adaptation because the box-tree
+ layout-engine core is rendering-agnostic. The main engineering effort is:
1. Porting the core data structures and layout algorithm to Zig
2. Writing the cell grid draw pass (~200-400 lines, replacing the ~400-line GPU draw loop)
3. Writing the terminal I/O backend (raw mode, input parsing, grid flush)

The application-facing API (`ui_button`, `ui_label`, `UI_Row`, `UI_Column`, etc.) can
remain nearly identical in shape, giving us a familiar immediate-mode API for building
terminal interfaces.
