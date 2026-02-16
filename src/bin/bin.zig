const std = @import("std");
const base = @import("base");
const Arena = base.Arena;
const term = @import("term");
const ui = @import("ui");
const draw = term.draw;
const Grid = draw.Grid;
const interaction = ui.interaction;
const dashboard = @import("dashboard.zig");

// ---------------------------------------------------------------------------
// Grid dump — writes the rendered grid as an .ansi file for tuimg
// ---------------------------------------------------------------------------

fn dump_grid(grid: *const Grid, path: []const u8) !void {
    const scratch = Arena.get_scratch(&.{});
    defer scratch.release();

    const bytes = try term.write_grid_ansi(scratch.arena, grid);
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(bytes);
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

    const args = std.process.argsAlloc(perm_arena.allocator()) catch &.{};
    var dump_mode = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--dump")) dump_mode = true;
    }

    if (dump_mode) {
        try run_dump(&perm_arena);
    } else {
        try run_interactive(&perm_arena);
    }
}

fn run_dump(perm_arena: *Arena) !void {
    const cols: u16 = 80;
    const rows: u16 = 40;
    const total = @as(usize, cols) * @as(usize, rows);
    const cells = try perm_arena.alloc(term.Cell, total);
    @memset(cells, .{});

    try ui.init_all();
    defer ui.deinit();

    interaction.begin_frame();

    const root = ui.begin_build_raw(cols, rows, 1.0 / 60.0);
    root.flags.draw_background = true;
    root.bg_color = dashboard.bg_color;

    try dashboard.build_ui();

    ui.end_build();

    var grid = Grid{ .cells = cells, .cols = cols, .rows = rows };
    ui.render.render(&grid, root);

    try dump_grid(&grid, "dump.ansi");

    const stderr: std.fs.File = .{ .handle = std.posix.STDERR_FILENO };
    stderr.writeAll("Wrote dump.ansi (80x40). Render with:\n  tuimg -o dump.png --cols 80 --rows 40 dump.ansi\n") catch {};
}

fn run_interactive(perm_arena: *Arena) !void {
    var event_arena = try Arena.init(.{});
    defer event_arena.deinit();

    try ui.init_all();
    defer ui.deinit();

    var t = try term.init(perm_arena);
    defer t.deinit();

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

        interaction.begin_frame();

        if (try t.poll_event(50)) |ev| {
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

        const root = try ui.begin_build(&t, dt);
        root.flags.draw_background = true;
        root.bg_color = dashboard.bg_color;

        try dashboard.build_ui();

        ui.end_build();

        var grid = Grid.from_term(&t);
        ui.render.render(&grid, root);
        try t.flush();
    }
}
