const std = @import("std");
const base = @import("base");
const Arena = base.Arena;
const term = @import("term");
const draw = term.draw;
const Grid = draw.Grid;
const ui = @import("ui");
const BoxFlags = ui.BoxFlags;
const Size = ui.Size;
const Color = ui.Color;
const Rect = ui.Rect;
const Box = ui.Box;
const interaction = ui.interaction;
const widgets = ui.widgets;

// ---------------------------------------------------------------------------
// Colors
// ---------------------------------------------------------------------------

const bg_color: Color = .{ .rgb = .{ 20, 20, 30 } };
const fg_color: Color = .{ .ansi = .white };
const accent_color: Color = .{ .ansi = .cyan };
const muted_color: Color = .{ .ansi = .bright_black };
const panel_bg: Color = .{ .rgb = .{ 30, 30, 45 } };
const button_bg: Color = .{ .rgb = .{ 50, 50, 70 } };
const bar_filled: Color = .{ .ansi = .green };
const bar_empty: Color = .{ .rgb = .{ 40, 40, 50 } };
const spark_color: Color = .{ .ansi = .cyan };

// ---------------------------------------------------------------------------
// Application state
// ---------------------------------------------------------------------------

const SPARKLINE_SAMPLES = 1024;

const App = struct {
    progress: f32 = 0.35,
    sparkline_data: [SPARKLINE_SAMPLES]f32 = initial_sparkline(),
    spark_head: usize = 0,
    spark_time: f32 = 0,
    spark_accum: f32 = 0,
};

fn initial_sparkline() [SPARKLINE_SAMPLES]f32 {
    @setEvalBranchQuota(2000);
    var data: [SPARKLINE_SAMPLES]f32 = undefined;
    for (&data, 0..) |*value, index| {
        const t: f32 = @as(f32, @floatFromInt(index)) * 0.15;
        value.* = 0.5 + 0.3 * @sin(t);
    }
    return data;
}

// ---------------------------------------------------------------------------
// Custom draw callbacks
// ---------------------------------------------------------------------------

fn draw_progress_bar(box: *Box, grid: *Grid, clip: Rect) void {
    const progress_ptr: *const f32 = ui.custom_draw_data(f32, box.custom_draw_user_data) orelse return;
    const progress = std.math.clamp(progress_ptr.*, 0, 1);

    const rect = box.rect;
    const inner_left = rect.col + 1;
    const inner_right = rect.col +| rect.w -| 1;
    const inner_width = inner_right -| inner_left;
    if (inner_width == 0) return;

    const filled_width: u16 = @intFromFloat(@as(f32, @floatFromInt(inner_width)) * progress);
    const row = rect.row +| rect.h / 2;

    const visible = Rect.intersect(rect, clip);
    if (visible.w == 0 or visible.h == 0) return;

    var col = inner_left;
    while (col < inner_right) : (col += 1) {
        if (!visible.contains(col, row)) continue;
        const is_filled = (col - inner_left) < filled_width;
        const cp: u21 = if (is_filled) '█' else '░';
        const color: Color = if (is_filled) bar_filled else bar_empty;
        draw.write_cell(grid, col, row, .{ .codepoint = cp, .fg = color, .bg = box.bg_color });
    }
}

const sparkline_blocks = [_]u21{ ' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█' };

fn draw_sparkline(box: *Box, grid: *Grid, clip: Rect) void {
    const app: *const App = ui.custom_draw_data(App, box.custom_draw_user_data) orelse return;
    const data = &app.sparkline_data;

    const rect = box.rect;
    const inner_left = rect.col;
    const inner_top = rect.row;
    const inner_width = rect.w;
    const inner_height = rect.h;
    if (inner_width == 0 or inner_height == 0) return;

    const visible = Rect.intersect(rect, clip);
    if (visible.w == 0 or visible.h == 0) return;

    const sample_count: usize = @min(@as(usize, inner_width), data.len);
    const start_sample = if (data.len > sample_count) data.len - sample_count else 0;

    for (0..sample_count) |sample_index| {
        const data_index = (app.spark_head + start_sample + sample_index) % data.len;
        const value = std.math.clamp(data[data_index], 0, 1);

        const col: u16 = inner_left +| @as(u16, @intCast(sample_index));

        const total_cells: f32 = @floatFromInt(inner_height);
        const filled_f = value * total_cells;
        const full_rows: u16 = @intFromFloat(@floor(filled_f));
        const fractional = filled_f - @floor(filled_f);
        const block_index: usize = @intFromFloat(fractional * 8);

        var row_offset: u16 = 0;
        while (row_offset < inner_height) : (row_offset += 1) {
            const row = inner_top +| (inner_height - 1 - row_offset);
            if (!visible.contains(col, row)) continue;

            const cp: u21 = if (row_offset < full_rows)
                '█'
            else if (row_offset == full_rows and block_index > 0)
                sparkline_blocks[block_index]
            else
                ' ';
            draw.write_cell(grid, col, row, .{ .codepoint = cp, .fg = spark_color, .bg = box.bg_color });
        }
    }
}

