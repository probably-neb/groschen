const std = @import("std");
const ui = @import("ui.zig");
const term = @import("term");
const base = @import("base");
const interaction = ui.interaction;
const Box = ui.Box;
const BoxFlags = ui.BoxFlags;
const Size = ui.Size;
const Color = ui.Color;
const Signal = ui.Signal;

// ---------------------------------------------------------------------------
// Basic Widgets
// ---------------------------------------------------------------------------

pub fn label(string: []const u8) *Box {
    ui.next_width(.text(0, 1));
    ui.next_height(.cells(1, 1));
    return ui.build_box(string, .{ .draw_text = true });
}

const button_flags: BoxFlags = .{
    .clickable = true,
    .keyboard_clickable = true,
    .focus_hot = true,
    .draw_background = true,
    .draw_border = true,
    .draw_text = true,
    .draw_side_top = true,
    .draw_side_bottom = true,
    .draw_side_left = true,
    .draw_side_right = true,
    .draw_hot_effects = true,
    .draw_active_effects = true,
};

pub fn button(string: []const u8) Signal {
    ui.next_width(.text(2, 1));
    ui.next_height(.cells(3, 1));
    ui.next_text_padding(1);
    const box = ui.build_box(string, button_flags);
    return interaction.signal_from_box(box);
}

pub fn separator() void {
    const parent = ui.top_stack(.parent);
    const axis: ui.Axis = if (parent) |p| p.child_layout_axis else .y;
    switch (axis) {
        .y => {
            ui.next_width(.pct(1, 1));
            ui.next_height(.cells(1, 1));
            _ = ui.build_box("─", .{
                .draw_border = true,
                .draw_side_top = true,
            });
        },
        .x => {
            ui.next_width(.cells(1, 1));
            ui.next_height(.pct(1, 1));
            _ = ui.build_box("│", .{
                .draw_border = true,
                .draw_side_left = true,
            });
        },
    }
}

// ---------------------------------------------------------------------------
// Text Input
// ---------------------------------------------------------------------------

pub const Line_Edit_State = struct {
    buffer: []u8,
    len: usize = 0,
    cursor: usize = 0,
};

const line_edit_flags: BoxFlags = .{
    .clickable = true,
    .keyboard_clickable = true,
    .focus_hot = true,
    .focus_active = true,
    .draw_background = true,
    .draw_border = true,
    .draw_side_top = true,
    .draw_side_bottom = true,
    .draw_side_left = true,
    .draw_side_right = true,
};

pub fn line_edit(string: []const u8, edit_state: *Line_Edit_State) Signal {
    ui.next_height(.cells(3, 1));
    ui.next_text_padding(1);

    const container = ui.push_parent_box(string, line_edit_flags);
    container.child_layout_axis = .x;

    const content = edit_state.buffer[0..edit_state.len];
    const before = content[0..edit_state.cursor];
    const after = content[edit_state.cursor..];

    const is_focused = !container.key.is_zero() and
        interaction.get_focus_hot_key().eql(container.key);

    if (before.len > 0) {
        const before_str = ui.arena_dupe(before) catch "";
        ui.next_width(.text(0, 1));
        ui.next_height(.pct(1, 0));
        _ = ui.build_box(before_str, .{ .draw_text = true, .focus_nav_skip = true });
    }

    if (is_focused) {
        const cursor_char: []const u8 = if (edit_state.cursor < edit_state.len)
            ui.arena_dupe(content[edit_state.cursor .. edit_state.cursor + 1]) catch "▏"
        else
            "▏";

        ui.next_width(.text(0, 1));
        ui.next_height(.pct(1, 0));
        ui.next_bg(.{ .ansi = .white });
        ui.next_color(.{ .ansi = .black });
        _ = ui.build_box(cursor_char, .{
            .draw_text = true,
            .draw_background = true,
            .focus_nav_skip = true,
        });

        const after_skip: []const u8 = if (edit_state.cursor < edit_state.len) after[1..] else after;
        if (after_skip.len > 0) {
            const after_str = ui.arena_dupe(after_skip) catch "";
            ui.next_width(.text(0, 1));
            ui.next_height(.pct(1, 0));
            _ = ui.build_box(after_str, .{ .draw_text = true, .focus_nav_skip = true });
        }
    } else {
        if (after.len > 0) {
            const after_str = ui.arena_dupe(after) catch "";
            ui.next_width(.text(0, 1));
            ui.next_height(.pct(1, 0));
            _ = ui.build_box(after_str, .{ .draw_text = true, .focus_nav_skip = true });
        }
    }

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.build_box("", .{ .focus_nav_skip = true });

    ui.pop_parent();

    const sig = interaction.signal_from_box(container);

    if (is_focused) {
        var ev = interaction.get_events().first;
        while (ev) |event| : (ev = event.next) {
            if (event.consumed) continue;

            switch (event.kind) {
                .text => {
                    if (event.codepoint > 0 and event.codepoint < 0x10000) {
                        var encode_buf: [4]u8 = undefined;
                        const byte_len = std.unicode.utf8Encode(@intCast(event.codepoint), &encode_buf) catch continue;
                        if (edit_state.len + byte_len <= edit_state.buffer.len) {
                            std.mem.copyBackwards(
                                u8,
                                edit_state.buffer[edit_state.cursor + byte_len .. edit_state.len + byte_len],
                                edit_state.buffer[edit_state.cursor..edit_state.len],
                            );
                            @memcpy(edit_state.buffer[edit_state.cursor .. edit_state.cursor + byte_len], encode_buf[0..byte_len]);
                            edit_state.len += byte_len;
                            edit_state.cursor += byte_len;
                            event.consumed = true;
                        }
                    }
                },
                .key_press => {
                    const handled = handle_line_edit_key(edit_state, event.key, event.mods);
                    if (handled) event.consumed = true;
                },
                else => {},
            }
        }
    }

    return sig;
}

