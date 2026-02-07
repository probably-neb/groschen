const base = @import("base");
const tui = @import("tui");
const Term = tui.term.Term;
const Color = tui.term.Color;

pub fn run() !void {
    var arena = try base.Arena.init(.{});
    defer arena.deinit();

    var t = try Term.init(&arena);
    defer t.deinit();

    var cursor_col: u16 = 0;
    var cursor_row: u16 = 0;

    while (true) {
        _ = try t.check_resize();
        t.clear();

        for (0..t.rows) |r| {
            const row: u16 = @intCast(r);
            for (0..t.cols) |cl| {
                const col: u16 = @intCast(cl);
                const cell = t.cell_at(col, row) orelse continue;
                if (col == cursor_col and row == cursor_row) {
                    cell.* = .{
                        .codepoint = ' ',
                        .bg = .{ .rgb = .{ 255, 255, 0 } },
                        .attrs = .{ .reverse = true },
                    };
                } else {
                    const even = (col + row) % 2 == 0;
                    cell.bg = .{ .ansi = if (even) .blue else .red };
                }
            }
        }

        const status = "Arrow keys: move | q/Ctrl-C: quit";
        const status_row = t.rows -| 1;
        t.fill_rect(0, status_row, t.cols, 1, .{ .bg = .{ .ansi = .black } });
        _ = t.write_text(1, status_row, t.cols -| 2, status, .{ .ansi = .bright_white }, .{ .ansi = .black }, .{ .bold = true });

        try t.flush();

        const event = try t.poll_event(100) orelse continue;
        switch (event) {
            .key => |ke| {
                if (ke.key == .codepoint and ke.codepoint == 'q') return;
                if (ke.key == .codepoint and ke.codepoint == 'c' and ke.mods.ctrl) return;
                switch (ke.key) {
                    .up => cursor_row -|= 1,
                    .down => cursor_row = @min(cursor_row + 1, t.rows -| 1),
                    .left => cursor_col -|= 1,
                    .right => cursor_col = @min(cursor_col + 1, t.cols -| 1),
                    else => {},
                }
            },
            .resize => {
                cursor_col = @min(cursor_col, t.cols -| 1);
                cursor_row = @min(cursor_row, t.rows -| 1);
            },
            .mouse => {},
        }
    }
}
