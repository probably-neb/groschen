const std = @import("std");
const ui = @import("ui.zig");
const term = @import("term");
const draw = term.draw;
const Grid = draw.Grid;
const Cell = term.Cell;
const Color = term.Color;
const Attrs = term.Attrs;

const Box = ui.Box;
const BoxFlags = ui.BoxFlags;
const Rect = ui.Rect;

const max_clip_depth = 64;
const max_floating = 64;

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

pub fn render(grid: *Grid, root: *Box) void {
    var ctx = RenderCtx{
        .grid = grid,
    };
    ctx.clip_stack[0] = .{ .col = 0, .row = 0, .w = grid.cols, .h = grid.rows };
    ctx.clip_len = 1;

    render_subtree(&ctx, root);

    const saved_floating = ctx.floating_len;
    const floating_copy = ctx.floating;
    ctx.floating_len = 0;
    for (floating_copy[0..saved_floating]) |fb| {
        ctx.clip_len = 1;
        ctx.clip_stack[0] = .{ .col = 0, .row = 0, .w = grid.cols, .h = grid.rows };
        render_subtree(&ctx, fb);
    }
}

// ---------------------------------------------------------------------------
// Render context
// ---------------------------------------------------------------------------

const RenderCtx = struct {
    grid: *Grid,
    clip_stack: [max_clip_depth]Rect = undefined,
    clip_len: u8 = 0,
    floating: [max_floating]*Box = undefined,
    floating_len: u8 = 0,
};

// ---------------------------------------------------------------------------
// Tree walk — pre-order (parent bg first, children overlay)
// ---------------------------------------------------------------------------

fn render_subtree(ctx: *RenderCtx, box: *Box) void {
    const r = box.rect;
    if (r.w == 0 or r.h == 0) return;

    if ((box.flags.floating_x or box.flags.floating_y) and ctx.clip_len > 0) {
        const top = ctx.clip_stack[ctx.clip_len - 1];
        const is_top_level = ctx.clip_len == 1 and top.col == 0 and top.row == 0 and
            top.w == ctx.grid.cols and top.h == ctx.grid.rows;
        if (!is_top_level) {
            if (ctx.floating_len < max_floating) {
                ctx.floating[ctx.floating_len] = box;
                ctx.floating_len += 1;
            }
            return;
        }
    }

    const clip = current_clip(ctx);
    const is_hot = box.hot_t > 0 and box.flags.draw_hot_effects;
    const is_active = box.active_t > 0 and box.flags.draw_active_effects;

    if (box.flags.draw_background) render_background(ctx, box, clip, is_hot, is_active);
    if (box.flags.draw_border) render_border(ctx, box, clip, is_hot);
    if (box.flags.draw_text and box.display_string.len > 0) render_text(ctx, box, clip, is_hot, is_active);

    const pushed_clip = box.flags.clip;
    if (pushed_clip) push_clip(ctx, r);

    var child = box.first;
    while (child) |c| : (child = c.next) {
        render_subtree(ctx, c);
    }

    if (pushed_clip) pop_clip(ctx);
}

// ---------------------------------------------------------------------------
// Clip stack
// ---------------------------------------------------------------------------

fn current_clip(ctx: *const RenderCtx) Rect {
    if (ctx.clip_len == 0) return .{};
    return ctx.clip_stack[ctx.clip_len - 1];
}

fn push_clip(ctx: *RenderCtx, r: Rect) void {
    if (ctx.clip_len >= max_clip_depth) return;
    ctx.clip_stack[ctx.clip_len] = Rect.intersect(current_clip(ctx), r);
    ctx.clip_len += 1;
}

fn pop_clip(ctx: *RenderCtx) void {
    if (ctx.clip_len > 1) ctx.clip_len -= 1;
}

// ---------------------------------------------------------------------------
// Background fill
// ---------------------------------------------------------------------------

fn render_background(ctx: *RenderCtx, box: *const Box, clip: Rect, is_hot: bool, is_active: bool) void {
    var bg = box.bg_color;
    if (is_active) {
        bg = draw.brighten_color(bg, box.active_t * 0.3);
    } else if (is_hot) {
        bg = draw.brighten_color(bg, box.hot_t * 0.15);
    }
    clipped_fill(ctx.grid, box.rect, clip, .{ .bg = bg });
}