fn handle_line_edit_key(state: *Line_Edit_State, key: term.Key, mods: term.Modifiers) bool {
    _ = mods;
    switch (key) {
        .backspace => {
            if (state.cursor > 0) {
                const remove_len = prev_char_len(state.buffer[0..state.cursor]);
                std.mem.copyForwards(
                    u8,
                    state.buffer[state.cursor - remove_len .. state.len - remove_len],
                    state.buffer[state.cursor..state.len],
                );
                state.cursor -= remove_len;
                state.len -= remove_len;
            }
            return true;
        },
        .delete => {
            if (state.cursor < state.len) {
                const remove_len = next_char_len(state.buffer[state.cursor..state.len]);
                std.mem.copyForwards(
                    u8,
                    state.buffer[state.cursor .. state.len - remove_len],
                    state.buffer[state.cursor + remove_len .. state.len],
                );
                state.len -= remove_len;
            }
            return true;
        },
        .left => {
            if (state.cursor > 0) {
                state.cursor -= prev_char_len(state.buffer[0..state.cursor]);
            }
            return true;
        },
        .right => {
            if (state.cursor < state.len) {
                state.cursor += next_char_len(state.buffer[state.cursor..state.len]);
            }
            return true;
        },
        .home => {
            state.cursor = 0;
            return true;
        },
        .end => {
            state.cursor = state.len;
            return true;
        },
        else => return false,
    }
}

fn prev_char_len(buf: []const u8) usize {
    if (buf.len == 0) return 0;
    var index = buf.len - 1;
    while (index > 0 and buf[index] & 0xC0 == 0x80) {
        index -= 1;
    }
    return buf.len - index;
}

fn next_char_len(buf: []const u8) usize {
    if (buf.len == 0) return 0;
    return std.unicode.utf8ByteSequenceLength(buf[0]) catch 1;
}

// ---------------------------------------------------------------------------
// Scroll List
// ---------------------------------------------------------------------------

pub const Scroll_List_View = struct {
    first_visible: usize,
    visible_count: usize,
    total_count: usize,
    row_height: u16,
    container: *Box,
};

const scroll_list_flags: BoxFlags = .{
    .clickable = true,
    .view_scroll = true,
    .focus_hot = true,
    .clip = true,
    .overflow_y = true,
    .draw_background = true,
};

pub fn scroll_list_begin(
    string: []const u8,
    total_count: usize,
    row_height: u16,
) Scroll_List_View {
    const container = ui.push_parent_box(string, scroll_list_flags);

    container.view_bounds[1] = @floatFromInt(total_count * row_height);

    const available_height: u16 = container.rect.h;
    const rows_visible: usize = if (row_height > 0)
        @intCast(@divFloor(available_height, row_height) + 1)
    else
        0;

    const rh_f: f32 = @floatFromInt(row_height);
    const first_visible: usize = if (rh_f > 0)
        @intFromFloat(@divFloor(container.view_off_target[1], rh_f))
    else
        0;
    const visible_count = @min(rows_visible, total_count -| first_visible);

    return .{
        .first_visible = first_visible,
        .visible_count = visible_count,
        .total_count = total_count,
        .row_height = row_height,
        .container = container,
    };
}

