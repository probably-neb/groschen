const std = @import("std");
const term = @import("term.zig");

const Cell = term.Cell;
const Color = term.Color;

// ---------------------------------------------------------------------------
// Grid — plain data view over a cell buffer
// ---------------------------------------------------------------------------

pub const Grid = struct {
    cells: []Cell,
    cols: u16,
    rows: u16,

    pub fn from_term(t: *term.Term) Grid {
        return .{ .cells = t.back, .cols = t.cols, .rows = t.rows };
    }
};

// ---------------------------------------------------------------------------
// Grid primitives
// ---------------------------------------------------------------------------

pub fn cell_at(grid: *Grid, col: u16, row: u16) ?*Cell {
    if (col >= grid.cols or row >= grid.rows) return null;
    return &grid.cells[@as(usize, row) * @as(usize, grid.cols) + @as(usize, col)];
}

pub fn write_cell(grid: *Grid, col: u16, row: u16, cell: Cell) void {
    if (cell_at(grid, col, row)) |c| {
        c.* = cell;
    }
}

pub fn fill_rect(grid: *Grid, col: u16, row: u16, w: u16, h: u16, cell: Cell) void {
    const x_end = @min(@as(u32, col) + w, grid.cols);
    const y_end = @min(@as(u32, row) + h, grid.rows);
    var r: u32 = row;
    while (r < y_end) : (r += 1) {
        var c: u32 = col;
        while (c < x_end) : (c += 1) {
            grid.cells[r * @as(u32, grid.cols) + c] = cell;
        }
    }
}

// ---------------------------------------------------------------------------
// Color effects
// ---------------------------------------------------------------------------

pub fn brighten_color(c: Color, amount: f32) Color {
    switch (c) {
        .rgb => |v| {
            return .{ .rgb = .{
                add_clamp_u8(v[0], amount),
                add_clamp_u8(v[1], amount),
                add_clamp_u8(v[2], amount),
            } };
        },
        .ansi => |a| {
            const idx = @intFromEnum(a);
            if (idx < 8 and amount > 0.05) {
                return .{ .ansi = @enumFromInt(idx + 8) };
            }
            return c;
        },
        .default => return c,
    }
}

fn add_clamp_u8(val: u8, amount: f32) u8 {
    const delta: f32 = amount * 80;
    const result = @as(f32, @floatFromInt(val)) + delta;
    if (result >= 255) return 255;
    if (result <= 0) return 0;
    return @intFromFloat(result);
}

// ---------------------------------------------------------------------------
// Text width measurement
// ---------------------------------------------------------------------------

pub fn text_display_width(text: []const u8) u16 {
    var w: u16 = 0;
    var i: usize = 0;
    while (i < text.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch {
            i += 1;
            continue;
        };
        if (i + cp_len > text.len) break;
        const cp = std.unicode.utf8Decode(text[i..][0..cp_len]) catch {
            i += cp_len;
            continue;
        };
        w += codepoint_width(cp);
        i += cp_len;
    }
    return w;
}

pub const codepoint_width = term.codepoint_width;

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

