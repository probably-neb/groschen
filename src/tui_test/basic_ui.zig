const std = @import("std");
const base = @import("base");
const Arena = base.Arena;
const term = @import("term");
const ui = @import("ui");
const Box = ui.Box;
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

    fn bg(self: Theme) Color {
        return switch (self) {
            .dark => .{ .ansi = .black },
            .light => .{ .ansi = .white },
        };
    }
    fn fg(self: Theme) Color {
        return switch (self) {
            .dark => .{ .ansi = .white },
            .light => .{ .ansi = .black },
        };
    }
    fn accent(self: Theme) Color {
        return switch (self) {
            .dark => .{ .ansi = .cyan },
            .light => .{ .ansi = .blue },
        };
    }
    fn muted(self: Theme) Color {
        return switch (self) {
            .dark => .{ .ansi = .bright_black },
            .light => .{ .ansi = .bright_black },
        };
    }
    fn panel_bg(self: Theme) Color {
        return switch (self) {
            .dark => .{ .rgb = .{ 30, 30, 40 } },
            .light => .{ .rgb = .{ 230, 230, 240 } },
        };
    }
    fn button_bg(self: Theme) Color {
        return switch (self) {
            .dark => .{ .rgb = .{ 50, 50, 70 } },
            .light => .{ .rgb = .{ 200, 200, 220 } },
        };
    }
    fn hot_bg(self: Theme) Color {
        return switch (self) {
            .dark => .{ .rgb = .{ 70, 70, 100 } },
            .light => .{ .rgb = .{ 170, 170, 210 } },
        };
    }
    fn active_bg(self: Theme) Color {
        return switch (self) {
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
// Build the UI tree (children under begin_build's root)
// ---------------------------------------------------------------------------

const BuildResult = struct {
    dec_buttons: [num_counters]*Box,
    inc_buttons: [num_counters]*Box,
    reset_button: *Box,
    theme_button: *Box,
};

fn build_ui(app: *const App) !BuildResult {
    const theme = app.theme;
    var result: BuildResult = undefined;

    _ = ui.push_color(theme.fg());

    // Title bar
    {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 1));
        ui.next_height(.cells(1, 1));
        ui.next_bg(theme.accent());
        ui.next_border_color(theme.accent());
        _ = ui.push_parent_box("", .{ .draw_background = true, .draw_border = true, .draw_side_bottom = true });

        ui.next_width(.pct(1, 0));
        ui.next_height(.pct(1, 0));
        ui.next_color(theme.bg());
        _ = ui.build_box(" UI Demo", .{ .draw_text = true });

        ui.pop_parent();
    }

    ui.spacer(.y, 1);

    // Counter panels
    for (0..num_counters) |ci| {
        const panel_str = try ui.arena_print(" {s} ##counter_panel_{d}", .{ counter_labels[ci], ci });

        ui.next_width(.pct(1, 0));
        ui.next_height(.children(1));
        ui.next_bg(theme.panel_bg());
        ui.next_border_color(theme.muted());
        _ = ui.push_parent_box(panel_str, panel_flags);

        // Row
        {
            ui.next_axis(.x);
            ui.next_width(.pct(1, 0));
            ui.next_height(.children(1));
            _ = ui.push_parent_box("", .{});

            ui.spacer(.x, 1);

            const label_str = try ui.arena_print(" {s}: ", .{counter_labels[ci]});
            ui.next_width(.text(0, 1));
            ui.next_height(.pct(1, 0));
            ui.next_color(theme.accent());
            _ = ui.build_box(label_str, .{ .draw_text = true });

            const dec_str = try ui.arena_print(" - ##dec_{d}", .{ci});
            result.dec_buttons[ci] = build_button(dec_str, theme);

            ui.spacer(.x, 1);

            const val_str = try ui.arena_print(" {d} ", .{app.counters[ci]});
            const val_color: Color = if (app.counters[ci] < 0) .{ .ansi = .red } else if (app.counters[ci] > 0) .{ .ansi = .green } else theme.fg();
            ui.next_width(.text(0, 1));
            ui.next_height(.pct(1, 0));
            ui.next_color(val_color);
            _ = ui.build_box(val_str, .{ .draw_text = true });

            ui.spacer(.x, 1);

            const inc_str = try ui.arena_print(" + ##inc_{d}", .{ci});
            result.inc_buttons[ci] = build_button(inc_str, theme);

            ui.spacer(.x, 1);

            ui.pop_parent();
        }

        ui.pop_parent();
    }

    _ = ui.pop_color();

    ui.spacer(.y, 1);

    // Action row
    {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 0));
        ui.next_height(.children(1));
        _ = ui.push_parent_box("", .{});
        defer ui.pop_parent();

        ui.spacer(.x, 2);
        result.reset_button = build_button("Reset All", theme);
        ui.spacer(.x, 2);
        const theme_label: []const u8 = if (app.theme == .dark) "Theme: Light##theme_toggle" else "Theme: Dark##theme_toggle";
        result.theme_button = build_button(theme_label, theme);
    }

    // Filler
    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.build_box("", .{});

    // Status bar
    {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 1));
        ui.next_height(.cells(1, 1));
        ui.next_bg(theme.accent());
        ui.next_border_color(theme.accent());
        _ = ui.push_parent_box("", .{ .draw_background = true, .draw_border = true, .draw_side_top = true });

        ui.next_width(.pct(1, 0));
        ui.next_height(.pct(1, 0));
        ui.next_color(theme.bg());
        _ = ui.build_box(" Mouse: click | Tab/Shift-Tab: focus | Enter: activate | q: quit", .{ .draw_text = true });

        ui.pop_parent();
    }

    return result;
}

