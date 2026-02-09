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
// Persistent application state
// ---------------------------------------------------------------------------

const num_counters = 3;
const counter_labels = [num_counters][]const u8{ "Apples", "Bananas", "Cherries" };

const App = struct {
    counters: [num_counters]i32 = .{ 0, 0, 0 },
    theme: Theme = .dark,
};

const Theme = enum {
    dark,
    light,

    fn bg(theme: Theme) Color {
        return switch (theme) {
            .dark => .{ .ansi = .black },
            .light => .{ .ansi = .white },
        };
    }
    fn fg(theme: Theme) Color {
        return switch (theme) {
            .dark => .{ .ansi = .white },
            .light => .{ .ansi = .black },
        };
    }
    fn accent(theme: Theme) Color {
        return switch (theme) {
            .dark => .{ .ansi = .cyan },
            .light => .{ .ansi = .blue },
        };
    }
    fn muted(theme: Theme) Color {
        return switch (theme) {
            .dark => .{ .ansi = .bright_black },
            .light => .{ .ansi = .bright_black },
        };
    }
    fn panel_bg(theme: Theme) Color {
        return switch (theme) {
            .dark => .{ .rgb = .{ 30, 30, 40 } },
            .light => .{ .rgb = .{ 230, 230, 240 } },
        };
    }
    fn button_bg(theme: Theme) Color {
        return switch (theme) {
            .dark => .{ .rgb = .{ 50, 50, 70 } },
            .light => .{ .rgb = .{ 200, 200, 220 } },
        };
    }
    fn hot_bg(theme: Theme) Color {
        return switch (theme) {
            .dark => .{ .rgb = .{ 70, 70, 100 } },
            .light => .{ .rgb = .{ 170, 170, 210 } },
        };
    }
    fn active_bg(theme: Theme) Color {
        return switch (theme) {
            .dark => .{ .rgb = .{ 100, 100, 140 } },
            .light => .{ .rgb = .{ 140, 140, 190 } },
        };
    }
};

// ---------------------------------------------------------------------------
// Reusable flag bundles
// ---------------------------------------------------------------------------

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

const panel_flags: BoxFlags = .{
    .draw_background = true,
    .draw_border = true,
    .draw_side_top = true,
    .draw_side_bottom = true,
    .draw_side_left = true,
    .draw_side_right = true,
};

// ---------------------------------------------------------------------------
// Build the UI tree with inline signals
// ---------------------------------------------------------------------------

fn build_ui(app: *App) !void {
    const theme = app.theme;

    ui.push_color(theme.fg());
    defer ui.pop_color();

    build_title_bar(theme);
    ui.spacer(.y, 1);
    try build_counter_panels(app, theme);
    ui.spacer(.y, 1);
    build_action_row(app, theme);
    build_filler();
    build_status_bar(theme);
}

fn build_title_bar(theme: Theme) void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    ui.next_bg(theme.accent());
    ui.next_border_color(theme.accent());
    _ = ui.push_parent_box("", .{ .draw_background = true, .draw_border = true, .draw_side_bottom = true });
    defer ui.pop_parent();

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    ui.push_color(theme.bg());
    defer ui.pop_color();
    _ = ui.build_box(" UI Demo", .{ .draw_text = true });
}

fn build_counter_panels(app: *App, theme: Theme) !void {
    for (0..num_counters) |counter_index| {
        const panel_str = try ui.arena_print(" {s} ##counter_panel_{d}", .{ counter_labels[counter_index], counter_index });

        ui.next_width(.pct(1, 0));
        ui.next_height(.children(1));
        ui.push_bg(theme.panel_bg());
        defer ui.pop_bg();
        ui.push_border_color(theme.muted());
        defer ui.pop_border_color();
        _ = ui.push_parent_box(panel_str, panel_flags);
        defer ui.pop_parent();

        build_counter_row(app, theme, counter_index);
    }
}

fn build_counter_row(app: *App, theme: Theme, counter_index: usize) void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 0));
    ui.next_height(.children(1));
    _ = ui.push_parent_box("", .{});
    defer ui.pop_parent();

    ui.spacer(.x, 1);

    const label_str = ui.arena_print(" {s}: ", .{counter_labels[counter_index]}) catch " : ";
    ui.next_width(.text(0, 1));
    ui.next_height(.pct(1, 0));
    ui.push_color(theme.accent());
    defer ui.pop_color();
    _ = ui.build_box(label_str, .{ .draw_text = true });

    const dec_str = ui.arena_print(" - ##dec_{d}", .{counter_index}) catch " - ";
    if (build_button(dec_str, theme).clicked()) {
        app.counters[counter_index] -= 1;
    }

    ui.spacer(.x, 1);

    const val_str = ui.arena_print(" {d} ", .{app.counters[counter_index]}) catch " 0 ";
    const val_color: Color = if (app.counters[counter_index] < 0)
        .{ .ansi = .red }
    else if (app.counters[counter_index] > 0)
        .{ .ansi = .green }
    else
        theme.fg();
    ui.next_width(.text(0, 1));
    ui.next_height(.pct(1, 0));
    ui.push_color(val_color);
    defer ui.pop_color();
    _ = ui.build_box(val_str, .{ .draw_text = true });

    ui.spacer(.x, 1);

    const inc_str = ui.arena_print(" + ##inc_{d}", .{counter_index}) catch " + ";
    if (build_button(inc_str, theme).clicked()) {
        app.counters[counter_index] += 1;
    }

    ui.spacer(.x, 1);
}

fn build_action_row(app: *App, theme: Theme) void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 0));
    ui.next_height(.children(1));
    _ = ui.push_parent_box("", .{});
    defer ui.pop_parent();

    ui.spacer(.x, 2);

    if (build_button("Reset All", theme).clicked()) {
        app.counters = .{ 0, 0, 0 };
    }

    ui.spacer(.x, 2);

    const theme_label: []const u8 = if (app.theme == .dark)
        "Theme: Light##theme_toggle"
    else
        "Theme: Dark##theme_toggle";
    if (build_button(theme_label, theme).clicked()) {
        app.theme = if (app.theme == .dark) .light else .dark;
    }
}

fn build_filler() void {
    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.build_box("", .{});
}

fn build_status_bar(theme: Theme) void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    ui.next_bg(theme.accent());
    ui.next_border_color(theme.accent());
    _ = ui.push_parent_box("", .{ .draw_background = true, .draw_border = true, .draw_side_top = true });
    defer ui.pop_parent();

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    ui.push_color(theme.bg());
    defer ui.pop_color();
    _ = ui.build_box(" Mouse: click | Tab/Shift-Tab: focus | Enter: activate | q: quit", .{ .draw_text = true });
}

fn build_button(string: []const u8, theme: Theme) ui.Signal {
    ui.next_width(.text(2, 1));
    ui.next_height(.cells(3, 1));
    ui.push_bg(theme.button_bg());
    defer ui.pop_bg();
    ui.push_color(theme.fg());
    defer ui.pop_color();
    ui.push_border_color(theme.accent());
    defer ui.pop_border_color();
    ui.next_text_padding(1);
    const box = ui.build_box(string, button_flags);
    return interaction.signal_from_box(box);
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
        root.bg_color = app.theme.bg();

        try build_ui(&app);

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
