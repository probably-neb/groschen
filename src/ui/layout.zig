const std = @import("std");
const ui = @import("ui.zig");
const Box = ui.Box;
const Axis = ui.Axis;
const Size = ui.Size;
const SizeKind = ui.SizeKind;
const Rect = ui.Rect;
const BoxFlags = ui.BoxFlags;

/// Run the full layout algorithm on a box tree rooted at `root`.
/// Sets `root.rect` to the screen bounds, then runs all 5 passes
/// for X, then all 5 passes for Y.
pub fn layout(root: *Box, screen_w: u16, screen_h: u16) void {
    root.rect = .{ .col = 0, .row = 0, .w = screen_w, .h = screen_h };
    root.fixed_size = .{ @floatFromInt(screen_w), @floatFromInt(screen_h) };

    layout_axis(root, .x);
    layout_axis(root, .y);
}

fn layout_axis(root: *Box, comptime axis: Axis) void {
    pass_standalone(root, axis);
    pass_upwards_dependent(root, axis);
    pass_downwards_dependent(root, axis);
    pass_constraints(root, axis);
    pass_position(root, axis);
}

// -----------------------------------------------------------------------
// Pass 1: Standalone Sizes (cells, text_content)
// -----------------------------------------------------------------------

fn pass_standalone(root: *Box, comptime axis: Axis) void {
    var it: ?*Box = root.first;
    while (it) |b| {
        resolve_standalone(b, axis);
        it = tree_next_within(b, root);
    }
}

fn resolve_standalone(b: *Box, comptime axis: Axis) void {
    const ax = @intFromEnum(axis);
    const size = b.pref_size[ax];
    switch (size.kind) {
        .cells => b.fixed_size[ax] = size.value,
        .text_content => {
            if (axis == .x) {
                const text_len: f32 = @floatFromInt(display_width(b.display_string));
                b.fixed_size[ax] = text_len + size.value + @as(f32, @floatFromInt(b.text_padding)) * 2;
            } else {
                b.fixed_size[ax] = 1 + size.value;
            }
        },
        else => {},
    }
}

// -----------------------------------------------------------------------
// Pass 2: Upwards-Dependent Sizes (parent_pct)
// -----------------------------------------------------------------------

fn pass_upwards_dependent(root: *Box, comptime axis: Axis) void {
    var it: ?*Box = root.first;
    while (it) |b| {
        resolve_upwards(b, axis);
        it = tree_next_within(b, root);
    }
}

fn resolve_upwards(b: *Box, comptime axis: Axis) void {
    const ax = @intFromEnum(axis);
    if (b.pref_size[ax].kind != .parent_pct) return;

    const frac = b.pref_size[ax].value;
    const avail = ancestor_resolved_size(b, axis);
    b.fixed_size[ax] = @round(avail * frac);
}

fn ancestor_resolved_size(b: *Box, comptime axis: Axis) f32 {
    const ax = @intFromEnum(axis);
    var p = b.parent;
    while (p) |ancestor| {
        const kind = ancestor.pref_size[ax].kind;
        if (kind == .cells or kind == .text_content or kind == .null) {
            const insets = border_insets(ancestor);
            return @max(ancestor.fixed_size[ax] - insets.before[ax] - insets.after[ax], 0);
        }
        if (kind == .parent_pct and ancestor.fixed_size[ax] > 0) {
            const insets = border_insets(ancestor);
            return @max(ancestor.fixed_size[ax] - insets.before[ax] - insets.after[ax], 0);
        }
        p = ancestor.parent;
    }
    return 0;
}

// -----------------------------------------------------------------------
// Pass 3: Downwards-Dependent Sizes (children_sum) — post-order
// -----------------------------------------------------------------------

fn pass_downwards_dependent(root: *Box, comptime axis: Axis) void {
    post_order_walk(root, axis);
}

fn post_order_walk(node: *Box, comptime axis: Axis) void {
    var child = node.first;
    while (child) |c| {
        post_order_walk(c, axis);
        child = c.next;
    }
    resolve_downwards(node, axis);
}

