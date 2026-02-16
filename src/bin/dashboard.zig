const std = @import("std");
const base = @import("base");
const Arena = base.Arena;
const term = @import("term");
const ui = @import("ui");
const unicode = ui.unicode;
const Color = ui.Color;
const Box = ui.Box;
const Rect = ui.Rect;
const interaction = ui.interaction;
const widgets = ui.widgets;
const draw = term.draw;
const Grid = draw.Grid;

// ---------------------------------------------------------------------------
// Colors (matching 18-carbon-v2 palette)
// ---------------------------------------------------------------------------

pub const bg_color: Color = .{ .rgb = .{ 10, 10, 10 } };
const hi_color: Color = .{ .rgb = .{ 220, 220, 215 } };
const accent_color: Color = .{ .rgb = .{ 210, 85, 70 } };
const muted_color: Color = .{ .rgb = .{ 135, 135, 130 } };
const dim_color: Color = .{ .rgb = .{ 65, 65, 62 } };
const very_dim_color: Color = .{ .rgb = .{ 32, 32, 30 } };
const bar_color: Color = .{ .rgb = .{ 150, 60, 50 } };
const bar_empty_color: Color = .{ .rgb = .{ 30, 20, 18 } };
const rail_color: Color = .{ .rgb = .{ 45, 45, 42 } };
const section_header_bg: Color = .{ .rgb = .{ 65, 65, 62 } };
const section_header_fg: Color = .{ .rgb = .{ 10, 10, 10 } };

// ---------------------------------------------------------------------------
// Fake Data
// ---------------------------------------------------------------------------

const Account = struct {
    name: []const u8,
    balance: f64,
};

const accounts = [_]Account{
    .{ .name = "Checking", .balance = 4521.30 },
    .{ .name = "Savings", .balance = 32100.00 },
    .{ .name = "Investment", .balance = 91221.26 },
};

const Expense = struct {
    name: []const u8,
    amount: u32,
    pct: u32,
};

const expenses = [_]Expense{
    .{ .name = "HOUSING", .amount = 1200, .pct = 31 },
    .{ .name = "FOOD", .amount = 642, .pct = 17 },
    .{ .name = "TRANSPORT", .amount = 380, .pct = 10 },
    .{ .name = "UTILITIES", .amount = 246, .pct = 6 },
    .{ .name = "ENTERTAIN", .amount = 180, .pct = 5 },
    .{ .name = "HEALTH", .amount = 120, .pct = 3 },
};

const Transaction = struct {
    date: []const u8,
    payee: []const u8,
    category: []const u8,
    amount: f64,
};

const transactions = [_]Transaction{
    .{ .date = "04/08", .payee = "WHOLE FOODS", .category = "FOOD", .amount = -84.32 },
    .{ .date = "04/08", .payee = "BANK TRANSFER", .category = "TRANSFER", .amount = 200.00 },
    .{ .date = "04/07", .payee = "AMAZON.COM", .category = "SHOPPING", .amount = -34.99 },
    .{ .date = "04/07", .payee = "SPOTIFY", .category = "ENTERTAIN", .amount = -9.99 },
    .{ .date = "04/07", .payee = "STARBUCKS", .category = "FOOD", .amount = -5.50 },
    .{ .date = "04/05", .payee = "SHELL OIL", .category = "TRANSPORT", .amount = -52.00 },
    .{ .date = "04/05", .payee = "OLIVE GARDEN", .category = "FOOD", .amount = -67.80 },
};

const PortfolioEntry = struct {
    name: []const u8,
    amount: u32,
    pct_str: []const u8,
    sparkline_values: []const i32,
};

const portfolio = [_]PortfolioEntry{
    .{ .name = "Stocks", .amount = 62450, .pct_str = "+14.2%", .sparkline_values = &.{ 12, 18, 24, 30, 36, 42, 48 } },
    .{ .name = "Bonds", .amount = 18220, .pct_str = "+3.1%", .sparkline_values = &.{ 28, 28, 30, 31, 31, 33, 34 } },
    .{ .name = "Crypto", .amount = 10550, .pct_str = "+8.7%", .sparkline_values = &.{ 10, 22, 28, 16, 35, 44, 55 } },
};

