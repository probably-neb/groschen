const std = @import("std");
const ui = @import("ui.zig");
const term = @import("term");
const base = @import("base");
const Arena = base.Arena;

const assert = std.debug.assert;

// ---------------------------------------------------------------------------
// Event Types
// ---------------------------------------------------------------------------

pub const UiEventKind = enum {
    mouse_press,
    mouse_release,
    key_press,
    text,
    scroll,
    mouse_move,
};

pub const UiEvent = struct {
    kind: UiEventKind = .key_press,
    key: term.Key = .none,
    codepoint: u21 = 0,
    mods: term.Modifiers = .{},
    mouse_button: term.MouseButton = .none,
    pos: [2]u16 = .{ 0, 0 },
    scroll: [2]i16 = .{ 0, 0 },
    consumed: bool = false,
    next: ?*UiEvent = null,
};

pub const UiEventList = struct {
    first: ?*UiEvent = null,
    last: ?*UiEvent = null,
    count: u32 = 0,

    fn append(self: *UiEventList, ev: *UiEvent) void {
        ev.next = null;
        if (self.last) |last| {
            last.next = ev;
        } else {
            self.first = ev;
        }
        self.last = ev;
        self.count += 1;
    }

    fn clear(self: *UiEventList) void {
        self.* = .{};
    }
};

// ---------------------------------------------------------------------------
// Interaction State
// ---------------------------------------------------------------------------

const InteractionState = struct {
    events: UiEventList = .{},
    mouse_pos: [2]u16 = .{ 0, 0 },
    hot_box_key: ui.Key = ui.Key.zero,
    active_box_key: [2]ui.Key = .{ ui.Key.zero, ui.Key.zero },
    focus_hot_key: ui.Key = ui.Key.zero,
    focus_active_key: ui.Key = ui.Key.zero,
};

var state: InteractionState = .{};

// ---------------------------------------------------------------------------
// Public Getters
// ---------------------------------------------------------------------------

pub fn get_hot_box_key() ui.Key {
    return state.hot_box_key;
}

pub fn get_focus_hot_key() ui.Key {
    return state.focus_hot_key;
}

pub fn set_focus_hot_key(key: ui.Key) void {
    state.focus_hot_key = key;
}

pub fn get_focus_active_key() ui.Key {
    return state.focus_active_key;
}

pub fn get_mouse_pos() [2]u16 {
    return state.mouse_pos;
}

pub fn get_events() *UiEventList {
    return &state.events;
}

pub fn get_active_box_key(comptime button: enum { left, right }) ui.Key {
    return state.active_box_key[
        switch (button) {
            .left => 0,
            .right => 1,
        }
    ];
}

// ---------------------------------------------------------------------------
// Frame Lifecycle
// ---------------------------------------------------------------------------

pub fn begin_frame() void {
    state.events.clear();
}

pub fn reset() void {
    state = .{};
}

// ---------------------------------------------------------------------------
// Event Conversion & Pushing
// ---------------------------------------------------------------------------

pub fn push_event(arena: *Arena, input: term.InputEvent) void {
    const ev = arena.create(UiEvent) catch return;
    ev.* = .{};

    switch (input) {
        .key => |k| {
            if (k.key == .codepoint and k.mods.eql(term.Modifiers.none)) {
                ev.kind = .text;
            } else {
                ev.kind = .key_press;
            }
            ev.key = k.key;
            ev.codepoint = k.codepoint;
            ev.mods = k.mods;
        },
        .mouse => |m| {
            ev.pos = .{ m.col, m.row };
            ev.mods = m.mods;
            ev.mouse_button = m.button;
            state.mouse_pos = .{ m.col, m.row };

            switch (m.kind) {
                .press => ev.kind = .mouse_press,
                .release => ev.kind = .mouse_release,
                .move => ev.kind = .mouse_move,
                .scroll_up => {
                    ev.kind = .scroll;
                    ev.scroll = .{ 0, -1 };
                },
                .scroll_down => {
                    ev.kind = .scroll;
                    ev.scroll = .{ 0, 1 };
                },
            }
        },
        .resize => return,
    }

    state.events.append(ev);
}

