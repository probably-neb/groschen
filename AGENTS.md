# AGENTS.md

## Naming Conventions

- **Functions and variables**: `snake_case`
- **Structs, types, and functions that return types**: `Title_Camel_Case` (e.g. `ArenaList`, `InitOptions`, `AllocError`)

## Code Style

- **Use descriptive variable names.** Prefer full, readable names like `index`, `codepoint`, `count` instead of abbreviations like `i`, `cp`, `n`. Well-established short forms are fine: `col`/`row`, `w`/`h`, `fg`/`bg`, `buf`, `ptr`, `pos`. Avoid ad-hoc abbreviations like `r` for rect or `cb` for callback — if the short form isn't immediately obvious, spell it out.
- **Prefer free functions over methods.** Especially prefer free functions that take plain old data (slices, integers, structs) as arguments rather than attaching behavior to types via methods. This keeps data structures simple and logic easy to test, compose, and reuse. Methods are acceptable for core type operations (e.g. `arena.alloc()`, `list.append()`), but default to free functions for everything else.
- **Never name the self parameter `self`.** Use a common abbreviation of the struct name instead — e.g. `term` for `Term`, `signal` for `Signal`, `arena` for `Arena`. This applies to both methods and free functions that take a struct pointer as their first argument.

## Throwaway Test Binaries

When writing quick one-off `.zig` files to test zig functionality, place them in `.zig-cache/` -- never in the project root or `/tmp`. This keeps the working tree clean and avoids committing scratch files.

```sh
cat > .zig-cache/writer_check.zig << 'EOF'
const std = @import("std");
pub fn main() !void {
    const info = @typeInfo(std.fs.File.Writer).@"struct";
    inline for (info.decls) |d| {
        @compileLog(d.name);
    }
}
EOF
cd .zig-cache && zig build-exe writer_check.zig 2>&1 | grep "Compile Log" -A30
```

## Base Layer (`src/base/`)

Prefer these types over zig std lib equivalents. They are designed around arena allocation, avoid hidden realloc+memcpy, and provide pointer stability where needed.

### Arena (`base.Arena`)

Virtual-memory-backed bump allocator. Reserves a large virtual address space (default 64 GB) upfront and commits pages on demand (64 KB granularity). This is the primary allocator for the project.

```zig
var arena = try Arena.init(.{});
defer arena.deinit();

// Typed allocation
const point = try arena.create(Point);
const items = try arena.alloc(u32, 100);

// Raw bytes
const buf = try arena.push(256);
const zeroed = try arena.push_zero(256);

// Expand the most recent allocation in-place
const expanded = try arena.expand(u32, items, 200);
```

Always prefer calling `arena.create()`, `arena.alloc()`, `arena.push()`, etc. directly. **`arena.allocator()` is discouraged** -- only use it as a short-lived bridge when you must pass a `std.mem.Allocator` to zig std lib functions (e.g. `std.fmt.allocPrint`). Never store or pass around the `std.mem.Allocator` wrapper when you can pass the `*Arena` instead. Note: `free()` is a no-op, `resize()` always fails.

**Scoped temporaries** -- save/restore the arena position for LIFO cleanup:

```zig
const scope = arena.scoped();
defer scope.release();
// allocations here are freed when scope.release() runs
```

### Scratch Arenas

Use `get_scratch` for **all temporary allocations** that would otherwise waste space or leak in a parent/persistent arena. Any intermediate buffers, sorting indices, temporary string builds, or working memory that is only needed within a function should go on a scratch arena rather than polluting a long-lived arena that won't be reset. There are exactly 2 scratch arenas per thread, lazily initialized. Always release with `defer`.

```zig
const scratch = Arena.get_scratch(&.{});
defer scratch.release();
const tmp = try scratch.arena.alloc(u32, n);
```

**You must pass conflicting arenas to `get_scratch`** when the caller already owns or writes into an arena. This prevents getting back the same underlying arena as a "scratch", which would corrupt data when the scratch is released (it resets position). If your function receives an `*Arena` parameter, always pass it as a conflict:

```zig
fn process(arena: *Arena, items: []const Item) !void {
    // CORRECT: pass `arena` as conflict so scratch is a *different* arena
    const scratch = Arena.get_scratch(&.{arena});
    defer scratch.release();

    const tmp = try scratch.arena.alloc(u32, items.len);
    // ... use tmp for intermediate work, result goes into `arena` ...
}
```

If you don't pass conflicts, `get_scratch` may return the same arena you're already using. When `scratch.release()` runs, it resets the position and silently frees your real data.