fn build_button(string: []const u8, theme: Theme) *Box {
    ui.next_width(.text(2, 1));
    ui.next_height(.cells(3, 1));
    ui.next_bg(theme.button_bg());
    ui.next_color(theme.fg());
    ui.next_border_color(theme.accent());
    ui.next_text_padding(1);
    return ui.build_box(string, button_flags);
}

// ---------------------------------------------------------------------------
// Signal handling
// ---------------------------------------------------------------------------

fn handle_all_signals(app: *App, br: *const BuildResult) void {
    for (0..num_counters) |ci| {
        const dec_sig = interaction.signal_from_box(br.dec_buttons[ci]);
        if (dec_sig.flags.left_clicked or dec_sig.flags.keyboard_pressed)
            app.counters[ci] -= 1;

        const inc_sig = interaction.signal_from_box(br.inc_buttons[ci]);
        if (inc_sig.flags.left_clicked or inc_sig.flags.keyboard_pressed)
            app.counters[ci] += 1;
    }

    const reset_sig = interaction.signal_from_box(br.reset_button);
    if (reset_sig.flags.left_clicked or reset_sig.flags.keyboard_pressed)
        app.counters = .{ 0, 0, 0 };

    const theme_sig = interaction.signal_from_box(br.theme_button);
    if (theme_sig.flags.left_clicked or theme_sig.flags.keyboard_pressed)
        app.theme = if (app.theme == .dark) .light else .dark;
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

        // -- Build ----------------------------------------------------------
        _ = try t.check_resize();
        t.clear();

        const root = ui.begin_build(t.cols, t.rows, dt);
        root.flags.draw_background = true;
        root.bg_color = app.theme.bg();

        const br = try build_ui(&app);

        ui.end_build();

        // -- Interaction ----------------------------------------------------
        interaction.process_events(root);
        handle_all_signals(&app, &br);

        // -- Draw -----------------------------------------------------------
        var grid = term.draw.Grid.from_term(&t);
        ui.render.render(&grid, root);
        try t.flush();
    }
}

test {
    std.testing.refAllDecls(@This());
}
