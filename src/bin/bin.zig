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
// Colors
// ---------------------------------------------------------------------------

const bg_color: Color = .{ .rgb = .{ 20, 20, 30 } };
const fg_color: Color = .{ .ansi = .white };
const accent_color: Color = .{ .ansi = .cyan };
const muted_color: Color = .{ .ansi = .bright_black };
const panel_bg: Color = .{ .rgb = .{ 30, 30, 45 } };
const button_bg: Color = .{ .rgb = .{ 50, 50, 70 } };
const success_color: Color = .{ .ansi = .green };
const warning_color: Color = .{ .ansi = .yellow };

// ---------------------------------------------------------------------------
// Flag bundles
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
// Application state
// ---------------------------------------------------------------------------

const App = struct {
    click_count: i32 = 0,
    message: []const u8 = "Welcome! Use Tab to navigate, Enter to activate.",
    message_color: Color = fg_color,
};

// ---------------------------------------------------------------------------
// UI construction
// ---------------------------------------------------------------------------

const BuildResult = struct {
    hello_button: *Box,
    count_button: *Box,
    reset_button: *Box,
};

fn build_ui(app: *const App) !BuildResult {
    var result: BuildResult = undefined;

    _ = ui.push_color(fg_color);

    // Title bar
    {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 1));
        ui.next_height(.cells(1, 1));
        ui.next_bg(accent_color);
        _ = ui.push_parent_box("", .{ .draw_background = true });

        ui.next_width(.pct(1, 0));
        ui.next_height(.pct(1, 0));
        ui.next_color(bg_color);
        _ = ui.build_box(" Groschen", .{ .draw_text = true });

        ui.pop_parent();
    }

    ui.spacer(.y, 1);

    // Main content panel
    {
        ui.next_width(.pct(1, 0));
        ui.next_height(.children(1));
        ui.next_bg(panel_bg);
        ui.next_border_color(muted_color);
        _ = ui.push_parent_box(" Demo Panel ##main_panel", panel_flags);

        ui.spacer(.y, 1);

        // Message display
        {
            ui.next_width(.pct(1, 0));
            ui.next_height(.cells(1, 1));
            ui.next_color(app.message_color);
            ui.next_text_padding(1);
            _ = ui.build_box(app.message, .{ .draw_text = true });
        }

        ui.spacer(.y, 1);

        // Button row
        {
            ui.next_axis(.x);
            ui.next_width(.pct(1, 0));
            ui.next_height(.children(1));
            _ = ui.push_parent_box("", .{});

            ui.spacer(.x, 2);
            result.hello_button = build_button("Hello##hello_btn");
            ui.spacer(.x, 1);
            result.count_button = build_button(try ui.arena_print("Clicked: {d}##count_btn", .{app.click_count}));
            ui.spacer(.x, 1);
            result.reset_button = build_button("Reset##reset_btn");
            ui.spacer(.x, 2);

            ui.pop_parent();
        }

        ui.spacer(.y, 1);

        ui.pop_parent();
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
        ui.next_bg(accent_color);
        _ = ui.push_parent_box("", .{ .draw_background = true });

        ui.next_width(.pct(1, 0));
        ui.next_height(.pct(1, 0));
        ui.next_color(bg_color);
        _ = ui.build_box(" Tab: focus | Enter: activate | q/Esc: quit", .{ .draw_text = true });

        ui.pop_parent();
    }

    _ = ui.pop_color();

    return result;
}

fn build_button(string: []const u8) *Box {
    ui.next_width(.text(2, 1));
    ui.next_height(.cells(3, 1));
    ui.next_bg(button_bg);
    ui.next_color(fg_color);
    ui.next_border_color(accent_color);
    ui.next_text_padding(1);
    return ui.build_box(string, button_flags);
}

// ---------------------------------------------------------------------------
// Signal handling
// ---------------------------------------------------------------------------

fn handle_signals(app: *App, br: *const BuildResult) void {
    const hello_sig = interaction.signal_from_box(br.hello_button);
    if (hello_sig.flags.left_clicked or hello_sig.flags.keyboard_pressed) {
        app.message = "Hello from Groschen!";
        app.message_color = success_color;
    }

    const count_sig = interaction.signal_from_box(br.count_button);
    if (count_sig.flags.left_clicked or count_sig.flags.keyboard_pressed) {
        app.click_count += 1;
        app.message = "Button clicked!";
        app.message_color = accent_color;
    }

    const reset_sig = interaction.signal_from_box(br.reset_button);
    if (reset_sig.flags.left_clicked or reset_sig.flags.keyboard_pressed) {
        app.click_count = 0;
        app.message = "Counter reset.";
        app.message_color = warning_color;
    }
}

// ---------------------------------------------------------------------------
// Quit detection
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

// ---------------------------------------------------------------------------
// Frame loop
// ---------------------------------------------------------------------------

pub fn main() !void {
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

        // -- Delta time -----------------------------------------------------
        const now = std.time.Instant.now() catch null;
        const dt: f32 = if (now != null and last_time != null)
            @as(f32, @floatFromInt(now.?.since(last_time.?))) / std.time.ns_per_s
        else
            1.0 / 60.0;
        last_time = now;

        // -- Input ----------------------------------------------------------
        const timeout_ms: i32 = if (ui.is_animating()) 16 else 50;
        interaction.begin_frame();

        if (try t.poll_event(timeout_ms)) |ev| {
            if (ev == .resize) {
                // Handled by check_resize below
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
        root.bg_color = bg_color;

        const br = try build_ui(&app);

        ui.end_build();

        // -- Interaction ----------------------------------------------------
        interaction.process_events(root);
        handle_signals(&app, &br);

        // -- Draw -----------------------------------------------------------
        var grid = term.draw.Grid.from_term(&t);
        ui.render.render(&grid, root);
        try t.flush();
    }
}