**FreeList** -- wraps an Arena with a free list for code that needs repeated alloc/free cycles. Returns a `std.mem.Allocator`:

```zig
var free_list = Arena.FreeList.init(&arena);
const ally = free_list.allocator();
const buf = try ally.alloc(u8, 100);
ally.free(buf); // actually reclaims for reuse
```

### ArenaList (`base.ArenaList`)

Use instead of `std.ArrayList`. Backed by an Arena, so growth never copies -- it asserts the arena hasn't been used elsewhere since the last growth (contiguity check).

```zig
var list: base.ArenaList(i32) = .empty;

try list.append(&arena, 42);
try list.append_slice(&arena, &.{ 1, 2, 3 });

// Pre-reserve capacity, then use assume_capacity variants
var list2 = try base.ArenaList(u8).init_capacity(&arena, 1024);
list2.append_assume_capacity('x');

// Access
const last = list.get_last();
const item = list.pop();
list.clear_retaining_capacity();
```

Key operations: `append`, `insert`, `ordered_remove`, `swap_remove`, `replace_range`, `add_one`, `add_many_as_slice`, `shrink_retaining_capacity`. Each has an `_assume_capacity` variant that skips the growth check.

### Xar (`base.Xar`)

Segmented list with **pointer stability** -- pointers to elements remain valid after append, unlike ArrayList. Elements are stored in power-of-2 shelves. O(1) append, O(1) indexed access.

Use when you need to hold pointers into the collection while it grows.

```zig
var xar = Xar(MyNode, 8){}; // 8 = prealloc count (must be 0 or power of 2)
defer xar.deinit(&arena);

try xar.append(&arena, node);
const ptr = xar.at(0);       // *MyNode, stable across future appends
_ = xar.pop();

var it = xar.iterator(0);
while (it.next()) |item| { ... }
```

### XarMap (`base.XarMap`)

Hash map built on Xar. **Pointers to values remain valid across rehashing.** Linear probing with tombstones.

Use instead of `std.HashMap` / `std.AutoHashMap`.

```zig
var map: base.XarMap(u32, []const u8, 4) = .{};
defer map.deinit(&arena);

try map.put(&arena, 1, "one");

if (map.get(key)) |val_ptr| { ... }       // ?*V
if (map.get_const(key)) |val_ptr| { ... } // ?*const V

const result = try map.get_or_put(&arena, key);
if (!result.found_existing) {
    result.key_ptr.* = key;
    result.value_ptr.* = value;
}

_ = map.remove(key);                      // bool
const old = map.fetch_remove(key);         // ?V

// Iteration
var it = map.const_iterator();
while (it.next()) |entry| { use(entry.key_ptr.*, entry.value_ptr.*); }
```

Custom key types can implement `fn hash(self) usize` and `fn eql(self, other) bool`. Slice keys (`[]const u8`) are handled automatically.

### IntrusiveLinkedList (`base.IntrusiveLinkedList`)

Singly-linked list. The element type must have a `next: ?*T` field. No allocations -- nodes are allocated in the arena and linked manually.

```zig
const Node = struct {
    data: u32,
    next: ?*Node = null,
};

var list: base.IntrusiveLinkedList(Node) = .{};
const n = try arena.create(Node);
n.* = .{ .data = 42 };
list.prepend(n);
```

Operations: `prepend`, `pop_first`, `insert_after`, `remove`, `remove_next`, `concat`, `reverse`, `count`.

### IntrusiveDoublyLinkedList (`base.IntrusiveDoublyLinkedList`)

Circular doubly-linked list. Element type must have `next: *T` and `prev: *T` fields. A single element points to itself.

```zig
const Node = struct {
    data: u32,
    next: *Node,
    prev: *Node,

    fn init(self: *Node, data: u32) void {
        self.* = .{ .data = data, .next = self, .prev = self };
    }
};

var list: base.IntrusiveDoublyLinkedList(Node) = .zero;
const n = try arena.create(Node);
n.init(42);
list.append(n);

var it = list.iter();
while (it.next()) |node| { ... }
```

Operations: `prepend`, `append`, `insert_after`, `insert_before`, `remove`, `pop_first`, `pop_last`, `last`, `concat`, `count`, `iter`.

### When to Use What

| Need | Type |
|---|---|
| General allocation | `Arena` |
| Growable array | `ArenaList` |
| Growable array with stable pointers | `Xar` |
| Key-value map with stable pointers | `XarMap` |
| Singly-linked node chain | `IntrusiveLinkedList` |
| Doubly-linked node chain with iteration | `IntrusiveDoublyLinkedList` |
| Short-lived temporary memory | `Arena.get_scratch` / `arena.scoped()` |
| Repeated alloc/free on an arena | `Arena.FreeList` |
| Passing arena to std lib APIs | `arena.allocator()` |