// ---------------------------------------------------------------------------
// Event Processing (call after layout)
// ---------------------------------------------------------------------------

pub fn process_events(root: *ui.Box) void {
    update_hot_box(root);
    process_mouse_focus(root);
    process_focus_navigation(root);
}

fn update_hot_box(root: *ui.Box) void {
    var hot_pos = state.mouse_pos;
    var ev = state.events.first;
    while (ev) |e| : (ev = e.next) {
        if (e.kind == .mouse_press) {
            hot_pos = e.pos;
            break;
        }
    }

    var result: ui.Key = ui.Key.zero;
    var node: ?*ui.Box = root;
    while (node) |n| {
        if (n.flags.clickable and !n.flags.disabled and
            n.rect.contains(hot_pos[0], hot_pos[1]))
        {
            result = n.key;
        }
        node = ui.tree_next(n);
    }
    state.hot_box_key = result;
}

fn process_mouse_focus(root: *ui.Box) void {
    var ev = state.events.first;
    while (ev) |e| : (ev = e.next) {
        if (e.consumed) continue;
        if (e.kind != .mouse_press) continue;

        const clicked_key = find_topmost_focusable_at(root, e.pos[0], e.pos[1]);
        if (!clicked_key.is_zero()) {
            state.focus_hot_key = clicked_key;
        }
    }
}

fn find_topmost_focusable_at(root: *ui.Box, col: u16, row: u16) ui.Key {
    var result: ui.Key = ui.Key.zero;
    var node: ?*ui.Box = root;
    while (node) |n| {
        if ((n.flags.focus_hot or n.flags.focus_active) and
            !n.flags.focus_nav_skip and !n.flags.disabled and
            !n.key.is_zero() and n.rect.contains(col, row))
        {
            result = n.key;
        }
        node = ui.tree_next(n);
    }
    return result;
}

// ---------------------------------------------------------------------------
// Focus Navigation
// ---------------------------------------------------------------------------

const max_focusable = 256;

fn process_focus_navigation(root: *ui.Box) void {
    var focusable_keys: [max_focusable]ui.Key = undefined;
    var focusable_count: u32 = 0;

    var node: ?*ui.Box = root;
    while (node) |n| {
        if ((n.flags.focus_hot or n.flags.focus_active) and
            !n.flags.focus_nav_skip and !n.flags.disabled and
            !n.key.is_zero())
        {
            if (focusable_count < max_focusable) {
                focusable_keys[focusable_count] = n.key;
                focusable_count += 1;
            }
        }
        node = ui.tree_next(n);
    }

    if (focusable_count == 0) {
        state.focus_hot_key = ui.Key.zero;
        state.focus_active_key = ui.Key.zero;
        return;
    }

    var current_idx: ?u32 = null;
    for (focusable_keys[0..focusable_count], 0..) |k, i| {
        if (k.eql(state.focus_hot_key)) {
            current_idx = @intCast(i);
            break;
        }
    }

    var ev = state.events.first;
    while (ev) |e| : (ev = e.next) {
        if (e.consumed) continue;
        if (e.kind != .key_press or e.key != .tab) continue;

        if (e.mods.shift) {
            current_idx = if (current_idx) |idx|
                if (idx == 0) focusable_count - 1 else idx - 1
            else
                focusable_count - 1;
        } else {
            current_idx = if (current_idx) |idx|
                (idx + 1) % focusable_count
            else
                0;
        }
        e.consumed = true;
    }

    if (current_idx) |idx| {
        state.focus_hot_key = focusable_keys[idx];
    } else if (!state.focus_hot_key.is_zero()) {
        state.focus_hot_key = focusable_keys[0];
    }

    // focus_active follows focus_hot if the focused box has the focus_active flag
    state.focus_active_key = ui.Key.zero;
    node = root;
    while (node) |n| {
        if (!n.key.is_zero() and n.key.eql(state.focus_hot_key) and n.flags.focus_active) {
            state.focus_active_key = n.key;
            break;
        }
        node = ui.tree_next(n);
    }
}