pub fn grid_to_string(grid: *const Grid, buf: []u8) []const u8 {
    var pos: usize = 0;
    var row: u16 = 0;
    while (row < grid.rows) : (row += 1) {
        if (row > 0) {
            if (pos < buf.len) {
                buf[pos] = '\n';
                pos += 1;
            }
        }
        var col: u16 = 0;
        while (col < grid.cols) : (col += 1) {
            const idx = @as(usize, row) * @as(usize, grid.cols) + @as(usize, col);
            const cp = grid.cells[idx].codepoint;
            if (cp == 0) {
                continue;
            }
            const len = std.unicode.utf8CodepointSequenceLength(cp) catch continue;
            if (pos + len > buf.len) return buf[0..pos];
            _ = std.unicode.utf8Encode(cp, buf[pos..][0..len]) catch continue;
            pos += len;
        }
    }
    return buf[0..pos];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

fn make_grid(cells: []Cell, cols: u16, rows: u16) Grid {
    @memset(cells, Cell{});
    return .{ .cells = cells, .cols = cols, .rows = rows };
}

test "cell_at returns null out of bounds" {
    var cells: [4]Cell = undefined;
    var grid = make_grid(&cells, 2, 2);

    try testing.expect(cell_at(&grid, 0, 0) != null);
    try testing.expect(cell_at(&grid, 1, 1) != null);
    try testing.expect(cell_at(&grid, 2, 0) == null);
    try testing.expect(cell_at(&grid, 0, 2) == null);
}

test "write_cell writes at position" {
    var cells: [6]Cell = undefined;
    var grid = make_grid(&cells, 3, 2);

    write_cell(&grid, 1, 0, .{ .codepoint = 'A', .fg = .{ .ansi = .red } });
    try testing.expectEqual(@as(u21, 'A'), cells[1].codepoint);
    try testing.expect(cells[1].fg.eql(.{ .ansi = .red }));
    try testing.expectEqual(@as(u21, ' '), cells[0].codepoint);
}

test "write_cell out of bounds is no-op" {
    var cells: [4]Cell = undefined;
    var grid = make_grid(&cells, 2, 2);

    write_cell(&grid, 5, 5, .{ .codepoint = 'X' });
    for (&cells) |*c| {
        try testing.expectEqual(@as(u21, ' '), c.codepoint);
    }
}

test "fill_rect fills region" {
    var cells: [5 * 3]Cell = undefined;
    var grid = make_grid(&cells, 5, 3);

    fill_rect(&grid, 1, 0, 3, 2, .{ .bg = .{ .ansi = .blue } });

    try testing.expect(cells[0].bg.eql(.default));
    try testing.expect(cells[1].bg.eql(.{ .ansi = .blue }));
    try testing.expect(cells[3].bg.eql(.{ .ansi = .blue }));
    try testing.expect(cells[4].bg.eql(.default));
    try testing.expect(cells[6].bg.eql(.{ .ansi = .blue }));
    try testing.expect(cells[11].bg.eql(.default));
}

test "fill_rect clamps to grid bounds" {
    var cells: [4]Cell = undefined;
    var grid = make_grid(&cells, 2, 2);

    fill_rect(&grid, 1, 1, 100, 100, .{ .codepoint = 'X' });
    try testing.expectEqual(@as(u21, ' '), cells[0].codepoint);
    try testing.expectEqual(@as(u21, ' '), cells[1].codepoint);
    try testing.expectEqual(@as(u21, ' '), cells[2].codepoint);
    try testing.expectEqual(@as(u21, 'X'), cells[3].codepoint);
}

test "grid_to_string basic" {
    var cells: [5 * 2]Cell = undefined;
    var grid = make_grid(&cells, 5, 2);

    cells[0].codepoint = 'H';
    cells[1].codepoint = 'i';

    cells[5].codepoint = 'G';
    cells[6].codepoint = 'o';

    var buf: [256]u8 = undefined;
    const result = grid_to_string(&grid, &buf);

    try testing.expectEqualStrings("Hi   \nGo   ", result);
}

test "text_display_width ascii" {
    try testing.expectEqual(@as(u16, 5), text_display_width("Hello"));
    try testing.expectEqual(@as(u16, 0), text_display_width(""));
    try testing.expectEqual(@as(u16, 1), text_display_width("X"));
}

test "codepoint_width basics" {
    try testing.expectEqual(@as(u16, 1), codepoint_width('A'));
    try testing.expectEqual(@as(u16, 0), codepoint_width(0));
    try testing.expectEqual(@as(u16, 0), codepoint_width(0x01));
    try testing.expectEqual(@as(u16, 2), codepoint_width(0x4E00));
}

test "brighten_color rgb" {
    const c: Color = .{ .rgb = .{ 100, 100, 100 } };
    const bright = brighten_color(c, 1.0);
    switch (bright) {
        .rgb => |v| {
            try testing.expect(v[0] > 100);
            try testing.expect(v[1] > 100);
            try testing.expect(v[2] > 100);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "brighten_color ansi promotes dark to bright" {
    const c: Color = .{ .ansi = .blue };
    const bright = brighten_color(c, 0.2);
    switch (bright) {
        .ansi => |a| try testing.expectEqual(term.Ansi.bright_blue, a),
        else => return error.TestUnexpectedResult,
    }
}

test "brighten_color default unchanged" {
    const c: Color = .default;
    const bright = brighten_color(c, 0.5);
    try testing.expect(bright.eql(.default));
}

test "brighten_color rgb clamps to 255" {
    const c: Color = .{ .rgb = .{ 250, 250, 250 } };
    const bright = brighten_color(c, 1.0);
    switch (bright) {
        .rgb => |v| {
            try testing.expectEqual(@as(u8, 255), v[0]);
            try testing.expectEqual(@as(u8, 255), v[1]);
            try testing.expectEqual(@as(u8, 255), v[2]);
        },
        else => return error.TestUnexpectedResult,
    }
}