const net_worth: f64 = 127842.56;
const net_worth_change: f64 = 2341.20;
const net_worth_pct = "+1.9%";
const income: f64 = 6200.00;
const total_expenses: f64 = 3858.80;
const net_savings: f64 = 2341.20;
const net_worth_sparkline_values = &.{ 10, 12, 15, 14, 16, 18, 17, 20, 19, 22, 23, 25 };

// ---------------------------------------------------------------------------
// Custom draw: expense bars
// ---------------------------------------------------------------------------

const ExpenseBarData = struct {
    amount: u32,
    pct: u32,
    max_pct: u32,
    max_bar_width: u16,
};

fn draw_expense_bar(box: *Box, grid: *Grid, clip: Rect) void {
    const data: *const ExpenseBarData = ui.custom_draw_data(ExpenseBarData, box.custom_draw_user_data) orelse return;
    const rect = box.rect;
    if (rect.w == 0 or rect.h == 0) return;

    const visible = Rect.intersect(rect, clip);
    if (visible.w == 0 or visible.h == 0) return;

    const row = rect.row;
    const max_bar: u16 = @min(data.max_bar_width, rect.w);
    const filled: u16 = if (data.max_pct > 0)
        @max(1, @as(u16, @intFromFloat(@as(f32, @floatFromInt(data.pct)) / @as(f32, @floatFromInt(data.max_pct)) * @as(f32, @floatFromInt(max_bar)))))
    else
        1;

    var col = rect.col;
    while (col < rect.col +| max_bar) : (col += 1) {
        if (!visible.contains(col, row)) continue;
        const is_filled = (col - rect.col) < filled;
        const cp: u21 = if (is_filled) unicode.block_full else unicode.block_light_shade;
        const color: Color = if (is_filled) bar_color else bar_empty_color;
        draw.write_cell(grid, col, row, .{ .codepoint = cp, .fg = color, .bg = box.bg_color });
    }
}

// ---------------------------------------------------------------------------
// UI construction
// ---------------------------------------------------------------------------

pub fn build_ui() !void {
    ui.push_color(hi_color);
    defer ui.pop_color();
    ui.push_bg(bg_color);
    defer ui.pop_bg();
    ui.push_flags(.{ .draw_background = true });
    defer ui.pop_flags();

    ui.spacer(.y, 1);

    try build_header();
    try build_nav();

    ui.spacer(.y, 1);

    try build_top_sections();

    ui.spacer(.y, 1);

    try build_transactions();

    ui.spacer(.y, 1);

    try build_portfolio();

    ui.next_width(.pct(1, 0));
    ui.next_height(.pct(1, 0));
    _ = ui.build_box("", .{});

    try build_status_bar();
}

fn build_header() !void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    _ = ui.push_parent_box("header###header", .{});
    defer ui.pop_parent();

    ui.spacer(.x, 3);

    {
        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box("GROSCHEN", .{ .draw_text = true });
    }

    ui.next_width(.pct(1, 0));
    ui.next_height(.cells(1, 1));
    _ = ui.build_box("", .{});

    {
        ui.push_color(dim_color);
        defer ui.pop_color();
        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box("synced", .{ .draw_text = true });
    }
    ui.spacer(.x, 1);
    {
        ui.push_color(accent_color);
        defer ui.pop_color();
        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        const dot = try render_glyph(unicode.black_circle);
        const dot_key = try ui.arena_print("{s}###sync_dot", .{dot});
        _ = ui.build_box(dot_key, .{ .draw_text = true });
    }
    ui.spacer(.x, 1);
    {
        ui.push_color(dim_color);
        defer ui.pop_color();
        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box("last update 2m ago", .{ .draw_text = true });
    }

    ui.spacer(.x, 3);
}