// ---------------------------------------------------------------------------
// Signal Computation
// ---------------------------------------------------------------------------

pub fn signal_from_box(box: *ui.Box) ui.Signal {
    var sig: ui.Signal = .{};

    if (box.flags.disabled or box.key.is_zero()) return sig;

    sig.mouse_pos = state.mouse_pos;

    const mouse_in_bounds = box.rect.contains(state.mouse_pos[0], state.mouse_pos[1]);

    if (mouse_in_bounds) sig.flags.mouse_over = true;
    if (mouse_in_bounds and box.flags.clickable and box.key.eql(state.hot_box_key))
        sig.flags.hovering = true;

    // -- Mouse events -------------------------------------------------------
    var ev = state.events.first;
    while (ev) |e| : (ev = e.next) {
        if (e.consumed) continue;

        switch (e.kind) {
            .mouse_press => {
                if (!box.flags.clickable) continue;
                const ev_in_bounds = box.rect.contains(e.pos[0], e.pos[1]);
                if (!ev_in_bounds) continue;
                if (!box.key.eql(state.hot_box_key)) continue;

                if (e.mouse_button == .left) {
                    sig.flags.left_pressed = true;
                    state.active_box_key[0] = box.key;
                } else if (e.mouse_button == .right) {
                    sig.flags.right_pressed = true;
                    state.active_box_key[1] = box.key;
                }
                e.consumed = true;
            },
            .mouse_release => {
                const is_left = e.mouse_button == .left and
                    !state.active_box_key[0].is_zero() and
                    state.active_box_key[0].eql(box.key);
                const is_right = e.mouse_button == .right and
                    !state.active_box_key[1].is_zero() and
                    state.active_box_key[1].eql(box.key);

                if (is_left) {
                    sig.flags.left_released = true;
                    if (box.rect.contains(e.pos[0], e.pos[1]))
                        sig.flags.left_clicked = true;
                    state.active_box_key[0] = ui.Key.zero;
                    e.consumed = true;
                }
                if (is_right) {
                    sig.flags.right_released = true;
                    if (box.rect.contains(e.pos[0], e.pos[1]))
                        sig.flags.right_clicked = true;
                    state.active_box_key[1] = ui.Key.zero;
                    e.consumed = true;
                }
            },
            .scroll => {
                if (!box.flags.view_scroll) continue;
                if (!box.rect.contains(e.pos[0], e.pos[1])) continue;

                sig.scroll[0] +|= e.scroll[0];
                sig.scroll[1] +|= e.scroll[1];
                e.consumed = true;
            },
            .key_press, .text, .mouse_move => {},
        }
    }

    // -- Keyboard interaction via focus -------------------------------------
    if (box.flags.keyboard_clickable and state.focus_hot_key.eql(box.key)) {
        ev = state.events.first;
        while (ev) |e| : (ev = e.next) {
            if (e.consumed) continue;
            if (e.kind != .key_press) continue;

            if (e.key == .enter or (e.key == .codepoint and e.codepoint == ' ')) {
                sig.flags.keyboard_pressed = true;
                sig.flags.commit = true;
                e.consumed = true;
            }
        }
    }

    // -- Dragging -----------------------------------------------------------
    const is_active_left = !state.active_box_key[0].is_zero() and state.active_box_key[0].eql(box.key);
    const is_active_right = !state.active_box_key[1].is_zero() and state.active_box_key[1].eql(box.key);
    if (is_active_left or is_active_right) sig.flags.dragging = true;

    // -- Animate hot_t / active_t / focus_*_t -------------------------------
    const anim_rate: f32 = 15.0;
    const dt: f32 = 1.0 / 60.0;
    const step = anim_rate * dt;

    box.hot_t = animate(box.hot_t, sig.flags.hovering, step);
    box.active_t = animate(box.active_t, is_active_left or is_active_right, step);
    box.focus_hot_t = animate(box.focus_hot_t, state.focus_hot_key.eql(box.key), step);
    box.focus_active_t = animate(box.focus_active_t, state.focus_active_key.eql(box.key), step);
    box.disabled_t = animate(box.disabled_t, box.flags.disabled, step);

    return sig;
}