// ---------------------------------------------------------------------------
// Border rendering
// ---------------------------------------------------------------------------

fn render_border(ctx: *RenderCtx, box: *const Box, clip: Rect, is_hot: bool) void {
    const rect = box.rect;
    const flags = box.flags;
    const focus = box.focus_hot_t > 0.5;

    var border_color = box.border_color;
    if (is_hot) border_color = draw.brighten_color(border_color, 0.2);

    const attrs: Attrs = if (focus) .{ .bold = true } else .{};

    const left = rect.col;
    const top = rect.row;
    const right = rect.col +| rect.w -| 1;
    const bottom = rect.row +| rect.h -| 1;

    if (flags.draw_side_top) {
        var x = left;
        while (x <= right) : (x +|= 1) {
            const cp: u21 = if (x == left and flags.draw_side_left)
                (if (focus) '╔' else '┌')
            else if (x == right and flags.draw_side_right)
                (if (focus) '╗' else '┐')
            else
                (if (focus) '═' else '─');
            clipped_write(ctx.grid, x, top, clip, .{ .codepoint = cp, .fg = border_color, .attrs = attrs });
        }
    }

    if (flags.draw_side_bottom and rect.h > 1) {
        var x = left;
        while (x <= right) : (x +|= 1) {
            const cp: u21 = if (x == left and flags.draw_side_left)
                (if (focus) '╚' else '└')
            else if (x == right and flags.draw_side_right)
                (if (focus) '╝' else '┘')
            else
                (if (focus) '═' else '─');
            clipped_write(ctx.grid, x, bottom, clip, .{ .codepoint = cp, .fg = border_color, .attrs = attrs });
        }
    }

    if (flags.draw_side_left and rect.h > 1) {
        const y_start = top + @as(u16, if (flags.draw_side_top) 1 else 0);
        const y_end = if (flags.draw_side_bottom) bottom else bottom + 1;
        var y = y_start;
        while (y < y_end) : (y += 1) {
            clipped_write(ctx.grid, left, y, clip, .{
                .codepoint = if (focus) '║' else '│',
                .fg = border_color,
                .attrs = attrs,
            });
        }
    }

    if (flags.draw_side_right and rect.h > 1) {
        const y_start = top + @as(u16, if (flags.draw_side_top) 1 else 0);
        const y_end = if (flags.draw_side_bottom) bottom else bottom + 1;
        var y = y_start;
        while (y < y_end) : (y += 1) {
            clipped_write(ctx.grid, right, y, clip, .{
                .codepoint = if (focus) '║' else '│',
                .fg = border_color,
                .attrs = attrs,
            });
        }
    }
}

// ---------------------------------------------------------------------------
// Text rendering
// ---------------------------------------------------------------------------