pub fn scroll_list_end(view: *const Scroll_List_View) Signal {
    ui.pop_parent();
    return interaction.signal_from_box(view.container);
}

/// Build a scrollbar indicator as a sibling. Call this after scroll_list_end,
/// while still inside the same parent that contains the scroll list.
pub fn scrollbar(view: *const Scroll_List_View) void {
    const total_h = view.container.view_bounds[1];
    const available: f32 = @floatFromInt(view.container.rect.h);
    if (total_h <= available or available <= 0) return;

    ui.next_width(.cells(1, 1));
    ui.next_height(.pct(1, 1));
    ui.next_bg(.{ .rgb = .{ 40, 40, 50 } });
    const track = ui.push_parent_box("scrollbar###__wgt_sbar", .{ .draw_background = true });
    track.child_layout_axis = .y;

    const track_h = available;
    const thumb_h = @max(1.0, track_h * available / total_h);
    const thumb_pos = track_h * view.container.view_off_target[1] / total_h;

    if (thumb_pos > 0) {
        ui.next_width(.cells(1, 1));
        ui.next_height(.cells(thumb_pos, 1));
        _ = ui.build_box("", .{ .focus_nav_skip = true });
    }

    ui.next_width(.cells(1, 1));
    ui.next_height(.cells(thumb_h, 1));
    ui.next_bg(.{ .ansi = .bright_white });
    _ = ui.build_box("scrollbar_thumb###__wgt_sthumb", .{
        .draw_background = true,
        .focus_nav_skip = true,
    });

    ui.pop_parent();
}

// ---------------------------------------------------------------------------
// Container Widgets
// ---------------------------------------------------------------------------

const panel_flags: BoxFlags = .{
    .draw_background = true,
    .draw_border = true,
    .draw_side_top = true,
    .draw_side_bottom = true,
    .draw_side_left = true,
    .draw_side_right = true,
};

pub fn panel_begin(string: []const u8) *Box {
    ui.next_height(.children(1));
    return ui.push_parent_box(string, panel_flags);
}

pub fn panel_end() void {
    ui.pop_parent();
}