fn animate(current: f32, target_on: bool, step: f32) f32 {
    return if (target_on)
        @min(1.0, current + step)
    else
        @max(0.0, current - step);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

fn make_test_box(arena: *Arena, name: []const u8, flags: ui.BoxFlags, rect: ui.Rect) *ui.Box {
    const b = arena.create(ui.Box) catch @panic("OOM");
    b.* = .{};
    const tag = ui.parse_tag(name);
    b.key = ui.Key.from_string(0, tag.hash_string);
    b.string = name;
    b.display_string = tag.display;
    b.flags = flags;
    b.rect = rect;
    return b;
}

fn link_children(parent: *ui.Box, children: []const *ui.Box) void {
    for (children) |child| {
        ui.push_child(parent, child);
    }
}

test "mouse click inside a button box produces left_clicked signal" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    reset();
    begin_frame();

    const root = make_test_box(&arena, "root###r", .{}, .{ .col = 0, .row = 0, .w = 80, .h = 24 });
    const button = make_test_box(&arena, "btn###b", .{
        .clickable = true,
        .focus_hot = true,
        .keyboard_clickable = true,
    }, .{ .col = 5, .row = 5, .w = 10, .h = 3 });
    link_children(root, &.{button});

    push_event(&arena, .{ .mouse = .{ .kind = .press, .button = .left, .col = 7, .row = 6, .mods = .{} } });
    push_event(&arena, .{ .mouse = .{ .kind = .release, .button = .left, .col = 7, .row = 6, .mods = .{} } });

    process_events(root);
    const sig = signal_from_box(button);

    try testing.expect(sig.flags.left_pressed);
    try testing.expect(sig.flags.left_released);
    try testing.expect(sig.flags.left_clicked);
    try testing.expect(sig.flags.hovering);
    try testing.expect(sig.flags.mouse_over);
}

test "mouse click outside a button box produces no signal" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    reset();
    begin_frame();

    const root = make_test_box(&arena, "root###r", .{}, .{ .col = 0, .row = 0, .w = 80, .h = 24 });
    const button = make_test_box(&arena, "btn###b", .{
        .clickable = true,
    }, .{ .col = 5, .row = 5, .w = 10, .h = 3 });
    link_children(root, &.{button});

    push_event(&arena, .{ .mouse = .{ .kind = .press, .button = .left, .col = 40, .row = 20, .mods = .{} } });
    push_event(&arena, .{ .mouse = .{ .kind = .release, .button = .left, .col = 40, .row = 20, .mods = .{} } });

    process_events(root);
    const sig = signal_from_box(button);

    try testing.expect(!sig.flags.left_pressed);
    try testing.expect(!sig.flags.left_released);
    try testing.expect(!sig.flags.left_clicked);
    try testing.expect(!sig.flags.hovering);
    try testing.expect(!sig.flags.mouse_over);
}

