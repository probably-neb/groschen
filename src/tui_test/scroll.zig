const std = @import("std");
const base = @import("base");
const Arena = base.Arena;
const term = @import("term");
const ui = @import("ui");
const BoxFlags = ui.BoxFlags;
const Size = ui.Size;
const Color = ui.Color;
const interaction = ui.interaction;

// ---------------------------------------------------------------------------
// Application state
// ---------------------------------------------------------------------------

const total_items: u32 = 1000;
const item_height: u32 = 1;
const scroll_speed: i32 = 3;

const App = struct {
    scroll_offset: i32 = 0,
    selected: ?u32 = null,
};

// ---------------------------------------------------------------------------
// Colors
// ---------------------------------------------------------------------------

const bg_color: Color = .{ .ansi = .black };
const fg_color: Color = .{ .ansi = .white };
const accent_color: Color = .{ .ansi = .cyan };

const even_bg: Color = .{ .rgb = .{ 25, 25, 35 } };
const odd_bg: Color = .{ .rgb = .{ 35, 35, 45 } };
const selected_bg: Color = .{ .rgb = .{ 50, 50, 90 } };

const scrollbar_bg: Color = .{ .rgb = .{ 40, 40, 50 } };
const scrollbar_fg: Color = .{ .ansi = .bright_white };

// ---------------------------------------------------------------------------
// Build with inline signals
// ---------------------------------------------------------------------------

fn build_ui(app: *App, visible_rows: u32) !void {
    _ = ui.push_color(fg_color);
    defer _ = ui.pop_color();

    build_title_bar();
    try build_main_area(app, visible_rows);
    try build_status_bar(app, visible_rows);
}

fn build_title_bar() void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    _ = ui.push_bg(accent_color);
    defer _ = ui.pop_bg();
    _ = ui.push_parent_box("", .{ .draw_background = true });
    defer ui.pop_parent();

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.push_color(bg_color);
    defer _ = ui.pop_color();
    _ = ui.build_box(" Scroll Demo — Virtualized List", .{ .draw_text = true });
}

fn build_main_area(app: *App, visible_rows: u32) !void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.pct(1, 0));
    _ = ui.push_parent_box("main_area###main", .{});
    defer ui.pop_parent();

    const scroll_box = try build_scroll_container(app, visible_rows);
    handle_scroll_input(app, scroll_box, visible_rows);
    build_scrollbar(app, visible_rows);
}

fn build_scroll_container(app: *App, visible_rows: u32) !*ui.Box {
    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 1));
    _ = ui.push_bg(.{ .rgb = .{ 20, 20, 30 } });
    defer _ = ui.pop_bg();
    const scroll_box = ui.push_parent_box("scroll_list###scroll", .{
        .clickable = true,
        .view_scroll = true,
        .focus_hot = true,
        .draw_background = true,
    });
    defer ui.pop_parent();

    const max_offset = max_scroll_offset(visible_rows);
    const offset: u32 = @intCast(@max(0, @min(app.scroll_offset, max_offset)));
    const end: u32 = @min(offset + visible_rows, total_items);

    for (offset..end) |item_index| {
        build_scroll_row(app, @intCast(item_index));
    }

    return scroll_box;
}

fn build_scroll_row(app: *App, index: u32) void {
    const is_selected = if (app.selected) |s| s == index else false;
    const row_bg: Color = if (is_selected)
        selected_bg
    else if (index % 2 == 0)
        even_bg
    else
        odd_bg;

    const item_str = ui.arena_print(" Item {d}###item_{d}", .{ index, index }) catch " Item ";
    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    _ = ui.push_bg(row_bg);
    defer _ = ui.pop_bg();
    _ = ui.push_color(if (is_selected) accent_color else fg_color);
    defer _ = ui.pop_color();
    const item_box = ui.build_box(item_str, .{
        .clickable = true,
        .draw_background = true,
        .draw_text = true,
    });

    const item_sig = interaction.signal_from_box(item_box);
    if (item_sig.flags.left_clicked) {
        app.selected = index;
    }
}

fn handle_scroll_input(app: *App, scroll_box: *ui.Box, visible_rows: u32) void {
    const scroll_sig = interaction.signal_from_box(scroll_box);
    if (scroll_sig.scroll[1] != 0) {
        apply_scroll(app, scroll_sig.scroll[1] * scroll_speed, visible_rows);
    }

    if (interaction.get_focus_hot_key().eql(scroll_box.key)) {
        handle_keyboard_scroll(app, visible_rows);
    }
}

fn build_scrollbar(app: *App, visible_rows: u32) void {
    ui.next_width(.cells(1, 1));
    ui.next_height(.pct(1, 1));
    _ = ui.push_bg(scrollbar_bg);
    defer _ = ui.pop_bg();
    _ = ui.push_parent_box("scrollbar###sbar", .{ .draw_background = true });
    defer ui.pop_parent();

    if (visible_rows < total_items and visible_rows > 0) {
        const max_offset = max_scroll_offset(visible_rows);
        const offset: u32 = @intCast(@max(0, @min(app.scroll_offset, max_offset)));
        const track_h: f32 = @floatFromInt(visible_rows);
        const thumb_h_f = @max(1.0, track_h * @as(f32, @floatFromInt(visible_rows)) / @as(f32, @floatFromInt(total_items)));
        const thumb_pos_f = track_h * @as(f32, @floatFromInt(offset)) / @as(f32, @floatFromInt(total_items));

        ui.next_width(.cells(1, 1));
        ui.next_height(.cells(thumb_pos_f, 1));
        _ = ui.build_box("", .{});

        ui.next_width(.cells(1, 1));
        ui.next_height(.cells(thumb_h_f, 1));
        _ = ui.push_bg(scrollbar_fg);
        defer _ = ui.pop_bg();
        _ = ui.build_box("scrollbar_thumb###thumb", .{ .draw_background = true });
    }
}

