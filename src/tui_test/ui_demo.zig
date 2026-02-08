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

// ---------------------------------------------------------------------------
// Persistent application state
// ---------------------------------------------------------------------------

const num_counters = 3;
const counter_labels = [num_counters][]const u8{ "Apples", "Bananas", "Cherries" };

const App = struct {
    counters: [num_counters]i32 = .{ 0, 0, 0 },
    focus_index: u16 = 0,
    focus_count: u16 = 0,
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
// Build the UI tree
// ---------------------------------------------------------------------------

const BuildResult = struct {
    root: *Box,
    dec_buttons: [num_counters]*Box,
    inc_buttons: [num_counters]*Box,
    reset_button: *Box,
    theme_button: *Box,
};

fn build_ui(app: *App, cols: u16, rows: u16) !BuildResult {
    const theme = app.theme;

    // Root
    ui.next_width(.cells(@floatFromInt(cols), 1));
    ui.next_height(.cells(@floatFromInt(rows), 1));
    ui.next_bg(theme.bg());
    const root = ui.push_parent_box("root", .{ .draw_background = true });
    root.rect = .{ .col = 0, .row = 0, .w = cols, .h = rows };

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
    var result: BuildResult = undefined;
    result.root = root;

    _ = ui.push_color(theme.fg());

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

            // Counter name
            const label_str = try ui.arena_print(" {s}: ", .{counter_labels[ci]});
            ui.next_width(.text(0, 1));
            ui.next_height(.pct(1, 0));
            ui.next_color(theme.accent());
            _ = ui.build_box(label_str, .{ .draw_text = true });

            // [-] button
            const dec_str = try ui.arena_print(" - ##dec_{d}", .{ci});
            result.dec_buttons[ci] = build_button(dec_str, theme);

            ui.spacer(.x, 1);

            // Value
            const val_str = try ui.arena_print(" {d} ", .{app.counters[ci]});
            const val_color: Color = if (app.counters[ci] < 0) .{ .ansi = .red } else if (app.counters[ci] > 0) .{ .ansi = .green } else theme.fg();
            ui.next_width(.text(0, 1));
            ui.next_height(.pct(1, 0));
            ui.next_color(val_color);
            _ = ui.build_box(val_str, .{ .draw_text = true });

            ui.spacer(.x, 1);

            // [+] button
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

        ui.spacer(.x, 2);
        result.reset_button = build_button("Reset All", theme);
        ui.spacer(.x, 2);
        const theme_label: []const u8 = if (app.theme == .dark) "Theme: Light" else "Theme: Dark";
        result.theme_button = build_button(theme_label, theme);

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
        ui.next_bg(theme.accent());
        ui.next_border_color(theme.accent());
        _ = ui.push_parent_box("", .{ .draw_background = true, .draw_border = true, .draw_side_top = true });

        ui.next_width(.pct(1, 0));
        ui.next_height(.pct(1, 0));
        ui.next_color(theme.bg());
        _ = ui.build_box(" Mouse: click | Tab/Shift-Tab: focus | Enter: activate | q: quit", .{ .draw_text = true });

        ui.pop_parent();
    }

    ui.pop_parent(); // root

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
// Minimal layout engine
// ---------------------------------------------------------------------------

fn layout_tree(root: *Box) void {
    resolve_sizes(root);
    position_children(root);
}

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

fn resolve_sizes(b: *Box) void {
    var child = b.first;
    while (child) |c| : (child = c.next) {
        resolve_sizes(c);
    }
    for (0..2) |dim| {
        b.fixed_size[dim] = resolve_one(b.pref_size[dim], b, dim);
    }
}

fn resolve_one(size: Size, b: *const Box, dim: usize) f32 {
    return switch (size.kind) {
        .null => 0,
        .cells => size.value,
        .text_content => blk: {
            const tag = ui.parse_tag(b.display_string);
            const len: f32 = @floatFromInt(tag.display.len);
            break :blk len + size.value + @as(f32, @floatFromInt(b.text_padding)) * 2;
        },
        .parent_pct => 0,
        .children_sum => blk: {
            const ai: usize = @intFromEnum(b.child_layout_axis);
            const insets = border_insets(b);
            if (dim == ai) {
                var sum: f32 = insets.before[ai] + insets.after[ai];
                var c = b.first;
                while (c) |ch| : (c = ch.next) {
                    sum += ch.fixed_size[ai];
                }
                break :blk sum;
            } else {
                var max_cross: f32 = 0;
                var c = b.first;
                while (c) |ch| : (c = ch.next) {
                    max_cross = @max(max_cross, ch.fixed_size[dim]);
                }
                break :blk max_cross + insets.before[dim] + insets.after[dim];
            }
        },
    };
}

fn position_children(parent: *Box) void {
    const axis = parent.child_layout_axis;
    const ai: usize = @intFromEnum(axis);
    const cross: usize = ai ^ 1;
    const parent_size = [2]f32{
        @floatFromInt(parent.rect.w),
        @floatFromInt(parent.rect.h),
    };

    const insets = border_insets(parent);
    const avail = [2]f32{
        @max(parent_size[0] - insets.before[0] - insets.after[0], 0),
        @max(parent_size[1] - insets.before[1] - insets.after[1], 0),
    };

    var total_fixed: f32 = 0;
    var num_flex: f32 = 0;
    var child = parent.first;
    while (child) |c| : (child = c.next) {
        for (0..2) |dim| {
            if (c.pref_size[dim].kind == .parent_pct) {
                c.fixed_size[dim] = avail[dim] * c.pref_size[dim].value;
            }
        }
        if (c.pref_size[ai].kind == .parent_pct and c.pref_size[ai].strictness < 1) {
            num_flex += 1;
        } else {
            total_fixed += c.fixed_size[ai];
        }
    }

    const remaining = @max(avail[ai] - total_fixed, 0);
    if (num_flex > 0) {
        child = parent.first;
        while (child) |c| : (child = c.next) {
            if (c.pref_size[ai].kind == .parent_pct and c.pref_size[ai].strictness < 1) {
                c.fixed_size[ai] = remaining / num_flex;
            }
        }
    }

    var pos: f32 = insets.before[ai];
    const cross_start: f32 = insets.before[cross];
    child = parent.first;
    while (child) |c| : (child = c.next) {
        var child_pos: [2]f32 = undefined;
        child_pos[ai] = pos;
        child_pos[cross] = cross_start;

        if (c.fixed_size[cross] <= 0) {
            c.fixed_size[cross] = avail[cross];
        }

        const parent_col: f32 = @floatFromInt(parent.rect.col);
        const parent_row: f32 = @floatFromInt(parent.rect.row);

        c.rect = .{
            .col = @intFromFloat(@max(parent_col + child_pos[0], 0)),
            .row = @intFromFloat(@max(parent_row + child_pos[1], 0)),
            .w = @intFromFloat(@max(@min(c.fixed_size[0], avail[0]), 0)),
            .h = @intFromFloat(@max(@min(c.fixed_size[1], avail[1]), 0)),
        };

        pos += c.fixed_size[ai];
        position_children(c);
    }
}

// ---------------------------------------------------------------------------
// Minimal draw pass
// ---------------------------------------------------------------------------

fn draw_tree(t: *Term, root: *Box, app: *const App, focus_box: ?*const Box) void {
    draw_box(t, root, app, focus_box);
}

fn draw_box(t: *Term, b: *Box, app: *const App, focus_box: ?*const Box) void {
    const r = b.rect;
    if (r.w == 0 or r.h == 0) return;

    const is_focused = if (focus_box) |fb| fb == b else false;
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
        draw_box(t, c, app, focus_box);
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
// Minimal interaction
// ---------------------------------------------------------------------------

const FocusableList = struct {
    items: [32]*Box = undefined,
    count: u16 = 0,

    fn collect(self: *FocusableList, root: *Box) void {
        self.count = 0;
        self.walk(root);
    }

    fn walk(self: *FocusableList, b: *Box) void {
        if (b.flags.focus_hot and !b.flags.focus_nav_skip and self.count < 32) {
            self.items[self.count] = b;
            self.count += 1;
        }
        var child = b.first;
        while (child) |c| : (child = c.next) {
            self.walk(c);
        }
    }

    fn at(self: *const FocusableList, index: u16) ?*Box {
        if (self.count == 0) return null;
        return self.items[index % self.count];
    }

    fn index_of(self: *const FocusableList, b: *const Box) ?u16 {
        for (0..self.count) |i| {
            if (self.items[i] == b) return @intCast(i);
        }
        return null;
    }
};

fn hit_test(root: *Box, col: u16, row: u16) ?*Box {
    var result: ?*Box = null;
    hit_walk(root, col, row, &result);
    return result;
}

fn hit_walk(b: *Box, col: u16, row: u16, result: *?*Box) void {
    if (b.flags.clickable and b.rect.contains(col, row)) {
        result.* = b;
    }
    var child = b.first;
    while (child) |c| : (child = c.next) {
        hit_walk(c, col, row, result);
    }
}

fn signal_for_box(b: *Box, event: ?tui.term.InputEvent, focus_box: ?*Box) Signal {
    var sig = Signal{};
    const ev = event orelse return sig;

    switch (ev) {
        .mouse => |me| {
            const in_bounds = b.rect.contains(me.col, me.row);
            if (in_bounds) sig.flags.mouse_over = true;
            if (in_bounds and b.flags.clickable) {
                sig.mouse_pos = .{ me.col, me.row };
                switch (me.kind) {
                    .press => {
                        if (me.button == .left) sig.flags.left_pressed = true;
                        if (me.button == .right) sig.flags.right_pressed = true;
                    },
                    .release => {
                        if (me.button == .left) {
                            sig.flags.left_released = true;
                            sig.flags.left_clicked = true;
                        }
                        if (me.button == .right) {
                            sig.flags.right_released = true;
                            sig.flags.right_clicked = true;
                        }
                    },
                    .scroll_up => sig.scroll[1] = -1,
                    .scroll_down => sig.scroll[1] = 1,
                    else => {},
                }
            }
        },
        .key => |ke| {
            if (focus_box) |fb| {
                if (fb == b and b.flags.keyboard_clickable) {
                    if (ke.key == .enter or (ke.key == .codepoint and ke.codepoint == ' ')) {
                        sig.flags.keyboard_pressed = true;
                        sig.flags.left_clicked = true;
                    }
                }
            }
        },
        .resize => {},
    }

    return sig;
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

pub fn run() !void {
    var perm_arena = try Arena.init(.{});
    defer perm_arena.deinit();

    var frame_arena = try Arena.init(.{});
    defer frame_arena.deinit();

    var t = try Term.init(&perm_arena);
    defer t.deinit();

    var app: App = .{};
    var focusables: FocusableList = .{};
    var mouse_col: u16 = 0;
    var mouse_row: u16 = 0;

    while (true) {
        const scope = frame_arena.scoped();
        defer scope.release();

        _ = try t.check_resize();
        t.clear();

        ui.init(&frame_arena);
        const br = try build_ui(&app, t.cols, t.rows);

        layout_tree(br.root);

        focusables.collect(br.root);
        app.focus_count = focusables.count;
        if (app.focus_count > 0 and app.focus_index >= app.focus_count) {
            app.focus_index = 0;
        }

        if (hit_test(br.root, mouse_col, mouse_row)) |hovered| {
            hovered.hot_t = 1;
        }

        const focus_box = focusables.at(app.focus_index);
        draw_tree(&t, br.root, &app, focus_box);

        try t.flush();

        const event = try t.poll_event(50) orelse continue;

        switch (event) {
            .key => |ke| {
                if (ke.key == .codepoint and ke.codepoint == 'q' and !ke.mods.ctrl and !ke.mods.alt) return;
                if (ke.key == .codepoint and ke.codepoint == 'c' and ke.mods.ctrl) return;

                if (ke.key == .tab and ke.mods.shift) {
                    if (app.focus_count > 0) {
                        app.focus_index = if (app.focus_index == 0) app.focus_count - 1 else app.focus_index - 1;
                    }
                } else if (ke.key == .tab) {
                    if (app.focus_count > 0) {
                        app.focus_index = (app.focus_index + 1) % app.focus_count;
                    }
                } else if (ke.key == .enter or (ke.key == .codepoint and ke.codepoint == ' ')) {
                    if (focus_box) |fb| {
                        const sig = signal_for_box(fb, event, focus_box);
                        handle_signals(&app, &br, fb, sig);
                    }
                }
            },
            .mouse => |me| {
                mouse_col = me.col;
                mouse_row = me.row;
                if (me.kind == .press or me.kind == .release) {
                    if (hit_test(br.root, me.col, me.row)) |clicked| {
                        const sig = signal_for_box(clicked, event, focus_box);
                        if (sig.flags.left_clicked or sig.flags.left_pressed) {
                            if (focusables.index_of(clicked)) |idx| {
                                app.focus_index = idx;
                            }
                        }
                        handle_signals(&app, &br, clicked, sig);
                    }
                }
            },
            .resize => {},
        }
    }
}

fn handle_signals(app: *App, br: *const BuildResult, b: *Box, sig: Signal) void {
    if (!sig.flags.left_clicked) return;

    for (0..num_counters) |ci| {
        if (b == br.dec_buttons[ci]) {
            app.counters[ci] -= 1;
            return;
        }
        if (b == br.inc_buttons[ci]) {
            app.counters[ci] += 1;
            return;
        }
    }

    if (b == br.reset_button) {
        app.counters = .{ 0, 0, 0 };
        return;
    }

    if (b == br.theme_button) {
        app.theme = if (app.theme == .dark) .light else .dark;
        return;
    }
}