// ---------------------------------------------------------------------------
// UI building
// ---------------------------------------------------------------------------

fn build_ui(app: *App) void {
    _ = ui.push_color(fg_color);
    defer _ = ui.pop_color();

    build_title_bar();
    ui.spacer(.y, 1);
    build_progress_section(app);
    ui.spacer(.y, 1);
    build_sparkline_section(app);
    build_status_bar();
}

fn build_title_bar() void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    ui.next_bg(accent_color);
    _ = ui.push_parent_box("", .{ .draw_background = true });
    defer ui.pop_parent();

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.push_color(bg_color);
    defer _ = ui.pop_color();
    _ = ui.build_box(" Custom Draw & Fastpath Demo", .{ .draw_text = true });
}

fn build_progress_section(app: *App) void {
    ui.next_width(.pct(1, 0));
    _ = ui.push_bg(panel_bg);
    defer _ = ui.pop_bg();
    _ = ui.push_border_color(muted_color);
    defer _ = ui.pop_border_color();
    _ = widgets.panel_begin(" Progress Bar ##progress_panel");
    defer widgets.panel_end();

    ui.spacer(.y, 1);

    {
        _ = ui.push_text_padding(1);
        defer _ = ui.pop_text_padding();
        const pct_label = ui.arena_print("Progress: {d:.0}%", .{app.progress * 100}) catch "Progress:";
        _ = widgets.label(pct_label);
    }

    ui.spacer(.y, 1);

    {
        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(3, 1));
        ui.next_bg(bg_color);
        const bar_box = ui.build_box("progress_bar###pbar", .{
            .draw_background = true,
            .draw_border = true,
            .draw_side_top = true,
            .draw_side_bottom = true,
            .draw_side_left = true,
            .draw_side_right = true,
        });
        bar_box.border_color = muted_color;
        bar_box.custom_draw = draw_progress_bar;
        bar_box.custom_draw_user_data = ui.custom_draw_data(f32, &app.progress);
    }

    ui.spacer(.y, 1);

    build_progress_buttons(app);

    ui.spacer(.y, 1);
}

fn build_progress_buttons(app: *App) void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 0));
    ui.next_height(.children(1));
    _ = ui.push_parent_box("pbar_btns###pbar_btns", .{});
    defer ui.pop_parent();

    ui.spacer(.x, 1);

    if (build_accel_button("Increment##inc_btn", 'i')) {
        app.progress = @min(1.0, app.progress + 0.05);
    }

    ui.spacer(.x, 1);

    if (build_accel_button("Decrement##dec_btn", 'd')) {
        app.progress = @max(0.0, app.progress - 0.05);
    }

    ui.spacer(.x, 1);

    if (build_accel_button("Fill##fill_btn", 'f')) {
        app.progress = 1.0;
    }

    ui.spacer(.x, 1);

    if (build_accel_button("Reset##reset_btn", 'r')) {
        app.progress = 0.0;
    }

    ui.spacer(.x, 1);
}