fn build_nav() !void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    _ = ui.push_parent_box("nav###nav", .{});
    defer ui.pop_parent();

    ui.spacer(.x, 3);

    const middle_dot = try render_glyph(unicode.middle_dot);

    {
        ui.push_color(accent_color);
        defer ui.pop_color();
        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        const dot = try render_glyph(unicode.black_circle);
        const dot_key = try ui.arena_print("{s}###nav_dot", .{dot});
        _ = ui.build_box(dot_key, .{ .draw_text = true });
    }
    ui.spacer(.x, 1);
    const overview_label = try ui.arena_print("{s}overview###nav_overview", .{middle_dot});
    nav_item("o", overview_label);
    ui.spacer(.x, 4);
    const accounts_label = try ui.arena_print("{s}accounts###nav_accounts", .{middle_dot});
    nav_item("a", accounts_label);
    ui.spacer(.x, 4);
    const budget_label = try ui.arena_print("{s}budget###nav_budget", .{middle_dot});
    nav_item("b", budget_label);
    ui.spacer(.x, 4);
    const invest_label = try ui.arena_print("{s}invest###nav_invest", .{middle_dot});
    nav_item("i", invest_label);
    ui.spacer(.x, 4);
    const txns_label = try ui.arena_print("{s}txns###nav_txns", .{middle_dot});
    nav_item("t", txns_label);
    ui.spacer(.x, 4);
    const history_label = try ui.arena_print("{s}history###nav_history", .{middle_dot});
    nav_item("h", history_label);
}

fn nav_item(key_label: []const u8, rest_label: []const u8) void {
    {
        ui.push_color(accent_color);
        defer ui.pop_color();
        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box(key_label, .{ .draw_text = true });
    }
    {
        ui.push_color(dim_color);
        defer ui.pop_color();
        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box(rest_label, .{ .draw_text = true });
    }
}

fn build_top_sections() !void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.children(1));
    _ = ui.push_parent_box("top_cols###top_cols", .{});
    defer ui.pop_parent();

    ui.spacer(.x, 3);

    {
        ui.next_axis(.y);
        ui.next_width(.cells(37, 1));
        ui.next_height(.children(1));
        _ = ui.push_parent_box("left_col###left_col", .{});
        defer ui.pop_parent();

        try build_net_worth_section();
        ui.spacer(.y, 1);
        try build_cash_flow_section();
    }

    ui.spacer(.x, 2);

    {
        ui.next_axis(.y);
        ui.next_width(.cells(36, 1));
        ui.next_height(.children(1));
        _ = ui.push_parent_box("right_col###right_col", .{});
        defer ui.pop_parent();

        try build_accounts_section();
        ui.spacer(.y, 1);
        try build_expenses_section();
    }
}

fn section_header(label: []const u8) void {
    ui.push_bg(section_header_bg);
    defer ui.pop_bg();
    ui.push_color(section_header_fg);
    defer ui.pop_color();
    ui.next_width(.text(2, 1));
    ui.next_height(.cells(1, 1));
    ui.next_text_padding(1);
    _ = ui.build_box(label, .{ .draw_text = true, .draw_background = true });
}

fn render_sparkline_values(values: []const i32) ![]const u8 {
    const arena = ui.get_build_arena();

    if (values.len == 0) return "";

    var min_value: i32 = values[0];
    var max_value: i32 = values[0];
    for (values[1..]) |value| {
        if (value < min_value) min_value = value;
        if (value > max_value) max_value = value;
    }

    const blocks = unicode.sparkline_blocks;
    const range: i64 = @as(i64, max_value) - @as(i64, min_value);
    const max_index: i64 = @as(i64, blocks.len - 1);
    const flat_index: usize = @intCast(max_index / 2);

    const start_pos = arena.get_pos();
    for (values) |value| {
        var block_index: usize = flat_index;
        if (range != 0) {
            const numerator = (@as(i64, value) - @as(i64, min_value)) * max_index;
            const scaled = @divTrunc(numerator, range);
            if (scaled <= 0) {
                block_index = 0;
            } else if (scaled >= max_index) {
                block_index = @intCast(max_index);
            } else {
                block_index = @intCast(scaled);
            }
        }

        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(blocks[block_index], &buf);
        const dest = try arena.push(len);
        @memcpy(dest, buf[0..len]);
    }

    const end_pos = arena.get_pos();
    return arena.memory[start_pos..end_pos];
}

fn render_glyph(codepoint: u21) ![]const u8 {
    const arena = ui.get_build_arena();
    const scratch = Arena.get_scratch(&.{arena});
    defer scratch.release();

    var buf: [4]u8 = undefined;
    const len = try std.unicode.utf8Encode(codepoint, &buf);
    return arena.dupe(u8, buf[0..len]);
}