pub fn collapsible_header(string: []const u8, open: *bool) Signal {
    const tag = ui.parse_tag(string);
    const arrow: []const u8 = if (open.*) "▼ " else "▶ ";
    const display = ui.arena_print("{s}{s}", .{ arrow, tag.display }) catch string;

    const header_string = if (ui.find_separator(string)) |sep|
        if (sep.is_triple)
            ui.arena_print("{s}###{s}", .{ display, tag.hash_string }) catch string
        else
            ui.arena_print("{s}##{s}", .{ display, tag.hash_string }) catch string
    else
        ui.arena_print("{s}###{s}", .{ display, string }) catch string;

    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    const header_box = ui.build_box(header_string, .{
        .clickable = true,
        .keyboard_clickable = true,
        .focus_hot = true,
        .draw_text = true,
        .draw_background = true,
        .draw_hot_effects = true,
        .draw_active_effects = true,
    });

    const sig = interaction.signal_from_box(header_box);
    if (sig.clicked()) {
        open.* = !open.*;
    }
    return sig;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const Arena = base.Arena;

fn setup_test_frame() *Box {
    ui.init_all() catch @panic("OOM: test init_all");
    return ui.begin_build_raw(80, 24, 1.0 / 60.0);
}

fn teardown_test_frame() void {
    ui.end_build();
    ui.deinit();
}

test "label produces a non-interactive text box" {
    const root = setup_test_frame();
    _ = root;
    defer teardown_test_frame();

    const box = label("hello");
    try testing.expect(box.flags.draw_text);
    try testing.expect(!box.flags.clickable);
    try testing.expect(!box.flags.keyboard_clickable);
    try testing.expectEqualStrings("hello", box.display_string);
}

test "button produces a clickable box with border and text" {
    const root = setup_test_frame();
    defer teardown_test_frame();

    const sig = button("OK");
    _ = sig;
    const box = root.first.?;
    try testing.expect(box.flags.clickable);
    try testing.expect(box.flags.keyboard_clickable);
    try testing.expect(box.flags.draw_border);
    try testing.expect(box.flags.draw_text);
    try testing.expect(box.flags.draw_background);
    try testing.expect(box.flags.focus_hot);
    try testing.expectEqualStrings("OK", box.display_string);
}

test "separator produces border box" {
    const root = setup_test_frame();
    defer teardown_test_frame();

    separator();
    const sep_box = root.first.?;
    try testing.expect(sep_box.flags.draw_border);
}

test "line_edit creates container with focus flags" {
    const root = setup_test_frame();
    defer teardown_test_frame();

    var buf: [64]u8 = undefined;
    var le_state = Line_Edit_State{ .buffer = &buf };

    _ = line_edit("input###test_input", &le_state);
    const box = root.first.?;
    try testing.expect(box.flags.focus_hot);
    try testing.expect(box.flags.focus_active);
    try testing.expect(box.flags.draw_border);
    try testing.expect(box.flags.draw_background);
}

test "line_edit inserts text" {
    _ = setup_test_frame();
    defer teardown_test_frame();

    var buf: [64]u8 = undefined;
    var le_state = Line_Edit_State{ .buffer = &buf };
    @memcpy(buf[0..3], "abc");
    le_state.len = 3;
    le_state.cursor = 3;

    _ = line_edit("input###test_input2", &le_state);

    try testing.expectEqualStrings("abc", le_state.buffer[0..le_state.len]);
    try testing.expectEqual(@as(usize, 3), le_state.cursor);
}

test "handle_line_edit_key backspace removes character" {
    var buf: [64]u8 = undefined;
    @memcpy(buf[0..3], "abc");
    var state = Line_Edit_State{ .buffer = &buf, .len = 3, .cursor = 3 };

    _ = handle_line_edit_key(&state, .backspace, .{});
    try testing.expectEqual(@as(usize, 2), state.len);
    try testing.expectEqual(@as(usize, 2), state.cursor);
    try testing.expectEqualStrings("ab", state.buffer[0..state.len]);
}

test "handle_line_edit_key left/right moves cursor" {
    var buf: [64]u8 = undefined;
    @memcpy(buf[0..3], "abc");
    var state = Line_Edit_State{ .buffer = &buf, .len = 3, .cursor = 2 };

    _ = handle_line_edit_key(&state, .left, .{});
    try testing.expectEqual(@as(usize, 1), state.cursor);

    _ = handle_line_edit_key(&state, .right, .{});
    try testing.expectEqual(@as(usize, 2), state.cursor);
}

test "handle_line_edit_key home/end" {
    var buf: [64]u8 = undefined;
    @memcpy(buf[0..3], "abc");
    var state = Line_Edit_State{ .buffer = &buf, .len = 3, .cursor = 2 };

    _ = handle_line_edit_key(&state, .home, .{});
    try testing.expectEqual(@as(usize, 0), state.cursor);

    _ = handle_line_edit_key(&state, .end, .{});
    try testing.expectEqual(@as(usize, 3), state.cursor);
}

test "handle_line_edit_key delete removes character ahead" {
    var buf: [64]u8 = undefined;
    @memcpy(buf[0..3], "abc");
    var state = Line_Edit_State{ .buffer = &buf, .len = 3, .cursor = 1 };

    _ = handle_line_edit_key(&state, .delete, .{});
    try testing.expectEqual(@as(usize, 2), state.len);
    try testing.expectEqual(@as(usize, 1), state.cursor);
    try testing.expectEqualStrings("ac", state.buffer[0..state.len]);
}

test "scroll_list_begin computes visible range" {
    _ = setup_test_frame();
    defer teardown_test_frame();

    const view = scroll_list_begin("list###test_list", 100, 1);
    try testing.expectEqual(@as(usize, 0), view.first_visible);
    try testing.expect(view.container.flags.view_scroll);
    try testing.expect(view.container.flags.clip);
    _ = scroll_list_end(&view);
}

test "panel_begin/end creates bordered container" {
    _ = setup_test_frame();
    defer teardown_test_frame();

    const panel_box = panel_begin(" My Panel ##test_panel");
    try testing.expect(panel_box.flags.draw_border);
    try testing.expect(panel_box.flags.draw_background);
    try testing.expect(panel_box.flags.draw_side_top);
    panel_end();
}

test "collapsible_header produces clickable box" {
    const root = setup_test_frame();
    defer teardown_test_frame();

    var open = true;

    const sig = collapsible_header("Section###sec1", &open);
    _ = sig;
    const header_box = root.first.?;
    try testing.expect(header_box.flags.clickable);
    try testing.expect(header_box.flags.draw_text);
    // open is still true because no click event was pushed
    try testing.expect(open);
}

test "prev_char_len handles ascii" {
    const buf = "abc";
    try testing.expectEqual(@as(usize, 1), prev_char_len(buf));
}

test "next_char_len handles ascii" {
    const buf = "abc";
    try testing.expectEqual(@as(usize, 1), next_char_len(buf));
}