fn render_text(ctx: *RenderCtx, box: *const Box, clip: Rect, is_hot: bool, is_active: bool) void {
    const rect = box.rect;
    const flags = box.flags;
    const left_inset: u16 = if (flags.draw_border and flags.draw_side_left) 1 else 0;
    const right_inset: u16 = if (flags.draw_border and flags.draw_side_right) 1 else 0;
    const top_inset: u16 = if (flags.draw_border and flags.draw_side_top) 1 else 0;
    const bot_inset: u16 = if (flags.draw_border and flags.draw_side_bottom) 1 else 0;

    const inner_width = rect.w -| left_inset -| right_inset -| (box.text_padding *| 2);
    const inner_height = rect.h -| top_inset -| bot_inset;
    if (inner_width == 0 or inner_height == 0) return;

    const text_row = rect.row +| top_inset +| (inner_height -| 1) / 2;
    const inner_left = rect.col +| left_inset +| box.text_padding;

    const text = box.display_string;
    const text_width = draw.text_display_width(text);

    const start_col: u16 = switch (box.text_align) {
        .left => inner_left,
        .center => inner_left +| (inner_width -| @as(u16, @intCast(@min(text_width, inner_width)))) / 2,
        .right => inner_left +| inner_width -| @as(u16, @intCast(@min(text_width, inner_width))),
    };

    const fg = box.fg_color;
    var bg: Color = if (flags.draw_background) box.bg_color else .default;
    var attrs: Attrs = .{};

    if (is_active) {
        bg = draw.brighten_color(bg, box.active_t * 0.3);
        attrs.bold = true;
    } else if (is_hot) {
        bg = draw.brighten_color(bg, box.hot_t * 0.15);
        attrs.bold = true;
    }
    if (box.focus_hot_t > 0.5) attrs.bold = true;

    const needs_truncation = text_width > inner_width;
    const ellipsis_w: u16 = if (needs_truncation) 1 else 0;
    const draw_limit: u16 = inner_width -| ellipsis_w;

    var col = start_col;
    var text_index: usize = 0;
    var drawn_width: u16 = 0;
    while (text_index < text.len and drawn_width < draw_limit) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[text_index]) catch {
            text_index += 1;
            continue;
        };
        if (text_index + cp_len > text.len) break;
        const cp = std.unicode.utf8Decode(text[text_index..][0..cp_len]) catch {
            text_index += cp_len;
            continue;
        };
        const codepoint_width = draw.codepoint_width(cp);
        if (codepoint_width == 0) {
            text_index += cp_len;
            continue;
        }
        if (drawn_width + codepoint_width > draw_limit) break;

        clipped_write(ctx.grid, col, text_row, clip, .{
            .codepoint = cp,
            .fg = fg,
            .bg = bg,
            .attrs = attrs,
        });
        if (codepoint_width == 2) {
            clipped_write(ctx.grid, col +| 1, text_row, clip, .{
                .codepoint = 0,
                .fg = fg,
                .bg = bg,
                .attrs = attrs,
            });
        }
        col +|= codepoint_width;
        drawn_width += codepoint_width;
        text_index += cp_len;
    }

    if (needs_truncation) {
        clipped_write(ctx.grid, col, text_row, clip, .{
            .codepoint = 0x2026, // …
            .fg = fg,
            .bg = bg,
            .attrs = attrs,
        });
    }
}

// ---------------------------------------------------------------------------
// Clipped grid operations
// ---------------------------------------------------------------------------

fn clipped_write(grid: *Grid, col: u16, row: u16, clip: Rect, cell: Cell) void {
    if (!clip.contains(col, row)) return;
    draw.write_cell(grid, col, row, cell);
}