fn render_repeat(codepoint: u21, count: usize) ![]const u8 {
    const arena = ui.get_build_arena();
    const scratch = Arena.get_scratch(&.{arena});
    defer scratch.release();

    var buf: [4]u8 = undefined;
    const glyph_len = try std.unicode.utf8Encode(codepoint, &buf);
    const tmp = try scratch.arena.alloc(u8, glyph_len * count);
    var out_index: usize = 0;
    var index: usize = 0;
    while (index < count) : (index += 1) {
        @memcpy(tmp[out_index .. out_index + glyph_len], buf[0..glyph_len]);
        out_index += glyph_len;
    }

    return arena.dupe(u8, tmp[0..out_index]);
}

fn build_net_worth_section() !void {
    section_header("NET WORTH###nw_hdr");
    ui.spacer(.y, 1);

    {
        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box("$127,842.56", .{ .draw_text = true });
    }

    {
        ui.push_color(dim_color);
        defer ui.pop_color();
        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        const sparkline = try render_sparkline_values(net_worth_sparkline_values);
        const spark_key = try ui.arena_print("{s}###nw_spark", .{sparkline});
        _ = ui.build_box(spark_key, .{ .draw_text = true });
    }

    {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(1, 1));
        _ = ui.push_parent_box("nw_change###nw_change", .{});
        defer ui.pop_parent();

        ui.push_color(accent_color);
        defer ui.pop_color();
        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box("+$2,341.20", .{ .draw_text = true });

        ui.spacer(.x, 2);

        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box(net_worth_pct ++ "###nw_pct", .{ .draw_text = true });
    }
}

fn build_cash_flow_section() !void {
    section_header("CASH FLOW###cf_hdr");
    ui.spacer(.y, 1);

    try build_cash_flow_row("Income###cf_income", "Income", "$ 6,200.00");
    try build_cash_flow_row("Expenses###cf_expenses", "Expenses", "$ 3,858.80");

    {
        ui.push_color(very_dim_color);
        defer ui.pop_color();
        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(1, 1));
        const sep = try render_repeat(unicode.box_light_horizontal, 32);
        const sep_key = try ui.arena_print("{s}###cf_sep", .{sep});
        _ = ui.build_box(sep_key, .{ .draw_text = true });
    }

    try build_cash_flow_row("Net Savings###cf_net", "Net Savings", "$ 2,341.20");
}

fn build_cash_flow_row(box_key: []const u8, label: []const u8, amount: []const u8) !void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 0));
    ui.next_height(.cells(1, 1));
    _ = ui.push_parent_box(box_key, .{});
    defer ui.pop_parent();

    {
        ui.push_color(muted_color);
        defer ui.pop_color();
        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box(label, .{ .draw_text = true });
    }

    ui.next_width(.pct(1, 0));
    ui.next_height(.cells(1, 1));
    _ = ui.build_box("", .{});

    {
        const amt_color: Color = if (std.mem.startsWith(u8, label, "Net")) accent_color else hi_color;
        ui.push_color(amt_color);
        defer ui.pop_color();
        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        const amt_key = try ui.arena_print("{s}###cf_amt_{s}", .{ amount, label });
        _ = ui.build_box(amt_key, .{ .draw_text = true });
    }
}

fn build_accounts_section() !void {
    section_header("ACCOUNTS###acct_hdr");
    ui.spacer(.y, 1);

    for (accounts, 0..) |account, index| {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(1, 1));
        const row_key = try ui.arena_print("acct_row_{d}###acct_row_{d}", .{ index, index });
        _ = ui.push_parent_box(row_key, .{});
        defer ui.pop_parent();

        {
            ui.push_color(muted_color);
            defer ui.pop_color();
            ui.next_width(.pct(1, 0));
            ui.next_height(.cells(1, 1));
            _ = ui.build_box(account.name, .{ .draw_text = true });
        }

        {
            ui.next_width(.text(0, 1));
            ui.next_height(.cells(1, 1));
            ui.push_text_align(.right);
            defer ui.pop_text_align();
            const amt_str = try format_account_amount(account.balance, index);
            _ = ui.build_box(amt_str, .{ .draw_text = true });
        }
    }
}