fn build_status_bar(app: *App, visible_rows: u32) !void {
    const max_off = max_scroll_offset(visible_rows);
    const current_offset: u32 = @intCast(@max(0, @min(app.scroll_offset, max_off)));
    const current_end: u32 = @min(current_offset + visible_rows, total_items);
    const sel_str: []const u8 = if (app.selected) |s| blk: {
        break :blk ui.arena_print("  Selected: {d}", .{s}) catch "";
    } else "";
    const status_str = try ui.arena_print(
        " Showing {d}-{d} of {d}  Offset: {d}{s}",
        .{ current_offset, if (current_end > 0) current_end - 1 else 0, total_items, current_offset, sel_str },
    );

    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    _ = ui.push_bg(accent_color);
    defer _ = ui.pop_bg();
    _ = ui.push_parent_box("", .{ .draw_background = true });
    defer ui.pop_parent();

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.push_color(bg_color);
    defer _ = ui.pop_color();
    _ = ui.build_box(status_str, .{ .draw_text = true });
}

fn max_scroll_offset(visible_rows: u32) i32 {
    return @as(i32, @intCast(total_items)) - @as(i32, @intCast(visible_rows));
}

fn handle_keyboard_scroll(app: *App, visible_rows: u32) void {
    var ev = interaction.get_events().first;
    while (ev) |e| : (ev = e.next) {
        if (e.consumed) continue;
        if (e.kind != .key_press) continue;

        switch (e.key) {
            .up => {
                apply_scroll(app, -1, visible_rows);
                e.consumed = true;
            },
            .down => {
                apply_scroll(app, 1, visible_rows);
                e.consumed = true;
            },
            .page_up => {
                apply_scroll(app, -@as(i32, @intCast(visible_rows)), visible_rows);
                e.consumed = true;
            },
            .page_down => {
                apply_scroll(app, @as(i32, @intCast(visible_rows)), visible_rows);
                e.consumed = true;
            },
            .home => {
                app.scroll_offset = 0;
                e.consumed = true;
            },
            .end => {
                app.scroll_offset = max_scroll_offset(visible_rows);
                e.consumed = true;
            },
            else => {},
        }
    }
}

fn apply_scroll(app: *App, delta: i32, visible_rows: u32) void {
    app.scroll_offset = @max(0, @min(app.scroll_offset + delta, max_scroll_offset(visible_rows)));
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn is_quit(ev: term.InputEvent) bool {
    switch (ev) {
        .key => |ke| {
            if (ke.key == .escape) return true;
            if (ke.key == .codepoint and ke.codepoint == 'q' and !ke.mods.ctrl and !ke.mods.alt) return true;
            if (ke.key == .codepoint and ke.codepoint == 'c' and ke.mods.ctrl) return true;
        },
        else => {},
    }
    return false;
}

pub fn run() !void {
    var perm_arena = try Arena.init(.{});
    defer perm_arena.deinit();

    var event_arena = try Arena.init(.{});
    defer event_arena.deinit();

    try ui.init_all();
    defer ui.deinit();

    var t = try term.init(&perm_arena);
    defer t.deinit();

    var app: App = .{};
    var last_time = std.time.Instant.now() catch null;

    while (true) {
        const ev_scope = event_arena.scoped();
        defer ev_scope.release();

        const now = std.time.Instant.now() catch null;
        const dt: f32 = if (now != null and last_time != null)
            @as(f32, @floatFromInt(now.?.since(last_time.?))) / std.time.ns_per_s
        else
            1.0 / 60.0;
        last_time = now;

        // -- Input ----------------------------------------------------------
        interaction.begin_frame();

        if (try t.poll_event(50)) |ev| {
            if (ev == .resize) {
                // Handled by check_resize below; don't enter drain loop
                // because poll_event returns .resize without clearing the
                // flag, which would spin forever.
            } else {
                if (is_quit(ev)) return;
                interaction.push_event(&event_arena, ev);
                while (try t.poll_event(0)) |more| {
                    if (more == .resize) break;
                    if (is_quit(more)) return;
                    interaction.push_event(&event_arena, more);
                }
            }
        }

        // -- Build (check_resize, clear, process_events run inside begin_build)
        const root = try ui.begin_build(&t, dt);
        root.flags.draw_background = true;
        root.bg_color = bg_color;

        // 2 rows for title + status bars
        const visible_rows: u32 = if (t.rows > 2) t.rows - 2 else 0;
        try build_ui(&app, visible_rows);

        ui.end_build();

        // -- Draw -----------------------------------------------------------
        var grid = term.draw.Grid.from_term(&t);
        ui.render.render(&grid, root);
        try t.flush();
    }
}

test {
    std.testing.refAllDecls(@This());
}