## Arena Usage (Frame vs Persistent)

- **Frame/UI arena** (`ui.get_build_arena()`, `ui.arena_print`, `ui.arena_dupe`) is **only valid for the current frame**. Pointers from these allocations must never be stored in `App` or any persistent state.
- **Persistent state** must live in app-owned buffers or the long-lived arena (`perm_arena` or a dedicated arena). Use `std.fmt.bufPrint` into a fixed buffer on the state struct for labels/messages that persist across frames.
- **Rules of thumb**
  - ✅ Use `ui.arena_print` for one-off labels that are built and consumed in the same frame.
  - ❌ Do not stash `ui.arena_print` results into `App` fields.
  - ✅ For persistent text, store a `[]u8` buffer on the state and format into it.

## Box as State Container

Following the raddebugger UI model, **persistent per-widget state lives directly on the `Box` struct** rather than in separate state objects. Every `Box` carries fields like `hot_t`, `active_t`, `view_off`, `view_off_target`, `view_bounds`, etc. that survive across frames (copied from the previous frame's box with the same key in `build_box`).

**Why this design:**
- **Minimal overhead.** A few extra floats per box cost almost nothing — boxes are arena-allocated and transient. Unused fields sit at zero.
- **Flexible composition.** Any box can become scrollable, animatable, or interactive just by setting flags. No need to pair it with a separate state struct or look up state in a side table.
- **No state lifetime management.** The box tree owns the state. When a box stops being built, its state is naturally pruned. No manual cleanup, no dangling references to freed state objects.
- **One-frame-behind pattern.** `build_box` copies persistent fields from the previous frame's box. Widget code reads last frame's state (e.g. `view_off_target`) to decide what to build, then `signal_from_box` updates state for the next frame. This is standard for immediate-mode UI.

**Scrolling example:** A box with `view_scroll` flag automatically gets scroll input handling in `signal_from_box`. Mouse wheel events update `view_off_target`; keyboard arrows/page keys do the same when the box has focus. The caller sets `view_bounds` to declare total content size, and the framework clamps `view_off_target` to the valid range. The `scroll_list_begin`/`scroll_list_end` widget is a convenience that reads `view_off_target` to compute visible row ranges — no external `Scroll_State` needed.

**Rules of thumb:**
- ✅ Add new persistent per-widget state as fields on `Box` when the overhead is trivial (a few scalars).
- ✅ Use `view_off_target` / `view_bounds` for scroll state — don't create separate scroll state structs.
- ❌ Don't store large or variable-size data on `Box` (buffers, lists). Use a keyed side table or app state for those.
- ❌ Don't read `view_off` to determine scroll position in widget code — read `view_off_target`. `view_off` is the visual/layout offset (used by the layout pass to shift children) and may lag behind the target during animation.

## Defer + Scoped Styles

- Prefer `push_*` + `defer pop_*` for repeated styles.
- **Always scope** a `push_*` with a block when it should not affect subsequent widgets.
- Avoid leaked styles by keeping the `defer` as close as possible to the `push_*`.

Example:

```zig
{
    _ = ui.push_text_padding(1);
    defer _ = ui.pop_text_padding();
    _ = widgets.label("Name:");
}
```

## UI Component Organization

- Break large UI builders into **small named functions** (e.g. `build_title_bar`, `build_button_row`, `build_status_bar`).
- Each function should:
  - Configure only the styles it owns.
  - Use `push_*`/`pop_*` with `defer` (no `next_*` for repeated styles).
  - Return early rather than deeply nesting when possible.

## Common Failure Modes

- **Flickering text / garbled labels**: storing a `ui.arena_print` result in persistent state.
- **Unexpected styling changes**: missing `pop_*` or a `push_*` not scoped with a block.
- **Cross-component bleed**: using `next_*` for styles intended to persist across multiple widgets.

When in doubt, assume UI allocations are frame-local and scope styles tightly.

## Terminal Rendering

Always use `tuimg` to render `.ansi` files to PNG. Do **not** use VHS, aha, ansilove, or other tools.

```sh
tuimg -o designs/output.png --cols 80 --rows 40 designs/input.ansi
```

Key flags: `--cols` / `--rows` set terminal dimensions (default 80×24), `--fg` / `--bg` override default colors, `--font-size` sets point size (default 14).