fn build_expenses_section() !void {
    section_header("EXPENSES###exp_hdr");
    ui.spacer(.y, 1);

    for (expenses, 0..) |expense, index| {
        try build_expense_row(expense, index);
    }

    {
        ui.push_color(very_dim_color);
        defer ui.pop_color();
        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(1, 1));
        const sep = try render_repeat(unicode.box_light_horizontal, 35);
        const sep_key = try ui.arena_print("{s}###exp_sep", .{sep});
        _ = ui.build_box(sep_key, .{ .draw_text = true });
    }

    {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(1, 1));
        _ = ui.push_parent_box("exp_total###exp_total", .{});
        defer ui.pop_parent();

        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box("", .{});

        {
            ui.push_color(accent_color);
            defer ui.pop_color();
            ui.next_width(.text(0, 1));
            ui.next_height(.cells(1, 1));
            _ = ui.build_box("$3,858.80###exp_total_amt", .{ .draw_text = true });
        }
    }
}

var expense_bar_data: [8]ExpenseBarData = undefined;

fn build_expense_row(expense: Expense, index: usize) !void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 0));
    ui.next_height(.cells(1, 1));
    const row_key = try ui.arena_print("exp_row_{d}###exp_row_{d}", .{ index, index });
    _ = ui.push_parent_box(row_key, .{});
    defer ui.pop_parent();

    {
        ui.push_color(muted_color);
        defer ui.pop_color();
        ui.next_width(.cells(10, 1));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box(expense.name, .{ .draw_text = true });
    }

    {
        ui.next_width(.cells(8, 1));
        ui.next_height(.cells(1, 1));
        ui.push_text_align(.right);
        defer ui.pop_text_align();
        const formatted = try format_expense_amount(expense.amount);
        _ = ui.build_box(formatted, .{ .draw_text = true });
    }

    {
        ui.push_color(dim_color);
        defer ui.pop_color();
        ui.next_width(.cells(5, 1));
        ui.next_height(.cells(1, 1));
        ui.push_text_align(.right);
        defer ui.pop_text_align();
        const pct_str = try ui.arena_print("{d}%###exp_pct_{d}", .{ expense.pct, index });
        _ = ui.build_box(pct_str, .{ .draw_text = true });
    }

    if (index < expense_bar_data.len) {
        expense_bar_data[index] = .{
            .amount = expense.amount,
            .pct = expense.pct,
            .max_pct = 31,
            .max_bar_width = 12,
        };
        ui.next_width(.cells(12, 0));
        ui.next_height(.cells(1, 1));
        const bar_key = try ui.arena_print("exp_bar_{d}###exp_bar_{d}", .{ index, index });
        const bar_box = ui.build_box(bar_key, .{});
        bar_box.custom_draw = draw_expense_bar;
        bar_box.custom_draw_user_data = ui.custom_draw_data(ExpenseBarData, &expense_bar_data[index]);
    }
}

fn build_transactions() !void {
    ui.next_width(.pct(1, 1));
    ui.next_height(.children(1));
    _ = ui.push_parent_box("txn_section###txn_section", .{});
    defer ui.pop_parent();

    {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(1, 1));
        _ = ui.push_parent_box("txn_hdr_row###txn_hdr_row", .{});
        defer ui.pop_parent();
        ui.spacer(.x, 3);
        section_header("TRANSACTIONS###txn_hdr");
    }

    ui.spacer(.y, 1);

    {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(1, 1));
        _ = ui.push_parent_box("txn_col_hdr###txn_col_hdr", .{});
        defer ui.pop_parent();

        ui.spacer(.x, 3);

        ui.push_color(very_dim_color);
        defer ui.pop_color();

        {
            ui.next_width(.cells(8, 1));
            ui.next_height(.cells(1, 1));
            _ = ui.build_box("DATE", .{ .draw_text = true });
        }
        {
            ui.next_width(.cells(22, 1));
            ui.next_height(.cells(1, 1));
            _ = ui.build_box("PAYEE", .{ .draw_text = true });
        }
        {
            ui.next_width(.cells(20, 1));
            ui.next_height(.cells(1, 1));
            _ = ui.build_box("CATEGORY", .{ .draw_text = true });
        }
        {
            ui.next_width(.pct(1, 0));
            ui.next_height(.cells(1, 1));
            ui.push_text_align(.right);
            defer ui.pop_text_align();
            _ = ui.build_box("AMOUNT", .{ .draw_text = true });
        }
        ui.spacer(.x, 3);
    }

    for (transactions, 0..) |txn, index| {
        try build_transaction_row(txn, index);
    }
}