fn clipped_fill(grid: *Grid, rect: Rect, clip: Rect, cell: Cell) void {
    const vis = Rect.intersect(rect, clip);
    if (vis.w == 0 or vis.h == 0) return;
    draw.fill_rect(grid, vis.col, vis.row, vis.w, vis.h, cell);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

fn make_grid(cells: []Cell, cols: u16, rows: u16) Grid {
    @memset(cells, Cell{});
    return .{ .cells = cells, .cols = cols, .rows = rows };
}

fn make_test_box() Box {
    return .{};
}

fn link(parent: *Box, child: *Box) void {
    ui.push_child(parent, child);
}

test "background fills rect" {
    var cells: [5 * 3]Cell = undefined;
    var grid = make_grid(&cells, 5, 3);

    var root = make_test_box();
    root.rect = .{ .col = 1, .row = 0, .w = 3, .h = 2 };
    root.flags.draw_background = true;
    root.bg_color = .{ .ansi = .blue };

    render(&grid, &root);

    try testing.expect(cells[0].bg.eql(.default));
    try testing.expect(cells[1].bg.eql(.{ .ansi = .blue }));
    try testing.expect(cells[3].bg.eql(.{ .ansi = .blue }));
    try testing.expect(cells[4].bg.eql(.default));
    try testing.expect(cells[6].bg.eql(.{ .ansi = .blue }));
    try testing.expect(cells[11].bg.eql(.default));
}

test "border renders box-drawing characters" {
    var cells: [7 * 4]Cell = undefined;
    var grid = make_grid(&cells, 7, 4);

    var root = make_test_box();
    root.rect = .{ .col = 0, .row = 0, .w = 7, .h = 4 };
    root.flags = BoxFlags.with_border(.{ .draw_border = true });
    root.border_color = .{ .ansi = .white };

    render(&grid, &root);

    try testing.expectEqual(@as(u21, '┌'), cells[0].codepoint);
    try testing.expectEqual(@as(u21, '┐'), cells[6].codepoint);
    try testing.expectEqual(@as(u21, '└'), cells[7 * 3].codepoint);
    try testing.expectEqual(@as(u21, '┘'), cells[7 * 3 + 6].codepoint);
    try testing.expectEqual(@as(u21, '─'), cells[1].codepoint);
    try testing.expectEqual(@as(u21, '─'), cells[5].codepoint);
    try testing.expectEqual(@as(u21, '│'), cells[7 * 1].codepoint);
    try testing.expectEqual(@as(u21, '│'), cells[7 * 2].codepoint);
    try testing.expectEqual(@as(u21, '│'), cells[7 * 1 + 6].codepoint);
    try testing.expectEqual(@as(u21, ' '), cells[7 * 1 + 3].codepoint);
}

test "text renders left-aligned" {
    var cells: [20 * 1]Cell = undefined;
    var grid = make_grid(&cells, 20, 1);

    var root = make_test_box();
    root.rect = .{ .col = 0, .row = 0, .w = 20, .h = 1 };
    root.flags.draw_text = true;
    root.display_string = "Hello";
    root.fg_color = .{ .ansi = .white };
    root.text_align = .left;

    render(&grid, &root);

    try testing.expectEqual(@as(u21, 'H'), cells[0].codepoint);
    try testing.expectEqual(@as(u21, 'e'), cells[1].codepoint);
    try testing.expectEqual(@as(u21, 'l'), cells[2].codepoint);
    try testing.expectEqual(@as(u21, 'l'), cells[3].codepoint);
    try testing.expectEqual(@as(u21, 'o'), cells[4].codepoint);
    try testing.expectEqual(@as(u21, ' '), cells[5].codepoint);
}

test "text truncates with ellipsis" {
    var cells: [5 * 1]Cell = undefined;
    var grid = make_grid(&cells, 5, 1);

    var root = make_test_box();
    root.rect = .{ .col = 0, .row = 0, .w = 5, .h = 1 };
    root.flags.draw_text = true;
    root.display_string = "Hello World";
    root.fg_color = .{ .ansi = .white };

    render(&grid, &root);

    try testing.expectEqual(@as(u21, 'H'), cells[0].codepoint);
    try testing.expectEqual(@as(u21, 'e'), cells[1].codepoint);
    try testing.expectEqual(@as(u21, 'l'), cells[2].codepoint);
    try testing.expectEqual(@as(u21, 'l'), cells[3].codepoint);
    try testing.expectEqual(@as(u21, 0x2026), cells[4].codepoint);
}

test "text center alignment" {
    var cells: [10 * 1]Cell = undefined;
    var grid = make_grid(&cells, 10, 1);

    var root = make_test_box();
    root.rect = .{ .col = 0, .row = 0, .w = 10, .h = 1 };
    root.flags.draw_text = true;
    root.display_string = "Hi";
    root.fg_color = .{ .ansi = .white };
    root.text_align = .center;

    render(&grid, &root);

    try testing.expectEqual(@as(u21, ' '), cells[3].codepoint);
    try testing.expectEqual(@as(u21, 'H'), cells[4].codepoint);
    try testing.expectEqual(@as(u21, 'i'), cells[5].codepoint);
    try testing.expectEqual(@as(u21, ' '), cells[6].codepoint);
}

test "text right alignment" {
    var cells: [10 * 1]Cell = undefined;
    var grid = make_grid(&cells, 10, 1);

    var root = make_test_box();
    root.rect = .{ .col = 0, .row = 0, .w = 10, .h = 1 };
    root.flags.draw_text = true;
    root.display_string = "Hi";
    root.fg_color = .{ .ansi = .white };
    root.text_align = .right;

    render(&grid, &root);

    try testing.expectEqual(@as(u21, ' '), cells[7].codepoint);
    try testing.expectEqual(@as(u21, 'H'), cells[8].codepoint);
    try testing.expectEqual(@as(u21, 'i'), cells[9].codepoint);
}

test "clip restricts child drawing" {
    var cells: [10 * 5]Cell = undefined;
    var grid = make_grid(&cells, 10, 5);

    var parent = make_test_box();
    parent.rect = .{ .col = 0, .row = 0, .w = 10, .h = 5 };
    parent.flags.clip = true;

    var child = make_test_box();
    child.rect = .{ .col = 8, .row = 0, .w = 5, .h = 1 };
    child.flags.draw_background = true;
    child.bg_color = .{ .ansi = .red };

    link(&parent, &child);

    render(&grid, &parent);

    try testing.expect(cells[8].bg.eql(.{ .ansi = .red }));
    try testing.expect(cells[9].bg.eql(.{ .ansi = .red }));
    try testing.expect(cells[7].bg.eql(.default));
}

test "border with text inside" {
    var cells: [10 * 3]Cell = undefined;
    var grid = make_grid(&cells, 10, 3);

    var root = make_test_box();
    root.rect = .{ .col = 0, .row = 0, .w = 10, .h = 3 };
    root.flags = BoxFlags.with_border(.{
        .draw_border = true,
        .draw_text = true,
        .draw_background = true,
    });
    root.border_color = .{ .ansi = .white };
    root.fg_color = .{ .ansi = .white };
    root.bg_color = .{ .ansi = .black };
    root.display_string = "Test";

    render(&grid, &root);

    try testing.expectEqual(@as(u21, '┌'), cells[0].codepoint);
    try testing.expectEqual(@as(u21, '┐'), cells[9].codepoint);
    try testing.expectEqual(@as(u21, '└'), cells[20].codepoint);
    try testing.expectEqual(@as(u21, '┘'), cells[29].codepoint);

    try testing.expectEqual(@as(u21, '│'), cells[10].codepoint);
    try testing.expectEqual(@as(u21, 'T'), cells[11].codepoint);
    try testing.expectEqual(@as(u21, 'e'), cells[12].codepoint);
    try testing.expectEqual(@as(u21, 's'), cells[13].codepoint);
    try testing.expectEqual(@as(u21, 't'), cells[14].codepoint);
}

test "children draw on top of parent background" {
    var cells: [10 * 3]Cell = undefined;
    var grid = make_grid(&cells, 10, 3);

    var parent = make_test_box();
    parent.rect = .{ .col = 0, .row = 0, .w = 10, .h = 3 };
    parent.flags.draw_background = true;
    parent.bg_color = .{ .ansi = .blue };

    var child = make_test_box();
    child.rect = .{ .col = 2, .row = 1, .w = 3, .h = 1 };
    child.flags.draw_background = true;
    child.bg_color = .{ .ansi = .red };

    link(&parent, &child);

    render(&grid, &parent);

    try testing.expect(cells[0].bg.eql(.{ .ansi = .blue }));
    try testing.expect(cells[12].bg.eql(.{ .ansi = .red }));
    try testing.expect(cells[11].bg.eql(.{ .ansi = .blue }));
}

test "partial border — only top side" {
    var cells: [6 * 3]Cell = undefined;
    var grid = make_grid(&cells, 6, 3);

    var root = make_test_box();
    root.rect = .{ .col = 0, .row = 0, .w = 6, .h = 3 };
    root.flags.draw_border = true;
    root.flags.draw_side_top = true;
    root.border_color = .{ .ansi = .white };

    render(&grid, &root);

    try testing.expectEqual(@as(u21, '─'), cells[0].codepoint);
    try testing.expectEqual(@as(u21, '─'), cells[5].codepoint);
    try testing.expectEqual(@as(u21, ' '), cells[6].codepoint);
    try testing.expectEqual(@as(u21, ' '), cells[11].codepoint);
    try testing.expectEqual(@as(u21, ' '), cells[12].codepoint);
}
