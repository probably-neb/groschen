#!/usr/bin/env python3
"""Generate design 18: Carbon V2 — an iteration on 14-carbon with layout changes."""
import os

# === Escape Helpers ===
E = "\033"
RST = f"{E}[0m"
BOLD = f"{E}[1m"
DIM = f"{E}[2m"
ITALIC = f"{E}[3m"
ULINE = f"{E}[4m"
REVERSE = f"{E}[7m"

def fg(r, g, b): return f"{E}[38;2;{r};{g};{b}m"
def bg(r, g, b): return f"{E}[48;2;{r};{g};{b}m"
def at(r, c): return f"{E}[{r};{c}H"

W, H = 80, 40

def setup(bgc):
    o = f"{E}[2J{E}[H{E}[?25l"
    for r in range(1, H + 1):
        o += f"{at(r, 1)}{bgc}{' ' * W}"
    return o

def finish():
    return f"{RST}{at(H + 1, 1)}{E}[?25h"

def p(r, c, text, *styles):
    return f"{at(r, c)}{''.join(styles)}{text}{RST}"


# ============================================================
# Shared financial data
# ============================================================
ACCOUNTS = [("CHECKING", 4521.30), ("SAVINGS", 32100.00), ("INVESTMENT", 91221.26)]
MONTHLY = [("INCOME", 6200.00), ("EXPENSES", 3858.80)]
NET_CHANGE = 2341.20
NET_WORTH = 127842.56
ALLOCS = [("STOCKS", 49), ("BONDS", 14), ("CRYPTO", 8), ("CASH", 29)]
EXPENSES = [
    ("HOUSING", 1200, 31), ("FOOD", 642, 17), ("TRANSPORT", 380, 10),
    ("UTILITIES", 246, 6), ("ENTERTAIN", 180, 5), ("HEALTH", 120, 3),
]
TXNS = [
    ("04/08", "WHOLE FOODS",   "FOOD",      -84.32),
    ("04/08", "BANK TRANSFER", "TRANSFER",  200.00),
    ("04/07", "AMAZON.COM",    "SHOPPING",  -34.99),
    ("04/07", "SPOTIFY",       "ENTERTAIN", -9.99),
    ("04/07", "STARBUCKS",     "FOOD",      -5.50),
    ("04/05", "SHELL OIL",     "TRANSPORT", -52.00),
    ("04/05", "OLIVE GARDEN",  "FOOD",      -67.80),
]

PORTFOLIO = [
    ("Stocks", 62450, "+14.2%", "▁▂▃▄▅▆▇"),
    ("Bonds", 18220, "+3.1%", "▅▅▆▆▆▇▇"),
    ("Crypto", 10550, "+8.7%", "▂▄▅▃▆▇█"),
]


# ============================================================
# DESIGN 18: CARBON V2
#
# Iteration on 14-carbon with these changes:
# - Net worth section is vertical (stacked)
# - Expenses label row is adjacent to expense items
# - Expense bars are shrunk; columns: category, amount, pct, bar
# - Total $3,858.80 is bright red, bottom-right of expenses
# - Synced/last-update moved to top header, replacing date
# - Portfolio entries are square blocks (name, amount / bar / pct%)
#
# Layout (left column cols 4-40, right column cols 42-77):
#   Row 2-3:   Header + navigation
#   Row 5-9:   NET WORTH (left, vertical)  |  ACCOUNTS (right)
#   Row 11-16: CASH FLOW (left)            |  EXPENSES (right, rows 11-20)
#   Row 22-30: TRANSACTIONS (full width)
#   Row 32-35: PORTFOLIO (full width, 2-row square blocks)
#   Row 40:    Bottom status
# ============================================================