fn build_transaction_row(txn: Transaction, index: usize) !void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 0));
    ui.next_height(.cells(1, 1));
    const row_key = try ui.arena_print("txn_row_{d}###txn_row_{d}", .{ index, index });
    _ = ui.push_parent_box(row_key, .{});
    defer ui.pop_parent();

    ui.spacer(.x, 3);

    const is_positive = txn.amount > 0;
    const row_color: Color = if (is_positive) accent_color else muted_color;

    {
        ui.push_color(dim_color);
        defer ui.pop_color();
        ui.next_width(.cells(8, 1));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box(txn.date, .{ .draw_text = true });
    }

    {
        ui.push_color(row_color);
        defer ui.pop_color();
        ui.next_width(.cells(22, 1));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box(txn.payee, .{ .draw_text = true });
    }

    {
        ui.push_color(dim_color);
        defer ui.pop_color();
        ui.next_width(.cells(20, 1));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box(txn.category, .{ .draw_text = true });
    }

    {
        ui.push_color(row_color);
        defer ui.pop_color();
        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(1, 1));
        ui.push_text_align(.right);
        defer ui.pop_text_align();
        const sign: []const u8 = if (is_positive) "+$" else "-$";
        const amt_str = try format_txn_amount(sign, @abs(txn.amount), index);
        _ = ui.build_box(amt_str, .{ .draw_text = true });
    }

    ui.spacer(.x, 3);
}

fn build_portfolio() !void {
    ui.next_width(.pct(1, 1));
    ui.next_height(.children(1));
    _ = ui.push_parent_box("port_section###port_section", .{});
    defer ui.pop_parent();

    {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(1, 1));
        _ = ui.push_parent_box("port_hdr_row###port_hdr_row", .{});
        defer ui.pop_parent();
        ui.spacer(.x, 3);
        section_header("PORTFOLIO###port_hdr");
    }

    ui.spacer(.y, 1);

    {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 0));
        ui.next_height(.children(1));
        _ = ui.push_parent_box("port_entries###port_entries", .{});
        defer ui.pop_parent();

        ui.spacer(.x, 3);

        for (portfolio, 0..) |entry, index| {
            if (index > 0) ui.spacer(.x, 5);
            try build_portfolio_block(entry, index);
        }
    }
}

fn build_portfolio_block(entry: PortfolioEntry, index: usize) !void {
    ui.next_axis(.y);
    ui.next_width(.cells(16, 0));
    ui.next_height(.children(1));
    const block_key = try ui.arena_print("port_block_{d}###port_block_{d}", .{ index, index });
    _ = ui.push_parent_box(block_key, .{});
    defer ui.pop_parent();

    {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(1, 1));
        const r1_key = try ui.arena_print("port_r1_{d}###port_r1_{d}", .{ index, index });
        _ = ui.push_parent_box(r1_key, .{});
        defer ui.pop_parent();

        {
            ui.push_color(muted_color);
            defer ui.pop_color();
            ui.next_width(.text(0, 1));
            ui.next_height(.cells(1, 1));
            _ = ui.build_box(entry.name, .{ .draw_text = true });
        }

        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box("", .{});

        {
            ui.next_width(.text(0, 1));
            ui.next_height(.cells(1, 1));
            const amt_str = try format_portfolio_amount(entry.amount, index);
            _ = ui.build_box(amt_str, .{ .draw_text = true });
        }
    }

    {
        ui.next_axis(.x);
        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(1, 1));
        const r2_key = try ui.arena_print("port_r2_{d}###port_r2_{d}", .{ index, index });
        _ = ui.push_parent_box(r2_key, .{});
        defer ui.pop_parent();

        {
            ui.push_color(dim_color);
            defer ui.pop_color();
            ui.next_width(.text(0, 1));
            ui.next_height(.cells(1, 1));
            const sparkline = try render_sparkline_values(entry.sparkline_values);
            const spark_key = try ui.arena_print("{s}###port_spark_{d}", .{ sparkline, index });
            _ = ui.build_box(spark_key, .{ .draw_text = true });
        }

        ui.next_width(.pct(1, 0));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box("", .{});

        {
            ui.push_color(accent_color);
            defer ui.pop_color();
            ui.next_width(.text(0, 1));
            ui.next_height(.cells(1, 1));
            const pct_key = try ui.arena_print("{s}###port_pct_{d}", .{ entry.pct_str, index });
            _ = ui.build_box(pct_key, .{ .draw_text = true });
        }
    }
}

