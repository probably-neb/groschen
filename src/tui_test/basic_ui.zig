const std = @import("std");
const base = @import("base");
const Arena = base.Arena;
const tui = @import("tui");
const Term = tui.term.Term;
const Attrs = tui.term.Attrs;
const ui = @import("ui");
const Box = ui.Box;
const BoxFlags = ui.BoxFlags;
const Size = ui.Size;
const Rect = ui.Rect;
const Color = ui.Color;
const Signal = ui.Signal;
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
    const tag = ui.parse_tag(string);
    const text_w: f32 = @floatFromInt(tag.display.len);
    ui.next_width(.cells(text_w + 4, 1));
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
// Draw pass (kept until Phase 4 draw.zig exists)
// ---------------------------------------------------------------------------

fn draw_tree(t: *Term, root: *Box, app: *const App) void {
    draw_box(t, root, app);
}

fn draw_box(t: *Term, b: *Box, app: *const App) void {
    const r = b.rect;
    if (r.w == 0 or r.h == 0) return;

    const is_focused = !b.key.is_zero() and interaction.get_focus_hot_key().eql(b.key);
    const is_hot = b.hot_t > 0;
    const is_active = b.active_t > 0;

    if (b.flags.draw_background) {
        const bg_color = to_term_color(if (is_active and b.flags.draw_active_effects)
            app.theme.active_bg()
        else if (is_hot and b.flags.draw_hot_effects)
            app.theme.hot_bg()
        else
            b.bg_color);

        t.fill_rect(r.col, r.row, r.w, r.h, .{ .bg = bg_color });
    }

    if (b.flags.draw_border) {
        const border_c = to_term_color(if (is_focused) app.theme.accent() else b.border_color);
        draw_border(t, r, b.flags, border_c, is_focused);
    }

    if (b.flags.draw_text and b.display_string.len > 0) {
        const text_col = r.col +| (if (b.flags.draw_border and b.flags.draw_side_left) @as(u16, 1) else 0) +| b.text_padding;
        const top_inset: u16 = if (b.flags.draw_border and b.flags.draw_side_top) 1 else 0;
        const bot_inset: u16 = if (b.flags.draw_border and b.flags.draw_side_bottom) 1 else 0;
        const inner_h = r.h -| top_inset -| bot_inset;
        const text_row = r.row +| top_inset +| (inner_h -| 1) / 2;
        const side_inset: u16 = (if (b.flags.draw_border and b.flags.draw_side_left) @as(u16, 1) else 0) +
            (if (b.flags.draw_border and b.flags.draw_side_right) @as(u16, 1) else 0) +
            b.text_padding * 2;
        const text_w = r.w -| side_inset;

        const fg = to_term_color(b.fg_color);
        const bg = to_term_color(if (is_active and b.flags.draw_active_effects)
            app.theme.active_bg()
        else if (is_hot and b.flags.draw_hot_effects)
            app.theme.hot_bg()
        else if (b.flags.draw_background)
            b.bg_color
        else
            app.theme.bg());
        const attrs: Attrs = if (is_focused) .{ .bold = true } else .{};

        const tag = ui.parse_tag(b.display_string);
        _ = t.write_text(text_col, text_row, text_w, tag.display, fg, bg, attrs);
    }

    var child = b.first;
    while (child) |c| : (child = c.next) {
        draw_box(t, c, app);
    }
}

fn draw_border(t: *Term, r: Rect, flags: BoxFlags, border_color: tui.term.Color, focused: bool) void {
    const top = flags.draw_side_top;
    const bottom = flags.draw_side_bottom;
    const left = flags.draw_side_left;
    const right = flags.draw_side_right;
    const attrs: Attrs = if (focused) .{ .bold = true } else .{};

    const x1 = r.col;
    const y1 = r.row;
    const x2 = r.col +| r.w -| 1;
    const y2 = r.row +| r.h -| 1;

    if (top) {
        var x = x1;
        while (x <= x2) : (x +|= 1) {
            const cp: u21 = if (x == x1 and left) (if (focused) '╔' else '┌') else if (x == x2 and right) (if (focused) '╗' else '┐') else (if (focused) '═' else '─');
            if (t.cell_at(x, y1)) |cell| {
                cell.* = .{ .codepoint = cp, .fg = border_color, .attrs = attrs };
            }
        }
    }

    if (bottom and r.h > 1) {
        var x = x1;
        while (x <= x2) : (x +|= 1) {
            const cp: u21 = if (x == x1 and left) (if (focused) '╚' else '└') else if (x == x2 and right) (if (focused) '╝' else '┘') else (if (focused) '═' else '─');
            if (t.cell_at(x, y2)) |cell| {
                cell.* = .{ .codepoint = cp, .fg = border_color, .attrs = attrs };
            }
        }
    }

    if (left and r.h > 1) {
        var y = y1 + 1;
        const y_end = if (bottom) y2 else y2 + 1;
        while (y < y_end) : (y += 1) {
            if (t.cell_at(x1, y)) |cell| {
                cell.* = .{ .codepoint = if (focused) '║' else '│', .fg = border_color, .attrs = attrs };
            }
        }
    }

    if (right and r.h > 1) {
        var y = y1 + 1;
        const y_end = if (bottom) y2 else y2 + 1;
        while (y < y_end) : (y += 1) {
            if (t.cell_at(x2, y)) |cell| {
                cell.* = .{ .codepoint = if (focused) '║' else '│', .fg = border_color, .attrs = attrs };
            }
        }
    }
}

fn to_term_color(c: Color) tui.term.Color {
    return switch (c) {
        .default => .default,
        .ansi => |a| .{ .ansi = @enumFromInt(@intFromEnum(a)) },
        .rgb => |v| .{ .rgb = v },
    };
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn is_quit(ev: tui.term.InputEvent) bool {
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

    var t = try Term.init(&perm_arena);
    defer t.deinit();

    var app: App = .{};

    while (true) {
        const ev_scope = event_arena.scoped();
        defer ev_scope.release();

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

        const root = ui.begin_build(t.cols, t.rows);
        root.flags.draw_background = true;
        root.bg_color = app.theme.bg();

        const br = try build_ui(&app);

        ui.end_build();

        // -- Interaction ----------------------------------------------------
        interaction.process_events(root);
        handle_all_signals(&app, &br);

        // -- Draw -----------------------------------------------------------
        draw_tree(&t, root, &app);
        try t.flush();
    }
}

test {
    std.testing.refAllDecls(@This());
}