fn resolve_downwards(b: *Box, comptime axis: Axis) void {
    const ax = @intFromEnum(axis);
    if (b.pref_size[ax].kind != .children_sum) return;

    const insets = border_insets(b);

    if (axis == b.child_layout_axis) {
        var sum: f32 = 0;
        var child = b.first;
        while (child) |c| {
            if (!is_floating(c, axis)) {
                sum += c.fixed_size[ax];
            }
            child = c.next;
        }
        b.fixed_size[ax] = sum + insets.before[ax] + insets.after[ax];
    } else {
        var max_cross: f32 = 0;
        var child = b.first;
        while (child) |c| {
            if (!is_floating(c, axis)) {
                max_cross = @max(max_cross, c.fixed_size[ax]);
            }
            child = c.next;
        }
        b.fixed_size[ax] = max_cross + insets.before[ax] + insets.after[ax];
    }
}

// -----------------------------------------------------------------------
// Pass 4: Constraint Enforcement
// -----------------------------------------------------------------------

fn pass_constraints(root: *Box, comptime axis: Axis) void {
    constrain_subtree(root, axis);
}

fn constrain_subtree(parent: *Box, comptime axis: Axis) void {
    const ax = @intFromEnum(axis);
    const insets = border_insets(parent);
    const avail = @max(parent.fixed_size[ax] - insets.before[ax] - insets.after[ax], 0);

    if (axis == parent.child_layout_axis) {
        constrain_layout_axis(parent, axis, avail);
    } else {
        constrain_cross_axis(parent, axis, avail);
    }

    var child = parent.first;
    while (child) |c| {
        constrain_subtree(c, axis);
        child = c.next;
    }
}

fn constrain_layout_axis(parent: *Box, comptime axis: Axis, avail: f32) void {
    const ax = @intFromEnum(axis);
    var total: f32 = 0;
    var shrinkable_total: f32 = 0;

    var child = parent.first;
    while (child) |c| {
        if (!is_floating(c, axis)) {
            total += c.fixed_size[ax];
            if (c.pref_size[ax].strictness < 1.0) {
                shrinkable_total += c.fixed_size[ax];
            }
        }
        child = c.next;
    }

    const overflow = total - avail;
    if (overflow <= 0 or shrinkable_total <= 0) return;

    const reduction = @min(overflow, shrinkable_total);

    child = parent.first;
    while (child) |c| {
        if (!is_floating(c, axis) and c.pref_size[ax].strictness < 1.0) {
            const weight = (1.0 - c.pref_size[ax].strictness);
            const share = if (shrinkable_total > 0)
                reduction * (c.fixed_size[ax] / shrinkable_total) * weight
            else
                0;
            c.fixed_size[ax] = @max(c.fixed_size[ax] - share, 0);
        }
        child = c.next;
    }
}

fn constrain_cross_axis(parent: *Box, comptime axis: Axis, avail: f32) void {
    const ax = @intFromEnum(axis);
    const allow_overflow = if (axis == .x) parent.flags.allow_overflow_x else parent.flags.allow_overflow_y;

    var child = parent.first;
    while (child) |c| {
        if (!is_floating(c, axis) and !allow_overflow) {
            c.fixed_size[ax] = @min(c.fixed_size[ax], avail);
        }
        child = c.next;
    }
}

// -----------------------------------------------------------------------
// Pass 5: Positioning
// -----------------------------------------------------------------------

fn pass_position(root: *Box, comptime axis: Axis) void {
    position_subtree(root, axis);
}

fn position_subtree(parent: *Box, comptime axis: Axis) void {
    const ax = @intFromEnum(axis);
    const insets = border_insets(parent);

    const parent_origin: f32 = if (axis == .x)
        @floatFromInt(parent.rect.col)
    else
        @floatFromInt(parent.rect.row);

    const avail = @max(parent.fixed_size[ax] - insets.before[ax] - insets.after[ax], 0);
    var cursor: f32 = parent_origin + insets.before[ax] - parent.view_off[ax];

    var child = parent.first;
    while (child) |c| {
        if (is_floating(c, axis)) {
            const pos = c.fixed_position[ax];
            set_rect_axis(c, axis, pos, c.fixed_size[ax]);
        } else {
            const size = snap(c.fixed_size[ax]);
            if (axis == parent.child_layout_axis) {
                set_rect_axis(c, axis, snap(cursor), size);
                cursor += c.fixed_size[ax];
            } else {
                const cross_pos = parent_origin + insets.before[ax];
                if (c.fixed_size[ax] <= 0) {
                    c.fixed_size[ax] = avail;
                }
                set_rect_axis(c, axis, snap(cross_pos), snap(c.fixed_size[ax]));
            }
        }

        c.fixed_size[ax] = @floatFromInt(rect_size(c, axis));

        position_subtree(c, axis);
        child = c.next;
    }
}