test "tab cycles focus between three focusable boxes" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    reset();

    const root = make_test_box(&arena, "root###r", .{}, .{ .col = 0, .row = 0, .w = 80, .h = 24 });
    const box_a = make_test_box(&arena, "a###a", .{ .focus_hot = true }, .{ .col = 0, .row = 0, .w = 20, .h = 3 });
    const box_b = make_test_box(&arena, "b###b", .{ .focus_hot = true }, .{ .col = 20, .row = 0, .w = 20, .h = 3 });
    const box_c = make_test_box(&arena, "c###c", .{ .focus_hot = true }, .{ .col = 40, .row = 0, .w = 20, .h = 3 });
    link_children(root, &.{ box_a, box_b, box_c });

    // Tab 1: no focus → first box
    begin_frame();
    push_event(&arena, .{ .key = .{ .key = .tab, .mods = .{} } });
    process_events(root);
    try testing.expect(state.focus_hot_key.eql(box_a.key));

    // Unlink and re-link to reset tree for next iteration
    // (tree_next depends on tree links being correct)
    // Tab 2: a → b
    begin_frame();
    push_event(&arena, .{ .key = .{ .key = .tab, .mods = .{} } });
    process_events(root);
    try testing.expect(state.focus_hot_key.eql(box_b.key));

    // Tab 3: b → c
    begin_frame();
    push_event(&arena, .{ .key = .{ .key = .tab, .mods = .{} } });
    process_events(root);
    try testing.expect(state.focus_hot_key.eql(box_c.key));

    // Tab 4: c → wraps to a
    begin_frame();
    push_event(&arena, .{ .key = .{ .key = .tab, .mods = .{} } });
    process_events(root);
    try testing.expect(state.focus_hot_key.eql(box_a.key));

    // Shift+Tab: a → wraps to c
    begin_frame();
    push_event(&arena, .{ .key = .{ .key = .tab, .mods = .{ .shift = true } } });
    process_events(root);
    try testing.expect(state.focus_hot_key.eql(box_c.key));
}

test "keyboard enter on focused box produces keyboard_pressed signal" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    reset();

    const root = make_test_box(&arena, "root###r", .{}, .{ .col = 0, .row = 0, .w = 80, .h = 24 });
    const button = make_test_box(&arena, "btn###b", .{
        .focus_hot = true,
        .keyboard_clickable = true,
    }, .{ .col = 5, .row = 5, .w = 10, .h = 3 });
    link_children(root, &.{button});

    // Tab to focus the button
    begin_frame();
    push_event(&arena, .{ .key = .{ .key = .tab, .mods = .{} } });
    process_events(root);
    try testing.expect(state.focus_hot_key.eql(button.key));

    // Press enter
    begin_frame();
    push_event(&arena, .{ .key = .{ .key = .enter, .mods = .{} } });
    process_events(root);
    const sig = signal_from_box(button);

    try testing.expect(sig.flags.keyboard_pressed);
    try testing.expect(sig.flags.commit);
}

test "scroll event on scrollable box produces scroll delta in signal" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    reset();
    begin_frame();

    const root = make_test_box(&arena, "root###r", .{}, .{ .col = 0, .row = 0, .w = 80, .h = 24 });
    const scroller = make_test_box(&arena, "scr###s", .{
        .view_scroll = true,
        .clickable = true,
    }, .{ .col = 0, .row = 0, .w = 40, .h = 20 });
    link_children(root, &.{scroller});

    push_event(&arena, .{ .mouse = .{ .kind = .scroll_down, .button = .none, .col = 10, .row = 10, .mods = .{} } });
    push_event(&arena, .{ .mouse = .{ .kind = .scroll_down, .button = .none, .col = 10, .row = 10, .mods = .{} } });
    push_event(&arena, .{ .mouse = .{ .kind = .scroll_up, .button = .none, .col = 10, .row = 10, .mods = .{} } });

    process_events(root);
    const sig = signal_from_box(scroller);

    try testing.expectEqual(@as(i16, 1), sig.scroll[1]);
    try testing.expectEqual(@as(i16, 0), sig.scroll[0]);
}

test "scroll event outside scrollable box produces no delta" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    reset();
    begin_frame();

    const root = make_test_box(&arena, "root###r", .{}, .{ .col = 0, .row = 0, .w = 80, .h = 24 });
    const scroller = make_test_box(&arena, "scr###s", .{
        .view_scroll = true,
        .clickable = true,
    }, .{ .col = 0, .row = 0, .w = 10, .h = 10 });
    link_children(root, &.{scroller});

    push_event(&arena, .{ .mouse = .{ .kind = .scroll_down, .button = .none, .col = 50, .row = 50, .mods = .{} } });

    process_events(root);
    const sig = signal_from_box(scroller);

    try testing.expectEqual(@as(i16, 0), sig.scroll[1]);
}

