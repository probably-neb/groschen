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
// Colors
// ---------------------------------------------------------------------------

const bg_color: Color = .{ .rgb = .{ 20, 20, 30 } };
const fg_color: Color = .{ .ansi = .white };
const accent_color: Color = .{ .ansi = .cyan };
const muted_color: Color = .{ .ansi = .bright_black };
const panel_bg: Color = .{ .rgb = .{ 30, 30, 45 } };
const button_bg: Color = .{ .rgb = .{ 50, 50, 70 } };
const input_bg: Color = .{ .rgb = .{ 15, 15, 25 } };
const success_color: Color = .{ .ansi = .green };
const warning_color: Color = .{ .ansi = .yellow };

// ---------------------------------------------------------------------------
// Application state
// ---------------------------------------------------------------------------

const total_list_items: usize = 200;

const DEFAULT_MESSAGE = "Welcome! Tab to navigate, Enter to activate.";

const App = struct {
    click_count: i32 = 0,
    message: []const u8 = "",
    message_color: Color = fg_color,
    message_buf: [256]u8 = undefined,

    name_buf: [128]u8 = [_]u8{0} ** 128,
    name_state: widgets.Line_Edit_State = undefined,

    search_buf: [128]u8 = [_]u8{0} ** 128,
    search_state: widgets.Line_Edit_State = undefined,

    selected_item: ?usize = null,

    details_open: bool = true,
    settings_open: bool = false,

    fn init(app: *App) void {
        app.message = DEFAULT_MESSAGE;
        app.name_state = .{ .buffer = &app.name_buf };
        app.search_state = .{ .buffer = &app.search_buf };
    }
};

fn set_message(app: *App, message: []const u8) void {
    app.message = message;
}

fn set_message_fmt(app: *App, comptime format: []const u8, args: anytype, fallback: []const u8) void {
    const msg = std.fmt.bufPrint(&app.message_buf, format, args) catch fallback;
    app.message = msg;
}

// ---------------------------------------------------------------------------
// Build with inline signals
// ---------------------------------------------------------------------------

fn build_ui(app: *App) !void {
    ui.push_color(fg_color);
    defer ui.pop_color();

    build_title_bar();
    try build_main_area(app);
    try build_status_bar(app);
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
    ui.push_color(bg_color);
    defer ui.pop_color();
    _ = ui.build_box(" Widget Demo — All Widgets", .{ .draw_text = true });
}

fn build_main_area(app: *App) !void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.pct(1, 0));
    _ = ui.push_parent_box("main###main_area", .{});
    defer ui.pop_parent();

    try build_left_column(app);
    try build_right_column(app);
}

fn build_left_column(app: *App) !void {
    ui.next_width(.pct(0.5, 0));
    ui.next_height(.pct(1, 1));
    _ = ui.push_parent_box("left_col###left", .{});
    defer ui.pop_parent();

    ui.spacer(.y, 1);

    try build_basic_widgets_panel(app);

    ui.spacer(.y, 1);

    try build_text_input_panel(app);

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.build_box("", .{});
}

fn build_basic_widgets_panel(app: *App) !void {
    ui.next_width(.pct(1, 0));
    ui.push_bg(panel_bg);
    defer ui.pop_bg();
    ui.push_border_color(muted_color);
    defer ui.pop_border_color();
    _ = widgets.panel_begin(" Basic Widgets ##basic_panel");
    defer widgets.panel_end();

    ui.spacer(.y, 1);

    ui.push_text_padding(1);
    defer ui.pop_text_padding();
    _ = widgets.label("This is a label widget.");

    ui.spacer(.y, 1);

    widgets.separator();

    ui.spacer(.y, 1);

    ui.push_text_padding(1);
    defer ui.pop_text_padding();
    ui.push_color(app.message_color);
    defer ui.pop_color();
    _ = widgets.label(app.message);

    ui.spacer(.y, 1);

    build_button_row(app);

    ui.spacer(.y, 1);
}

fn build_button_row(app: *App) void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 0));
    ui.next_height(.children(1));
    _ = ui.push_parent_box("btn_row###btn_row", .{});
    defer ui.pop_parent();

    ui.spacer(.x, 1);

    if (build_button("Greet##greet_btn", accent_color)) {
        if (app.name_state.len > 0) {
            set_message_fmt(app, "Hello, {s}!", .{app.name_buf[0..app.name_state.len]}, "Hello!");
            app.message_color = success_color;
        } else {
            set_message(app, "Hello, stranger!");
            app.message_color = success_color;
        }
    }

    ui.spacer(.x, 1);

    const click_label = ui.arena_print("Clicks: {d}##count_btn", .{app.click_count}) catch "Clicks";
    if (build_button(click_label, accent_color)) {
        app.click_count += 1;
        set_message(app, "Button clicked!");
        app.message_color = accent_color;
    }

    ui.spacer(.x, 1);

    if (build_button("Reset##reset_btn", warning_color)) {
        app.click_count = 0;
        set_message(app, "Counter reset.");
        app.message_color = warning_color;
    }

    ui.spacer(.x, 1);
}

fn build_button(label: []const u8, border_color: Color) bool {
    ui.push_bg(button_bg);
    defer ui.pop_bg();
    ui.push_border_color(border_color);
    defer ui.pop_border_color();
    return widgets.button(label).clicked();
}