fn build_status_bar() !void {
    ui.next_axis(.x);
    ui.next_width(.pct(1, 1));
    ui.next_height(.cells(1, 1));
    _ = ui.push_parent_box("status###status", .{});
    defer ui.pop_parent();

    ui.spacer(.x, 3);

    {
        ui.push_color(dim_color);
        defer ui.pop_color();
        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        _ = ui.build_box("3 accounts", .{ .draw_text = true });
    }

    ui.next_width(.pct(1, 0));
    ui.next_height(.cells(1, 1));
    _ = ui.build_box("", .{});

    {
        ui.push_color(dim_color);
        defer ui.pop_color();
        ui.next_width(.text(0, 1));
        ui.next_height(.cells(1, 1));
        const middle_dot = try render_glyph(unicode.middle_dot);
        const status_label = try ui.arena_print("q{s}quit  ?{s}help", .{ middle_dot, middle_dot });
        _ = ui.build_box(status_label, .{ .draw_text = true });
    }

    ui.spacer(.x, 3);
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

fn format_account_amount(amount: f64, index: usize) ![]const u8 {
    const abs_val = @abs(amount);
    const rounded = @round(abs_val * 100.0);
    const total_cents: u64 = @intFromFloat(rounded);
    const whole = total_cents / 100;
    const cents = total_cents % 100;
    if (whole >= 10_000) {
        const t = whole / 1_000;
        const u = whole % 1_000;
        return try ui.arena_print("$ {d},{d:0>3}.{d:0>2}###acct_amt_{d}", .{ t, u, cents, index });
    } else if (whole >= 1_000) {
        const t = whole / 1_000;
        const u = whole % 1_000;
        return try ui.arena_print("$  {d},{d:0>3}.{d:0>2}###acct_amt_{d}", .{ t, u, cents, index });
    } else {
        return try ui.arena_print("$     {d}.{d:0>2}###acct_amt_{d}", .{ whole, cents, index });
    }
}

fn format_expense_amount(amount: u32) ![]const u8 {
    if (amount >= 1_000) {
        const t = amount / 1_000;
        const u = amount % 1_000;
        return try ui.arena_print("$ {d},{d:0>3}###exp_famt_{d}", .{ t, u, amount });
    } else {
        return try ui.arena_print("$   {d}###exp_famt_{d}", .{ amount, amount });
    }
}

fn format_txn_amount(sign: []const u8, abs_amount: f64, index: usize) ![]const u8 {
    const rounded = @round(abs_amount * 100.0);
    const total_cents: u64 = @intFromFloat(rounded);
    const whole = total_cents / 100;
    const cents = total_cents % 100;
    if (whole >= 1_000) {
        const t = whole / 1_000;
        const u = whole % 1_000;
        return try ui.arena_print("{s}{d},{d:0>3}.{d:0>2}###txn_amt_{d}", .{ sign, t, u, cents, index });
    } else if (whole >= 100) {
        return try ui.arena_print("{s}  {d}.{d:0>2}###txn_amt_{d}", .{ sign, whole, cents, index });
    } else if (whole >= 10) {
        return try ui.arena_print("{s}   {d}.{d:0>2}###txn_amt_{d}", .{ sign, whole, cents, index });
    } else {
        return try ui.arena_print("{s}    {d}.{d:0>2}###txn_amt_{d}", .{ sign, whole, cents, index });
    }
}

fn format_portfolio_amount(amount: u32, index: usize) ![]const u8 {
    if (amount >= 10_000) {
        const t = amount / 1_000;
        const u = amount % 1_000;
        return try ui.arena_print("${d},{d:0>3}###port_amt_{d}", .{ t, u, index });
    } else if (amount >= 1_000) {
        const t = amount / 1_000;
        const u = amount % 1_000;
        return try ui.arena_print("${d},{d:0>3}###port_amt_{d}", .{ t, u, index });
    } else {
        return try ui.arena_print("${d}###port_amt_{d}", .{ amount, index });
    }
}