fn build_sparkline_section(app: *App) void {
    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    ui.next_bg(panel_bg);
    ui.next_border_color(muted_color);
    _ = ui.push_parent_box("spark_panel###spark_panel", .{
        .draw_background = true,
        .draw_border = true,
        .draw_side_top = true,
        .draw_side_bottom = true,
        .draw_side_left = true,
        .draw_side_right = true,
    });
    defer ui.pop_parent();

    {
        _ = ui.push_text_padding(1);
        defer _ = ui.pop_text_padding();
        _ = widgets.label("Sparkline (custom_draw)");
    }

    {
        ui.next_width(.pct(1, 0));
        ui.next_height(.pct(1, 0));
        ui.next_bg(bg_color);
        const spark_box = ui.build_box("sparkline###spark", .{
            .draw_background = true,
        });
        spark_box.custom_draw = draw_sparkline;
        spark_box.custom_draw_user_data = ui.custom_draw_data(App, app);
    }
}

fn build_accel_button(label: []const u8, codepoint: u21) bool {
    ui.next_width(.text(2, 1));
    ui.next_height(.cells(3, 1));
    _ = ui.push_bg(button_bg);
    defer _ = ui.pop_bg();
    _ = ui.push_color(fg_color);
    defer _ = ui.pop_color();
    _ = ui.push_border_color(accent_color);
    defer _ = ui.pop_border_color();
    ui.next_text_padding(1);
    const box = ui.build_box(label, .{
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
    });
    box.fastpath_codepoint = codepoint;
    return interaction.signal_from_box(box).clicked();
}

fn build_status_bar() void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    ui.next_bg(accent_color);
    _ = ui.push_parent_box("", .{ .draw_background = true });
    defer ui.pop_parent();

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.push_color(bg_color);
    defer _ = ui.pop_color();
    _ = ui.build_box(" Tab: focus | Enter/click: activate | i/d/f/r: accelerators | q: quit", .{ .draw_text = true });
}

// ---------------------------------------------------------------------------
// Fastpath accelerator dispatch
// ---------------------------------------------------------------------------

fn handle_accelerators(app: *App, ev: term.InputEvent) void {
    switch (ev) {
        .key => |key| {
            if (key.mods.ctrl or key.mods.alt) return;
            if (interaction.get_focus_active_key() != null) return;
            switch (key.codepoint) {
                'i' => app.progress = @min(1.0, app.progress + 0.05),
                'd' => app.progress = @max(0.0, app.progress - 0.05),
                'f' => app.progress = 1.0,
                'r' => app.progress = 0.0,
                else => {},
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// Sparkline animation
// ---------------------------------------------------------------------------

const advance_interval: f32 = 0.15;

fn advance_sparkline(app: *App, dt: f32) void {
    app.spark_accum += dt;
    while (app.spark_accum >= advance_interval) {
        app.spark_accum -= advance_interval;

        const index = app.spark_head;
        const prev = app.sparkline_data[(index + app.sparkline_data.len - 1) % app.sparkline_data.len];
        app.spark_time += advance_interval;
        const noise = 0.5 + 0.35 * @sin(app.spark_time * 1.3) + 0.15 * @cos(app.spark_time * 3.1);
        app.sparkline_data[index] = std.math.clamp(prev * 0.6 + noise * 0.4, 0, 1);
        app.spark_head = (index + 1) % app.sparkline_data.len;
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn is_quit(ev: term.InputEvent) bool {
    switch (ev) {
        .key => |key| {
            if (key.key == .escape) return true;
            if (key.key == .codepoint and key.codepoint == 'q' and
                !key.mods.ctrl and !key.mods.alt and
                interaction.get_focus_active_key() == null) return true;
            if (key.key == .codepoint and key.codepoint == 'c' and key.mods.ctrl) return true;
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

        advance_sparkline(&app, dt);

        interaction.begin_frame();

        if (try t.poll_event(50)) |ev| {
            if (ev == .resize) {
                // handled by check_resize
            } else {
                if (is_quit(ev)) return;
                handle_accelerators(&app, ev);
                interaction.push_event(&event_arena, ev);
                while (try t.poll_event(0)) |more| {
                    if (more == .resize) break;
                    if (is_quit(more)) return;
                    handle_accelerators(&app, more);
                    interaction.push_event(&event_arena, more);
                }
            }
        }

        const root = try ui.begin_build(&t, dt);
        root.flags.draw_background = true;
        root.bg_color = bg_color;

        build_ui(&app);

        ui.end_build();

        var grid = Grid.from_term(&t);
        ui.render.render(&grid, root);
        try t.flush();
    }
}

test {
    std.testing.refAllDecls(@This());
}