def design_carbon_v2():
    BG = bg(10, 10, 10)
    HI = fg(220, 220, 215)
    AC = fg(210, 85, 70)
    AC_BG = bg(210, 85, 70)
    MD = fg(135, 135, 130)
    DK = fg(65, 65, 62)
    VDK = fg(32, 32, 30)
    BAR = fg(150, 60, 50)
    BARE = fg(30, 20, 18)
    RAIL = fg(45, 45, 42)

    o = setup(BG)

    # Vertical side rails
    for row in range(1, 41):
        o += p(row, 1, "│", RAIL, BG)
        o += p(row, 80, "│", RAIL, BG)

    # ── Header: title left, synced + last-update right (replaces date) ──
    o += p(2, 4, "GROSCHEN", HI, BOLD, BG)
    o += p(2, 52, "synced", DK, BG)
    o += p(2, 59, "●", AC, BG)
    o += p(2, 61, "last update 2m ago", DK, BG)

    # Navigation
    o += p(3, 4, "●", AC, BG)
    o += p(3, 6, "o", AC, BOLD, BG)
    o += p(3, 7, "·overview", DK, BG)
    o += p(3, 20, "a", AC, BOLD, BG)
    o += p(3, 21, "·accounts", DK, BG)
    o += p(3, 34, "b", AC, BOLD, BG)
    o += p(3, 35, "·budget", DK, BG)
    o += p(3, 46, "i", AC, BOLD, BG)
    o += p(3, 47, "·invest", DK, BG)
    o += p(3, 58, "t", AC, BOLD, BG)
    o += p(3, 59, "·txns", DK, BG)
    o += p(3, 68, "h", AC, BOLD, BG)
    o += p(3, 69, "·history", DK, BG)

    # ── Net Worth (vertical, left column) ──
    o += p(5, 4, " NET WORTH ", fg(10, 10, 10), BOLD, bg(65, 65, 62))
    o += p(7, 4, "$127,842.56", HI, BOLD, BG)
    o += p(8, 4, "▁▂▃▃▄▅▅▆▆▇▇█", DK, BG)
    o += p(9, 4, "+$2,341.20", AC, BOLD, BG)
    o += p(9, 16, "+1.9%", AC, BG)

    # ── Accounts (right column, rows 5-9) ──
    o += p(5, 42, " ACCOUNTS ", fg(10, 10, 10), BOLD, bg(65, 65, 62))
    o += p(7, 42, "Checking", MD, BG)
    o += p(7, 62, f"${4521.30:>10,.2f}", HI, BG)
    o += p(8, 42, "Savings", MD, BG)
    o += p(8, 62, f"${32100:>10,.2f}", HI, BG)
    o += p(9, 42, "Investment", MD, BG)
    o += p(9, 62, f"${91221.26:>10,.2f}", HI, BG)

    # ── Cash Flow (left column, rows 11-16) ──
    o += p(11, 4, " CASH FLOW ", fg(10, 10, 10), BOLD, bg(65, 65, 62))
    o += p(13, 4, "Income", MD, BG)
    o += p(13, 24, f"${6200:>10,.2f}", HI, BG)
    o += p(14, 4, "Expenses", MD, BG)
    o += p(14, 24, f"${3858.80:>10,.2f}", HI, BG)
    o += p(15, 4, "─" * 32, VDK, BG)
    o += p(16, 4, "Net Savings", MD, BG)
    o += p(16, 24, f"${NET_CHANGE:>10,.2f}", AC, BOLD, BG)

    # ── Expenses (right column, rows 11-20) ──
    exp_left = 42
    o += p(11, exp_left, " EXPENSES ", fg(10, 10, 10), BOLD, bg(65, 65, 62))

    # Columns: category(10)  amount(8)  pct(5)  bar(12)
    maxbar = 12
    for i, (name, amt, pct) in enumerate(EXPENSES):
        row = 13 + i
        bw = max(1, int(pct / 31 * maxbar))
        o += p(row, exp_left, f"{name:<10}", MD, BG)
        o += p(row, exp_left + 10, f"${amt:>6,d}", HI, BG)
        o += p(row, exp_left + 18, f"{pct:>3d}%", DK, BG)
        o += p(row, exp_left + 23, "█" * bw, BAR, BG)
        o += p(row, exp_left + 23 + bw, "░" * (maxbar - bw), BARE, BG)

    # Total at bottom-right of expenses block, bright red text
    sep_row = 13 + len(EXPENSES)
    o += p(sep_row, exp_left, "─" * 35, VDK, BG)
    total_row = sep_row + 1
    o += p(total_row, exp_left + 26, "$3,858.80", AC, BOLD, BG)

    # ── Transactions (full width, rows 22-30) ──
    o += p(22, 4, " TRANSACTIONS ", fg(10, 10, 10), BOLD, bg(65, 65, 62))

    o += p(23, 4, "DATE", VDK, BG)
    o += p(23, 12, "PAYEE", VDK, BG)
    o += p(23, 34, "CATEGORY", VDK, BG)
    o += p(23, 54, "AMOUNT", VDK, BG)

    for i, (date, desc, cat, amt) in enumerate(TXNS):
        row = 24 + i
        sign = "+" if amt > 0 else "-"
        clr = AC if amt > 0 else MD
        o += p(row, 4, date, DK, BG)
        o += p(row, 12, desc, clr, BG)
        o += p(row, 34, cat, DK, BG)
        o += p(row, 53, f"{sign}${abs(amt):>8,.2f}", clr, BG)

    # ── Portfolio (2-row square blocks, rows 32-35) ──
    # Each block: row 1 = name (left) + amount (right)
    #             row 2 = bar graph (left) + pct% (right, red text)
    o += p(32, 4, " PORTFOLIO ", fg(10, 10, 10), BOLD, bg(65, 65, 62))

    block_width = 16
    for i, (name, amount, pct_str, spark) in enumerate(PORTFOLIO):
        col = 4 + i * (block_width + 1) + 4*i
        amt_str = f"${amount:>,d}"
        o += p(34, col, name, MD, BG)
        o += p(34, col + block_width - len(amt_str), amt_str, HI, BG)
        o += p(35, col, spark, DK, BG)
        o += p(35, col + block_width - len(pct_str), pct_str, AC, BOLD, BG)

    # ── Bottom status ──
    o += p(40, 4, "3 accounts", DK, BG)
    o += p(40, 62, "q·quit  ?·help", DK, BG)

    o += finish()
    return o


def main():
    name = "18-carbon-v2"
    data = design_carbon_v2()
    path = f"{name}.ansi"
    with open(path, "w") as f:
        f.write(data)
    print(f"Wrote {path}")

    # Display it
    print(data)


if __name__ == "__main__":
    main()