fn set_rect_axis(b: *Box, comptime axis: Axis, pos: f32, size: f32) void {
    const p = clamp_u16(pos);
    const s = clamp_u16(size);
    if (axis == .x) {
        b.rect.col = p;
        b.rect.w = s;
    } else {
        b.rect.row = p;
        b.rect.h = s;
    }
}

fn rect_size(b: *const Box, comptime axis: Axis) u16 {
    return if (axis == .x) b.rect.w else b.rect.h;
}

// -----------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------

fn border_insets(b: *const Box) struct { before: [2]f32, after: [2]f32 } {
    var before = [2]f32{ 0, 0 };
    var after = [2]f32{ 0, 0 };
    if (b.flags.draw_border) {
        if (b.flags.draw_side_left) before[0] = 1;
        if (b.flags.draw_side_right) after[0] = 1;
        if (b.flags.draw_side_top) before[1] = 1;
        if (b.flags.draw_side_bottom) after[1] = 1;
    }
    return .{ .before = before, .after = after };
}

fn is_floating(b: *const Box, comptime axis: Axis) bool {
    return if (axis == .x) b.flags.floating_x else b.flags.floating_y;
}

fn tree_next_within(current: *Box, root: *const Box) ?*Box {
    if (current.first) |first_child| return first_child;

    var node = current;
    while (true) {
        if (node == root) return null;
        if (node.next) |sibling| return sibling;
        node = node.parent orelse return null;
        if (node == root) return null;
    }
}

/// Measure display width in terminal columns.
/// For now this counts bytes, which is correct for ASCII.
/// TODO: proper unicode grapheme cluster / East Asian Width handling.
fn display_width(s: []const u8) usize {
    return s.len;
}

fn snap(v: f32) f32 {
    return @trunc(v);
}

fn clamp_u16(v: f32) u16 {
    if (v <= 0) return 0;
    if (v >= 65535) return 65535;
    return @intFromFloat(v);
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

const assert = std.debug.assert;
const testing = std.testing;
const base = @import("base");
const Arena = base.Arena;

fn make_box(arena: *Arena) !*Box {
    const b = try arena.create(Box);
    b.* = .{};
    return b;
}

fn link(parent: *Box, child: *Box) void {
    ui.push_child(parent, child);
}

test "three equal children in a row" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    const root = try make_box(&arena);
    root.pref_size = .{ Size.cells(30, 1), Size.cells(10, 1) };
    root.child_layout_axis = .x;

    var children: [3]*Box = undefined;
    for (&children) |*cp| {
        const c = try make_box(&arena);
        c.pref_size = .{ Size.cells(10, 1), Size.cells(10, 1) };
        link(root, c);
        cp.* = c;
    }

    layout(root, 30, 10);

    try testing.expectEqual(@as(u16, 0), children[0].rect.col);
    try testing.expectEqual(@as(u16, 10), children[0].rect.w);
    try testing.expectEqual(@as(u16, 10), children[1].rect.col);
    try testing.expectEqual(@as(u16, 10), children[1].rect.w);
    try testing.expectEqual(@as(u16, 20), children[2].rect.col);
    try testing.expectEqual(@as(u16, 10), children[2].rect.w);
}

test "parent_pct child" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    const root = try make_box(&arena);
    root.pref_size = .{ Size.cells(20, 1), Size.cells(10, 1) };
    root.child_layout_axis = .x;

    const child = try make_box(&arena);
    child.pref_size = .{ Size.pct(0.5, 1), Size.pct(1, 1) };
    link(root, child);

    layout(root, 20, 10);

    try testing.expectEqual(@as(u16, 10), child.rect.w);
    try testing.expectEqual(@as(u16, 10), child.rect.h);
}

test "children_sum parent" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    const root = try make_box(&arena);
    root.pref_size = .{ Size.cells(100, 1), Size.cells(100, 1) };
    root.child_layout_axis = .y;

    const container = try make_box(&arena);
    container.pref_size = .{ Size.children(1), Size.children(1) };
    container.child_layout_axis = .x;
    link(root, container);

    const c1 = try make_box(&arena);
    c1.pref_size = .{ Size.cells(5, 1), Size.cells(8, 1) };
    link(container, c1);

    const c2 = try make_box(&arena);
    c2.pref_size = .{ Size.cells(10, 1), Size.cells(6, 1) };
    link(container, c2);

    const c3 = try make_box(&arena);
    c3.pref_size = .{ Size.cells(8, 1), Size.cells(4, 1) };
    link(container, c3);

    layout(root, 100, 100);

    try testing.expectEqual(@as(u16, 23), container.rect.w);
    try testing.expectEqual(@as(u16, 8), container.rect.h);
}