fn build_text_input_panel(app: *App) !void {
    ui.next_width(.pct(1, 0));
    ui.push_bg(panel_bg);
    defer ui.pop_bg();
    ui.push_border_color(muted_color);
    defer ui.pop_border_color();
    _ = widgets.panel_begin(" Text Input ##input_panel");
    defer widgets.panel_end();

    ui.spacer(.y, 1);

    {
        ui.push_text_padding(1);
        defer ui.pop_text_padding();
        _ = widgets.label("Name:");
    }

    {
        ui.next_width(.pct(1, 0));
        ui.push_bg(input_bg);
        defer ui.pop_bg();
        ui.push_border_color(muted_color);
        defer ui.pop_border_color();
        _ = widgets.line_edit("name_field###name_edit", &app.name_state);
    }

    ui.spacer(.y, 1);

    {
        ui.push_text_padding(1);
        defer ui.pop_text_padding();
        _ = widgets.label("Search:");
    }

    {
        ui.next_width(.pct(1, 0));
        ui.push_bg(input_bg);
        defer ui.pop_bg();
        ui.push_border_color(muted_color);
        defer ui.pop_border_color();
        _ = widgets.line_edit("search_field###search_edit", &app.search_state);
    }

    ui.spacer(.y, 1);
}

fn build_right_column(app: *App) !void {
    ui.next_width(.pct(0.5, 0));
    ui.next_height(.pct(1, 1));
    _ = ui.push_parent_box("right_col###right", .{});
    defer ui.pop_parent();

    ui.spacer(.y, 1);

    build_collapsible_panel(app);

    ui.spacer(.y, 1);

    try build_scroll_list(app);
}

fn build_collapsible_panel(app: *App) void {
    ui.next_width(.pct(1, 0));
    ui.push_bg(panel_bg);
    defer ui.pop_bg();
    ui.push_border_color(muted_color);
    defer ui.pop_border_color();
    _ = widgets.panel_begin(" Collapsible Sections ##collapse_panel");
    defer widgets.panel_end();

    ui.spacer(.y, 1);

    ui.push_bg(.{ .rgb = .{ 40, 40, 55 } });
    defer ui.pop_bg();
    _ = widgets.collapsible_header("Details###details_sec", &app.details_open);

    if (app.details_open) {
        ui.push_text_padding(2);
        defer ui.pop_text_padding();
        _ = widgets.label("This section can be collapsed.");
        _ = widgets.label("Click the header or press Enter.");
        ui.spacer(.y, 1);
    }

    ui.push_bg(.{ .rgb = .{ 40, 40, 55 } });
    defer ui.pop_bg();
    _ = widgets.collapsible_header("Settings###settings_sec", &app.settings_open);

    if (app.settings_open) {
        ui.push_text_padding(2);
        defer ui.pop_text_padding();
        _ = widgets.label("Setting 1: enabled");
        _ = widgets.label("Setting 2: disabled");
        _ = widgets.label("Setting 3: auto");
        ui.spacer(.y, 1);
    }
}

fn build_scroll_list(app: *App) !void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.push_parent_box("scroll_area###scroll_wrap", .{});
    defer ui.pop_parent();

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 1));
    ui.next_bg(.{ .rgb = .{ 15, 15, 25 } });
    var view = widgets.scroll_list_begin(
        "item_list###scroll_list",
        total_list_items,
        1,
    );

    for (view.first_visible..view.first_visible + view.visible_count) |index| {
        const is_selected = if (app.selected_item) |s| s == index else false;
        const row_bg: Color = if (is_selected)
            .{ .rgb = .{ 50, 50, 90 } }
        else if (index % 2 == 0)
            .{ .rgb = .{ 20, 20, 32 } }
        else
            .{ .rgb = .{ 28, 28, 40 } };

        const item_str = try ui.arena_print(" Item {d}###list_item_{d}", .{ index, index });
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
            app.selected_item = index;
            set_message_fmt(app, "Selected item {d}", .{index}, "Selected item");
            app.message_color = accent_color;
        }
    }

    _ = widgets.scroll_list_end(&view);
    widgets.scrollbar(&view);
}

fn build_status_bar(app: *App) !void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    ui.next_bg(accent_color);
    _ = ui.push_parent_box("", .{ .draw_background = true });
    defer ui.pop_parent();

    const name_str = if (app.name_state.len > 0)
        app.name_buf[0..app.name_state.len]
    else
        "—";

    const status = try ui.arena_print(
        " Tab: focus | Enter: activate | q/Esc: quit | Name: {s} | Items: {d}",
        .{ name_str, total_list_items },
    );

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    ui.push_color(bg_color);
    defer ui.pop_color();
    _ = ui.build_box(status, .{ .draw_text = true });
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn is_quit(ev: term.InputEvent) bool {
    switch (ev) {
        .key => |key| {
            const is_escape = key.key == .escape;
            const is_q = key.codepoint == 'q' and !key.mods.ctrl and !key.mods.alt and interaction.get_focus_active_key() == null;
            const is_ctrl_c = key.codepoint == 'c' and key.mods.ctrl;

            return is_escape or is_q or is_ctrl_c;
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
    app.init();

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
        const timeout_ms: i32 = if (ui.is_animating()) 16 else 50;
        interaction.begin_frame();

        if (try t.poll_event(timeout_ms)) |ev| {
            if (ev == .resize) {
                // handled by check_resize
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
