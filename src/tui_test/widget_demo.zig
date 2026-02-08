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
const input_bg: Color = .{ .rgb = .{ 15, 15, 25 } };
const success_color: Color = .{ .ansi = .green };
const warning_color: Color = .{ .ansi = .yellow };

// ---------------------------------------------------------------------------
// Application state
// ---------------------------------------------------------------------------

const total_list_items: usize = 200;

const App = struct {
    click_count: i32 = 0,
    message: []const u8 = "Welcome! Tab to navigate, Enter to activate.",
    message_color: Color = fg_color,

    name_buf: [128]u8 = [_]u8{0} ** 128,
    name_state: widgets.Line_Edit_State = undefined,

    search_buf: [128]u8 = [_]u8{0} ** 128,
    search_state: widgets.Line_Edit_State = undefined,

    scroll_state: widgets.Scroll_List_State = .{},
    selected_item: ?usize = null,

    details_open: bool = true,
    settings_open: bool = false,

    fn init(self: *App) void {
        self.name_state = .{ .buffer = &self.name_buf };
        self.search_state = .{ .buffer = &self.search_buf };
    }
};

// ---------------------------------------------------------------------------
// Build
// ---------------------------------------------------------------------------

const BuildResult = struct {
    greet_button: *Box,
    count_button: *Box,
    reset_button: *Box,
    name_input: *Box,
    search_input: *Box,
    scroll_view: widgets.Scroll_List_View,
    item_boxes: [128]*Box,
    item_indices: [128]usize,
    item_count: usize,
    details_header: *Box,
    settings_header: *Box,
};

fn build_ui(app: *App) !BuildResult {
    var result: BuildResult = undefined;
    result.item_count = 0;

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
        _ = ui.build_box(" Widget Demo — All Widgets", .{ .draw_text = true });

        ui.pop_parent();
    }

    // Main content — two columns
    {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 1));
        ui.next_height(.pct(1, 0));
        _ = ui.push_parent_box("main###main_area", .{});

        // Left column
        {
            ui.next_width(.pct(0.5, 0));
            ui.next_height(.pct(1, 1));
            _ = ui.push_parent_box("left_col###left", .{});

            ui.spacer(.y, 1);

            // Basic widgets panel
            {
                ui.next_width(.pct(1, 0));
                ui.next_bg(panel_bg);
                ui.next_border_color(muted_color);
                _ = widgets.panel_begin(" Basic Widgets ##basic_panel");

                ui.spacer(.y, 1);

                // Labels
                ui.next_text_padding(1);
                _ = widgets.label("This is a label widget.");

                ui.spacer(.y, 1);

                widgets.separator();

                ui.spacer(.y, 1);

                // Message display
                ui.next_text_padding(1);
                ui.next_color(app.message_color);
                _ = widgets.label(app.message);
                ui.next_color(fg_color);

                ui.spacer(.y, 1);

                // Button row
                {
                    ui.next_axis(.x);
                    ui.next_width(.pct(1, 0));
                    ui.next_height(.children(1));
                    _ = ui.push_parent_box("btn_row###btn_row", .{});

                    ui.spacer(.x, 1);

                    ui.next_bg(button_bg);
                    ui.next_border_color(accent_color);
                    result.greet_button = widgets.button("Greet##greet_btn");

                    ui.spacer(.x, 1);

                    ui.next_bg(button_bg);
                    ui.next_border_color(accent_color);
                    result.count_button = widgets.button(
                        try ui.arena_print("Clicks: {d}##count_btn", .{app.click_count}),
                    );

                    ui.spacer(.x, 1);

                    ui.next_bg(button_bg);
                    ui.next_border_color(warning_color);
                    result.reset_button = widgets.button("Reset##reset_btn");

                    ui.spacer(.x, 1);

                    ui.pop_parent();
                }

                ui.spacer(.y, 1);

                widgets.panel_end();
            }

            ui.spacer(.y, 1);

            // Text input panel
            {
                ui.next_width(.pct(1, 0));
                ui.next_bg(panel_bg);
                ui.next_border_color(muted_color);
                _ = widgets.panel_begin(" Text Input ##input_panel");

                ui.spacer(.y, 1);

                ui.next_text_padding(1);
                _ = widgets.label("Name:");

                ui.next_width(.pct(1, 0));
                ui.next_bg(input_bg);
                ui.next_border_color(muted_color);
                result.name_input = widgets.line_edit("name_field###name_edit", &app.name_state);

                ui.spacer(.y, 1);

                ui.next_text_padding(1);
                _ = widgets.label("Search:");

                ui.next_width(.pct(1, 0));
                ui.next_bg(input_bg);
                ui.next_border_color(muted_color);
                result.search_input = widgets.line_edit("search_field###search_edit", &app.search_state);

                ui.spacer(.y, 1);

                widgets.panel_end();
            }

            // Filler
            ui.next_width(.pct(1, 0));
            ui.next_height(.pct(1, 0));
            _ = ui.build_box("", .{});

            ui.pop_parent();
        }

        // Right column
        {
            ui.next_width(.pct(0.5, 0));
            ui.next_height(.pct(1, 1));
            _ = ui.push_parent_box("right_col###right", .{});

            ui.spacer(.y, 1);

            // Collapsible sections
            {
                ui.next_width(.pct(1, 0));
                ui.next_bg(panel_bg);
                ui.next_border_color(muted_color);
                _ = widgets.panel_begin(" Collapsible Sections ##collapse_panel");

                ui.spacer(.y, 1);

                // Details section
                ui.next_bg(.{ .rgb = .{ 40, 40, 55 } });
                result.details_header = widgets.collapsible_header("Details###details_sec", &app.details_open);

                if (app.details_open) {
                    ui.next_text_padding(2);
                    _ = widgets.label("This section can be collapsed.");
                    ui.next_text_padding(2);
                    _ = widgets.label("Click the header or press Enter.");
                    ui.spacer(.y, 1);
                }

                // Settings section
                ui.next_bg(.{ .rgb = .{ 40, 40, 55 } });
                result.settings_header = widgets.collapsible_header("Settings###settings_sec", &app.settings_open);

                if (app.settings_open) {
                    ui.next_text_padding(2);
                    _ = widgets.label("Setting 1: enabled");
                    ui.next_text_padding(2);
                    _ = widgets.label("Setting 2: disabled");
                    ui.next_text_padding(2);
                    _ = widgets.label("Setting 3: auto");
                    ui.spacer(.y, 1);
                }

                widgets.panel_end();
            }

            ui.spacer(.y, 1);

            // Scroll list
            {
                ui.next_axis(.x);
                ui.next_width(.pct(1, 0));
                ui.next_height(.pct(1, 0));
                _ = ui.push_parent_box("scroll_area###scroll_wrap", .{});

                ui.next_width(.pct(1, 0));
                ui.next_height(.pct(1, 1));
                ui.next_bg(.{ .rgb = .{ 15, 15, 25 } });
                result.scroll_view = widgets.scroll_list_begin(
                    "item_list###scroll_list",
                    total_list_items,
                    1,
                    &app.scroll_state,
                );

                const view = &result.scroll_view;
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
                    ui.next_bg(row_bg);
                    ui.next_color(if (is_selected) accent_color else fg_color);
                    const item_box = ui.build_box(item_str, .{
                        .clickable = true,
                        .draw_background = true,
                        .draw_text = true,
                    });

                    if (result.item_count < result.item_boxes.len) {
                        result.item_boxes[result.item_count] = item_box;
                        result.item_indices[result.item_count] = index;
                        result.item_count += 1;
                    }
                }

                widgets.scroll_list_end();

                widgets.scrollbar(&result.scroll_view);

                ui.pop_parent();
            }

            ui.pop_parent();
        }

        ui.pop_parent();
    }

    _ = ui.pop_color();

    // Status bar
    {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 1));
        ui.next_height(.cells(1, 1));
        ui.next_bg(accent_color);
        _ = ui.push_parent_box("", .{ .draw_background = true });

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
        ui.next_color(bg_color);
        _ = ui.build_box(status, .{ .draw_text = true });

        ui.pop_parent();
    }

    return result;
}

