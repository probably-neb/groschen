#!/usr/bin/env python3
"""Generate design 18: Carbon V3 — combined accounts/portfolio, stacked net worth + cash flow, horizontal expenses."""
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
# Financial data
# ============================================================
HOLDINGS = [
    ("Checking",  4521,    321,   7.6),
    ("Savings",  32100,    100,   0.3),
    ("Stocks",   62450,   7766, 14.2),
    ("Bonds",    18220,    547,  3.1),
    ("Crypto",   10550,    844,  8.7),
]

NET_WORTH = 127842
NET_CHANGE = 2341
NET_PCT = 1.9

EXPENSES = [
    ("HOUSING", 1200, 31), ("FOOD", 642, 17), ("TRANSPORT", 380, 10),
    ("UTILITIES", 246, 6), ("ENTERTAIN", 180, 5), ("HEALTH", 120, 3),
]

EXPENSE_TOTAL = 3858.80
EXPENSE_PREV_DELTA = -312
EXPENSE_PREV_PCT = -7.5
SAVINGS_RATE = 37.8

TXNS = [
    ("04/08", "WHOLE FOODS",   "FOOD",      -84.32),
    ("04/08", "BANK TRANSFER", "TRANSFER",  200.00),
    ("04/07", "AMAZON.COM",    "SHOPPING",  -34.99),
    ("04/07", "SPOTIFY",       "ENTERTAIN", -9.99),
    ("04/07", "STARBUCKS",     "FOOD",      -5.50),
    ("04/05", "SHELL OIL",     "TRANSPORT", -52.00),
    ("04/05", "OLIVE GARDEN",  "FOOD",      -67.80),
]


# ============================================================
# DESIGN 18: CARBON V3
#
# Layout (80x40):
#   Row 2-3:   Header + navigation
#
#   LEFT column (cols 4-39): Combined ACCOUNTS & PORTFOLIO
#     Row 5:     section label
#     Row 7-9:   account entries  (name $amount +$change +pct%)
#     Row 10:    ── portfolio ── separator
#     Row 11-13: portfolio entries (same format, no bars)
#     Row 14:    separator
#     Row 15:    total line
#
#   RIGHT column (cols 42-77): NET WORTH stacked above CASH FLOW
#     Row 5:     NET WORTH label
#     Row 7:     big dollar amount
#     Row 8:     sparkline
#     Row 9:     change + percent
#     Row 11:    CASH FLOW label
#     Row 13:    income
#     Row 14:    expenses
#     Row 15:    separator
#     Row 16:    net savings
#
#   FULL WIDTH: Horizontal expenses
#     Row 18:    EXPENSES label + aggregate stats
#     Row 20-21: 3×2 grid of expense categories
#
#   FULL WIDTH: Transactions
#     Row 23:    TRANSACTIONS label
#     Row 24:    column headers
#     Row 25-31: transaction rows
#
#   Row 40:    Bottom status
# ============================================================

