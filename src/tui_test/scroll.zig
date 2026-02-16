const std = @import("std");
const base = @import("base");
const Arena = base.Arena;
const term = @import("term");
const ui = @import("ui");
const BoxFlags = ui.BoxFlags;
const Size = ui.Size;
const Color = ui.Color;
const interaction = ui.interaction;
const widgets = @import("widgets");

// ---------------------------------------------------------------------------
// Application state
// ---------------------------------------------------------------------------

const total_items: u32 = 1000;
const item_height: u32 = 1;

const App = struct {
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
    ui.push_color(fg_color);
    defer ui.pop_color();

    build_title_bar();
    try build_main_area(app, visible_rows);
    try build_status_bar(app, visible_rows);
}

fn build_title_bar() void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    ui.push_bg(accent_color);
    defer ui.pop_bg();
    _ = ui.push_parent_box("", .{ .draw_background = true });
    defer ui.pop_parent();

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    ui.push_color(bg_color);
    defer ui.pop_color();
    _ = ui.build_box(" Scroll Demo — Virtualized List", .{ .draw_text = true });
}

fn build_main_area(app: *App, visible_rows: u32) !void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.pct(1, 0));
    _ = ui.push_parent_box("main_area###main", .{});
    defer ui.pop_parent();

    try build_scroll_list(app, visible_rows);
}

fn build_scroll_list(app: *App, visible_rows: u32) !void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.pct(1, 1));
    _ = ui.push_parent_box("scroll_area###scroll_wrap", .{});
    defer ui.pop_parent();

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 1));
    ui.next_bg(.{ .rgb = .{ 20, 20, 30 } });
    var view = widgets.scroll_list_begin(
        "scroll_list###scroll",
        total_items,
        @intCast(item_height),
    );

    for (view.first_visible..view.first_visible + view.visible_count) |item_index| {
        build_scroll_row(app, @intCast(item_index));
    }

    _ = widgets.scroll_list_end(&view);
    build_scrollbar_from_box(view.container, visible_rows);
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
    ui.push_bg(row_bg);
    defer ui.pop_bg();
    ui.push_color(if (is_selected) accent_color else fg_color);
    defer ui.pop_color();
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

fn build_scrollbar_from_box(container: *ui.Box, visible_rows: u32) void {
    const total_h = container.view_bounds[1];
    const avail: f32 = @floatFromInt(visible_rows);
    if (total_h <= avail or avail <= 0) return;

    ui.next_width(.cells(1, 1));
    ui.next_height(.pct(1, 1));
    ui.push_bg(scrollbar_bg);
    defer ui.pop_bg();
    _ = ui.push_parent_box("scrollbar###sbar", .{ .draw_background = true });
    defer ui.pop_parent();

    const track_h = avail;
    const thumb_h = @max(1.0, track_h * avail / total_h);
    const thumb_pos = track_h * container.view_off_target[1] / total_h;

    if (thumb_pos > 0) {
        ui.next_width(.cells(1, 1));
        ui.next_height(.cells(thumb_pos, 1));
        _ = ui.build_box("", .{});
    }

    ui.next_width(.cells(1, 1));
    ui.next_height(.cells(thumb_h, 1));
    ui.push_bg(scrollbar_fg);
    defer ui.pop_bg();
    _ = ui.build_box("scrollbar_thumb###thumb", .{ .draw_background = true });
}

fn build_status_bar(app: *App, visible_rows: u32) !void {
    const total_h: f32 = @floatFromInt(total_items * item_height);
    const avail: f32 = @floatFromInt(visible_rows);
    const max_offset = @max(0, total_h - avail);

    // We don't have access to the scroll box here, so display what we can.
    // Read from the scroll box would require passing it through; instead we
    // build the status from known constants and the selected item.
    const sel_str: []const u8 = if (app.selected) |s| blk: {
        break :blk ui.arena_print("  Selected: {d}", .{s}) catch "";
    } else "";
    const status_str = try ui.arena_print(
        " {d} items  Max scroll: {d:.0}{s}",
        .{ total_items, max_offset, sel_str },
    );

    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    ui.push_bg(accent_color);
    defer ui.pop_bg();
    _ = ui.push_parent_box("", .{ .draw_background = true });
    defer ui.pop_parent();

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    ui.push_color(bg_color);
    defer ui.pop_color();
    _ = ui.build_box(status_str, .{ .draw_text = true });
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