// ---------------------------------------------------------------------------
// Signal handling
// ---------------------------------------------------------------------------

fn handle_signals(app: *App, br: *const BuildResult) void {
    // Buttons
    const greet_sig = widgets.button_signal(br.greet_button);
    if (greet_sig.flags.left_clicked or greet_sig.flags.keyboard_pressed) {
        if (app.name_state.len > 0) {
            app.message = ui.arena_print("Hello, {s}!", .{app.name_buf[0..app.name_state.len]}) catch "Hello!";
            app.message_color = success_color;
        } else {
            app.message = "Hello, stranger!";
            app.message_color = success_color;
        }
    }

    const count_sig = widgets.button_signal(br.count_button);
    if (count_sig.flags.left_clicked or count_sig.flags.keyboard_pressed) {
        app.click_count += 1;
        app.message = "Button clicked!";
        app.message_color = accent_color;
    }

    const reset_sig = widgets.button_signal(br.reset_button);
    if (reset_sig.flags.left_clicked or reset_sig.flags.keyboard_pressed) {
        app.click_count = 0;
        app.message = "Counter reset.";
        app.message_color = warning_color;
    }

    // Text inputs
    _ = widgets.line_edit_handle_events(&app.name_state, br.name_input);
    _ = widgets.line_edit_handle_events(&app.search_state, br.search_input);

    // Collapsible headers
    _ = widgets.collapsible_header_signal(br.details_header, &app.details_open);
    _ = widgets.collapsible_header_signal(br.settings_header, &app.settings_open);

    // Scroll list
    _ = widgets.scroll_list_signal(&br.scroll_view);

    // List item clicks
    for (0..br.item_count) |index| {
        const sig = interaction.signal_from_box(br.item_boxes[index]);
        if (sig.flags.left_clicked) {
            app.selected_item = br.item_indices[index];
            app.message = ui.arena_print("Selected item {d}", .{br.item_indices[index]}) catch "Selected item";
            app.message_color = accent_color;
        }
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn is_quit(ev: term.InputEvent) bool {
    switch (ev) {
        .key => |ke| {
            if (ke.key == .escape) return true;
            if (ke.key == .codepoint and ke.codepoint == 'q' and !ke.mods.ctrl and !ke.mods.alt) {
                // Don't quit on 'q' if a text input is focused
                const focus_key = interaction.get_focus_active_key();
                if (!focus_key.is_zero()) return false;
            }
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

test {
    std.testing.refAllDecls(@This());
}