def design_carbon_v3():
    BG = bg(10, 10, 10)
    HI = fg(220, 220, 215)
    AC = fg(210, 85, 70)
    MD = fg(135, 135, 130)
    DK = fg(65, 65, 62)
    VDK = fg(32, 32, 30)
    RAIL = fg(45, 45, 42)

    o = setup(BG)

    # Vertical side rails
    for row in range(1, 41):
        o += p(row, 1, "│", RAIL, BG)
        o += p(row, 80, "│", RAIL, BG)

    # ── Header ──
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

    # ================================================================
    # LEFT COLUMN: Combined ACCOUNTS & PORTFOLIO (cols 4-39)
    # ================================================================
    o += p(5, 4, " HOLDINGS ", fg(10, 10, 10), BOLD, bg(65, 65, 62))

    # Each entry: Name(11)  $Amount(7)  +$Change(7)  +Pct%(6)
    # Positioned: col 4     col 16      col 24       col 33
    def entry(row, name, amt, chg, pct, name_style=MD, bold=False):
        out = ""
        extra = BOLD if bold else ""
        out += p(row, 4, f"{name:<11}", name_style, extra, BG)
        out += p(row, 16, f"${amt:>6,d}", HI, extra, BG)
        chg_s = f"+${chg:,d}" if chg >= 0 else f"-${abs(chg):,d}"
        out += p(row, 24, f"{chg_s:>7}", AC, extra, BG)
        pct_s = f"+{pct:.1f}%" if pct >= 0 else f"-{abs(pct):.1f}%"
        out += p(row, 33, f"{pct_s:>6}", AC, extra, BG)
        return out

    for i, (name, amt, chg, pct) in enumerate(HOLDINGS):
        o += entry(7 + i, name, amt, chg, pct)

    o += p(12, 4, "─" * 35, VDK, BG)

    # Total line
    o += entry(13, "Total", NET_WORTH, NET_CHANGE, NET_PCT, name_style=HI, bold=True)

    # ================================================================
    # RIGHT COLUMN: NET WORTH + CASH FLOW (cols 42-77)
    # ================================================================

    # ── Net Worth ──
    o += p(5, 42, " NET WORTH ", fg(10, 10, 10), BOLD, bg(65, 65, 62))
    o += p(7, 42, f"${NET_WORTH:>,d}.56", HI, BOLD, BG)
    o += p(8, 42, "▁▂▃▃▄▅▅▆▆▇▇█", DK, BG)
    o += p(9, 42, f"+${NET_CHANGE:,d}.20", AC, BOLD, BG)
    o += p(9, 55, f"+{NET_PCT}%", AC, BG)

    # ── Cash Flow ──
    o += p(11, 42, " CASH FLOW ", fg(10, 10, 10), BOLD, bg(65, 65, 62))
    o += p(13, 42, "Income", MD, BG)
    o += p(13, 62, "$  6,200.00", HI, BG)
    o += p(14, 42, "Expenses", MD, BG)
    o += p(14, 62, "$  3,858.80", HI, BG)
    o += p(15, 42, "─" * 34, VDK, BG)
    o += p(16, 42, "Net Savings", MD, BG)
    o += p(16, 62, "$  2,341.20", AC, BOLD, BG)

    # ================================================================
    # FULL WIDTH: EXPENSES (columnar list)
    # ================================================================
    o += p(18, 4, " EXPENSES ", fg(10, 10, 10), BOLD, bg(65, 65, 62))

    # Aggregate stats on the label row
    o += p(18, 16, "$3,858.80", HI, BG)
    o += p(18, 28, "Δ", DK, BG)
    o += p(18, 29, "-$312", AC, BG)
    o += p(18, 35, "(-7.5%)", DK, BG)
    o += p(18, 45, "avg", DK, BG)
    o += p(18, 49, "$643", HI, BG)
    o += p(18, 53, "/cat", DK, BG)
    o += p(18, 60, "savings rate", DK, BG)
    o += p(18, 73, "37.8%", AC, BG)

    # Column headers
    o += p(19, 4, "CATEGORY", VDK, BG)
    o += p(19, 20, "AMOUNT", VDK, BG)
    o += p(19, 32, "PCT", VDK, BG)

    for i, (name, amt, pct) in enumerate(EXPENSES):
        row = 20 + i
        o += p(row, 4, f"{name:<12}", MD, BG)
        o += p(row, 18, f"${amt:>7,d}", HI, BG)
        o += p(row, 31, f"{pct:>3d}%", DK, BG)

    # ================================================================
    # FULL WIDTH: TRANSACTIONS
    # ================================================================
    o += p(27, 4, " TRANSACTIONS ", fg(10, 10, 10), BOLD, bg(65, 65, 62))

    o += p(28, 4, "DATE", VDK, BG)
    o += p(28, 12, "PAYEE", VDK, BG)
    o += p(28, 34, "CATEGORY", VDK, BG)
    o += p(28, 54, "AMOUNT", VDK, BG)

    for i, (date, desc, cat, amt) in enumerate(TXNS):
        row = 29 + i
        sign = "+" if amt > 0 else "-"
        clr = AC if amt > 0 else MD
        o += p(row, 4, date, DK, BG)
        o += p(row, 12, desc, clr, BG)
        o += p(row, 34, cat, DK, BG)
        o += p(row, 53, f"{sign}${abs(amt):>8,.2f}", clr, BG)

    # ── Bottom status ──
    o += p(40, 4, "synced", DK, BG)
    o += p(40, 11, "●", AC, BG)
    o += p(40, 13, "3 accounts", DK, BG)
    o += p(40, 55, "last update: 2 min ago", DK, BG)

    o += finish()
    return o


def main():
    name = "18-carbon-v3"
    data = design_carbon_v3()
    path = f"{name}.ansi"
    with open(path, "w") as f:
        f.write(data)
    print(f"Wrote {path}")
    print(data)


if __name__ == "__main__":
    main()