test "disabled box produces no signal" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    reset();
    begin_frame();

    const root = make_test_box(&arena, "root###r", .{}, .{ .col = 0, .row = 0, .w = 80, .h = 24 });
    const button = make_test_box(&arena, "btn###b", .{
        .clickable = true,
        .disabled = true,
    }, .{ .col = 5, .row = 5, .w = 10, .h = 3 });
    link_children(root, &.{button});

    push_event(&arena, .{ .mouse = .{ .kind = .press, .button = .left, .col = 7, .row = 6, .mods = .{} } });

    process_events(root);
    const sig = signal_from_box(button);

    try testing.expect(!sig.flags.left_pressed);
    try testing.expect(!sig.flags.any());
}

test "mouse click transfers focus to clicked focusable box" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    reset();

    const root = make_test_box(&arena, "root###r", .{}, .{ .col = 0, .row = 0, .w = 80, .h = 24 });
    const box_a = make_test_box(&arena, "a###a", .{
        .clickable = true,
        .focus_hot = true,
    }, .{ .col = 0, .row = 0, .w = 20, .h = 3 });
    const box_b = make_test_box(&arena, "b###b", .{
        .clickable = true,
        .focus_hot = true,
    }, .{ .col = 20, .row = 0, .w = 20, .h = 3 });
    link_children(root, &.{ box_a, box_b });

    // Tab to focus box_a
    begin_frame();
    push_event(&arena, .{ .key = .{ .key = .tab, .mods = .{} } });
    process_events(root);
    try testing.expect(state.focus_hot_key.eql(box_a.key));

    // Click on box_b → focus should move to box_b
    begin_frame();
    push_event(&arena, .{ .mouse = .{ .kind = .press, .button = .left, .col = 25, .row = 1, .mods = .{} } });
    process_events(root);
    try testing.expect(state.focus_hot_key.eql(box_b.key));
}

test "right click inside a button box produces right_clicked signal" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    reset();
    begin_frame();

    const root = make_test_box(&arena, "root###r", .{}, .{ .col = 0, .row = 0, .w = 80, .h = 24 });
    const button = make_test_box(&arena, "btn###b", .{
        .clickable = true,
    }, .{ .col = 5, .row = 5, .w = 10, .h = 3 });
    link_children(root, &.{button});

    push_event(&arena, .{ .mouse = .{ .kind = .press, .button = .right, .col = 7, .row = 6, .mods = .{} } });
    push_event(&arena, .{ .mouse = .{ .kind = .release, .button = .right, .col = 7, .row = 6, .mods = .{} } });

    process_events(root);
    const sig = signal_from_box(button);

    try testing.expect(sig.flags.right_pressed);
    try testing.expect(sig.flags.right_released);
    try testing.expect(sig.flags.right_clicked);
}

test "press inside release outside produces released but not clicked" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    reset();
    begin_frame();

    const root = make_test_box(&arena, "root###r", .{}, .{ .col = 0, .row = 0, .w = 80, .h = 24 });
    const button = make_test_box(&arena, "btn###b", .{
        .clickable = true,
    }, .{ .col = 5, .row = 5, .w = 10, .h = 3 });
    link_children(root, &.{button});

    push_event(&arena, .{ .mouse = .{ .kind = .press, .button = .left, .col = 7, .row = 6, .mods = .{} } });
    push_event(&arena, .{ .mouse = .{ .kind = .release, .button = .left, .col = 50, .row = 50, .mods = .{} } });

    process_events(root);
    const sig = signal_from_box(button);

    try testing.expect(sig.flags.left_pressed);
    try testing.expect(sig.flags.left_released);
    try testing.expect(!sig.flags.left_clicked);
}
