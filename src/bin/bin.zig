const std = @import("std");
const base = @import("base");
const Arena = base.Arena;
const term = @import("term");
const ui = @import("ui");
const Color = ui.Color;
const interaction = ui.interaction;
const plaid = @import("plaid");

// ---------------------------------------------------------------------------
// Colors
// ---------------------------------------------------------------------------

const bg_color: Color = .{ .rgb = .{ 20, 20, 30 } };
const fg_color: Color = .{ .ansi = .white };
const accent_color: Color = .{ .ansi = .cyan };

// ---------------------------------------------------------------------------
// UI construction
// ---------------------------------------------------------------------------

fn build_ui(state: *plaid.State) !void {
    ui.push_color(fg_color);
    defer ui.pop_color();

    build_title_bar();
    ui.spacer(.y, 1);

    try plaid.build_page(state);

    // Fill remaining vertical space
    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.build_box("", .{});

    build_status_bar(state);
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
    _ = ui.build_box(" Groschen", .{ .draw_text = true });
}

fn build_status_bar(state: *const plaid.State) void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    ui.push_bg(accent_color);
    defer ui.pop_bg();
    _ = ui.push_parent_box("", .{ .draw_background = true });
    defer ui.pop_parent();

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    ui.push_color(plaid.status_color(state));
    defer ui.pop_color();
    _ = ui.build_box(plaid.status_text(state), .{ .draw_text = true });
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

    var plaid_arena = try Arena.init(.{});
    defer plaid_arena.deinit();

    var event_arena = try Arena.init(.{});
    defer event_arena.deinit();

    try ui.init_all();
    defer ui.deinit();

    var t = try term.init(&perm_arena);
    defer t.deinit();

    var state = plaid.init_state(&plaid_arena);
    defer plaid.deinit(&state);

    plaid.load_saved_state(&state);

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

        const timeout_ms: i32 = if (ui.is_animating() or plaid.is_busy(&state)) 16 else 50;
        interaction.begin_frame();

        if (try t.poll_event(timeout_ms)) |ev| {
            if (ev == .resize) {} else {
                if (is_quit(ev)) break;
                interaction.push_event(&event_arena, ev);
                while (try t.poll_event(0)) |more| {
                    if (more == .resize) break;
                    if (is_quit(more)) return;
                    interaction.push_event(&event_arena, more);
                }
            }
        }

        plaid.tick(&state);

        const root = try ui.begin_build(&t, dt);
        root.flags.draw_background = true;
        root.bg_color = bg_color;

        try build_ui(&state);

        ui.end_build();

        var grid = term.draw.Grid.from_term(&t);
        ui.render.render(&grid, root);
        try t.flush();
    }
}