test "overflow with strictness" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    const root = try make_box(&arena);
    root.pref_size = .{ Size.cells(30, 1), Size.cells(10, 1) };
    root.child_layout_axis = .x;

    const strict = try make_box(&arena);
    strict.pref_size = .{ Size.cells(20, 1), Size.cells(10, 1) };
    link(root, strict);

    const flex = try make_box(&arena);
    flex.pref_size = .{ Size.cells(20, 0), Size.cells(10, 1) };
    link(root, flex);

    layout(root, 30, 10);

    try testing.expectEqual(@as(u16, 20), strict.rect.w);
    try testing.expect(flex.rect.w <= 10);
}

test "nested row inside column" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    const root = try make_box(&arena);
    root.pref_size = .{ Size.cells(40, 1), Size.cells(20, 1) };
    root.child_layout_axis = .y;

    const row = try make_box(&arena);
    row.pref_size = .{ Size.pct(1, 1), Size.cells(5, 1) };
    row.child_layout_axis = .x;
    link(root, row);

    const left = try make_box(&arena);
    left.pref_size = .{ Size.cells(20, 1), Size.pct(1, 1) };
    link(row, left);

    const right = try make_box(&arena);
    right.pref_size = .{ Size.cells(20, 1), Size.pct(1, 1) };
    link(row, right);

    layout(root, 40, 20);

    try testing.expectEqual(@as(u16, 0), row.rect.col);
    try testing.expectEqual(@as(u16, 0), row.rect.row);
    try testing.expectEqual(@as(u16, 40), row.rect.w);
    try testing.expectEqual(@as(u16, 5), row.rect.h);

    try testing.expectEqual(@as(u16, 0), left.rect.col);
    try testing.expectEqual(@as(u16, 20), left.rect.w);
    try testing.expectEqual(@as(u16, 20), right.rect.col);
    try testing.expectEqual(@as(u16, 20), right.rect.w);
}

test "floating box uses fixed_position" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    const root = try make_box(&arena);
    root.pref_size = .{ Size.cells(80, 1), Size.cells(24, 1) };
    root.child_layout_axis = .y;

    const normal = try make_box(&arena);
    normal.pref_size = .{ Size.pct(1, 1), Size.cells(5, 1) };
    link(root, normal);

    const floating = try make_box(&arena);
    floating.pref_size = .{ Size.cells(10, 1), Size.cells(3, 1) };
    floating.flags.floating_x = true;
    floating.flags.floating_y = true;
    floating.fixed_position = .{ 30, 10 };
    link(root, floating);

    layout(root, 80, 24);

    try testing.expectEqual(@as(u16, 30), floating.rect.col);
    try testing.expectEqual(@as(u16, 10), floating.rect.row);
    try testing.expectEqual(@as(u16, 10), floating.rect.w);
    try testing.expectEqual(@as(u16, 3), floating.rect.h);
}

test "border insets reduce available space" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    const root = try make_box(&arena);
    root.pref_size = .{ Size.cells(20, 1), Size.cells(10, 1) };
    root.child_layout_axis = .x;
    root.flags.draw_border = true;
    root.flags.draw_side_left = true;
    root.flags.draw_side_right = true;
    root.flags.draw_side_top = true;
    root.flags.draw_side_bottom = true;

    const child = try make_box(&arena);
    child.pref_size = .{ Size.pct(1, 1), Size.pct(1, 1) };
    link(root, child);

    layout(root, 20, 10);

    try testing.expectEqual(@as(u16, 1), child.rect.col);
    try testing.expectEqual(@as(u16, 1), child.rect.row);
    try testing.expectEqual(@as(u16, 18), child.rect.w);
    try testing.expectEqual(@as(u16, 8), child.rect.h);
}

test "text_content sizing" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    const root = try make_box(&arena);
    root.pref_size = .{ Size.cells(80, 1), Size.cells(24, 1) };
    root.child_layout_axis = .y;

    const label = try make_box(&arena);
    label.display_string = "Hello";
    label.text_padding = 1;
    label.pref_size = .{ Size.text(0, 1), Size.text(0, 1) };
    link(root, label);

    layout(root, 80, 24);

    // "Hello" = 5 chars + 1 padding * 2 = 7
    try testing.expectEqual(@as(u16, 7), label.rect.w);
    try testing.expectEqual(@as(u16, 1), label.rect.h);
}
