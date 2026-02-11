#!/usr/bin/env python3
"""Generate 2 brutal/dense dashboard designs (16-17) for groschen finance app.

Design direction:
- Heavy grid structure with full frames and column dividers
- Minimal single-accent color (strategic highlights only)
- Titles embedded in frame borders
- Keybind hints via highlighted first letters of sub-page names
- Dense, contained, industrial — channeling the aesthetic of 06-10
"""
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


# ============================================================
# DESIGN 16: BUNKER
#
# Heavy box drawing (┏━┓┃┗┛) with full outer frame.
# Three-column grid with vertical dividers for accounts section.
# Muted violet/lavender accent used sparingly on: net worth
# change, positive amounts, keybind first-letters.
# Section titles embedded in heavy horizontal dividers.
# Navigation in the title bar with first-letter highlights.
# Status bar embedded in the bottom frame line.
# Dense, no wasted space.
# ============================================================
def design_bunker():
    BG = bg(4, 4, 8)
    HI = fg(220, 220, 230)
    AC = fg(160, 120, 210)       # muted violet accent
    AC_BG = bg(160, 120, 210)
    MD = fg(130, 130, 140)
    DK = fg(60, 60, 70)
    VDK = fg(30, 30, 38)
    BR = fg(75, 75, 90)          # frame/border
    BAR = fg(100, 75, 140)       # expense bars
    BARE = fg(22, 22, 30)        # bar empty

    o = setup(BG)

    L, R = 1, 80
    inn = R - L - 1  # 78

    # Outer heavy frame
    o += p(1, L, "┏" + "━" * inn + "┓", BR, BG)
    for row in range(2, 40):
        o += p(row, L, "┃", BR, BG)
        o += p(row, R, "┃", BR, BG)
    o += p(40, L, "┗" + "━" * inn + "┛", BR, BG)

    # Title bar row 2: GROSCHEN + nav with first-letter keybinds
    o += p(2, 4, "GROSCHEN", HI, BOLD, BG)

    # Navigation: first letter is accent, rest is dim
    nav = [
        (16, "O", "VERVIEW", True),
        (28, "A", "CCOUNTS", False),
        (40, "B", "UDGET", False),
        (50, "I", "NVEST", False),
        (60, "T", "XNS", False),
        (68, "H", "ISTORY", False),
    ]
    for col, key, rest, active in nav:
        if active:
            o += p(2, col, key, fg(4, 4, 8), BOLD, AC_BG)
            o += p(2, col + 1, rest, AC, BG)
        else:
            o += p(2, col, key, AC, BOLD, BG)
            o += p(2, col + 1, rest, DK, BG)

    # NET WORTH section divider
    title_nw = "━━ NET WORTH "
    pad_nw = inn - len(title_nw) - 10
    o += p(3, L, "┣" + title_nw + "━" * pad_nw + " APR 2025 ┫", BR, BG)
    o += p(3, 4, "NET WORTH", DK, BG)

    o += p(4, 4, "$127,842.56", HI, BOLD, BG)
    o += p(4, 20, "▁▂▃▃▄▅▅▆▆▇▇█", MD, BG)
    o += p(4, 40, "+$2,341.20", AC, BOLD, BG)
    o += p(4, 55, "(+1.9%)", AC, BG)

    # Three-column divider: ACCOUNTS | CASH FLOW | ALLOCATION
    c1, c2 = 27, 53

    seg1_title = "━━ ACCOUNTS "
    seg1_pad = c1 - L - 1 - len(seg1_title)
    seg2_title = "━━ CASH FLOW "
    seg2_pad = c2 - c1 - 1 - len(seg2_title)
    seg3_title = "━━ ALLOCATION "
    seg3_pad = R - c2 - 1 - len(seg3_title)

    o += p(5, L, "┣" + seg1_title + "━" * seg1_pad +
           "┳" + seg2_title + "━" * seg2_pad +
           "┳" + seg3_title + "━" * seg3_pad + "┫", BR, BG)

    for row in range(6, 12):
        o += p(row, c1, "┃", BR, BG)
        o += p(row, c2, "┃", BR, BG)

    # Accounts column
    o += p(6, 4, "CHECKING", MD, BG)
    o += p(6, 17, "$4,521", HI, BG)
    o += p(7, 4, "SAVINGS", MD, BG)
    o += p(7, 16, "$32,100", HI, BG)
    o += p(8, 4, "INVESTMENT", MD, BG)
    o += p(8, 16, "$91,221", HI, BG)
    o += p(9, 4, "━" * 20, VDK, BG)
    o += p(10, 4, "TOTAL", MD, BG)
    o += p(10, 15, "$127,843", AC, BOLD, BG)

    # Cash flow column
    o += p(6, 30, "INCOME", MD, BG)
    o += p(6, 43, "$6,200", AC, BG)
    o += p(7, 30, "EXPENSES", MD, BG)
    o += p(7, 43, "$3,859", HI, BG)
    o += p(8, 30, "━" * 20, VDK, BG)
    o += p(9, 30, "NET", MD, BG)
    o += p(9, 43, "$2,341", AC, BOLD, BG)
    o += p(10, 30, "RATE", DK, BG)
    o += p(10, 43, "37.8%", DK, BG)

    # Allocation column
    alloc_bars = [10, 3, 2, 6]
    for i, ((name, pct), bw) in enumerate(zip(ALLOCS, alloc_bars)):
        row = 6 + i
        o += p(row, 56, "█" * bw, BAR, BG)
        o += p(row, 56 + bw + 1, name, DK, BG)
        o += p(row, 74, f"{pct:>3d}%", MD, BG)

    # Expenses: merge columns back to full width
    line12 = list("━" * inn)
    te = "━━ EXPENSES "
    line12[0:len(te)] = list(te)
    line12[c1 - L - 1] = "┻"
    line12[c2 - L - 1] = "┻"
    rl = " TOTAL: $3,858.80 ━━"
    rs = inn - len(rl)
    line12[rs:rs + len(rl)] = list(rl)
    o += p(12, L, "┣" + "".join(line12) + "┫", BR, BG)

    maxbar = 35
    for i, (name, amt, pct) in enumerate(EXPENSES):
        row = 13 + i
        bw = int(pct / 31 * maxbar)
        o += p(row, 4, f"{name:<12}", MD, BG)
        o += p(row, 17, "█" * bw, BAR, BG)
        o += p(row, 17 + bw, "░" * (maxbar - bw), BARE, BG)
        o += p(row, 55, f"${amt:>7,d}", HI, BG)
        o += p(row, 66, f"{pct:>3d}%", DK, BG)

    # Transactions
    tt = "━━ TRANSACTIONS "
    o += p(19, L, "┣" + tt + "━" * (inn - len(tt)) + "┫", BR, BG)

    o += p(20, 4, "DATE", DK, BG)
    o += p(20, 12, "DESCRIPTION", DK, BG)
    o += p(20, 34, "CATEGORY", DK, BG)
    o += p(20, 54, "AMOUNT", DK, BG)

    for i, (date, desc, cat, amt) in enumerate(TXNS):
        row = 21 + i
        sign = "+" if amt > 0 else "-"
        clr = AC if amt > 0 else MD
        o += p(row, 4, date, DK, BG)
        o += p(row, 12, desc, clr, BG)
        o += p(row, 34, cat, DK, BG)
        o += p(row, 53, f"{sign}${abs(amt):>8,.2f}", clr, BG)

    # Budget section - two columns: BUDGETS | GOALS
    bc = 40
    seg_b1 = "━━ BUDGETS "
    seg_b1_pad = bc - L - 1 - len(seg_b1)
    seg_b2 = "━━ GOALS "
    seg_b2_pad = R - bc - 1 - len(seg_b2)
    o += p(28, L, "┣" + seg_b1 + "━" * seg_b1_pad +
           "┳" + seg_b2 + "━" * seg_b2_pad + "┫", BR, BG)

    for row in range(29, 35):
        o += p(row, bc, "┃", BR, BG)

    # Budget bars (left column)
    budgets = [
        ("HOUSING", 1200, 1200),
        ("FOOD", 642, 700),
        ("TRANSPORT", 380, 400),
        ("UTILITIES", 246, 300),
        ("ENTERTAIN", 180, 250),
    ]
    for i, (name, spent, limit) in enumerate(budgets):
        row = 29 + i
        pct = min(spent / limit, 1.0)
        bar_w = 14
        filled = int(pct * bar_w)
        over = spent >= limit
        o += p(row, 4, f"{name:<11}", MD, BG)
        bar_clr = AC if over else BAR
        o += p(row, 16, "█" * filled, bar_clr, BG)
        o += p(row, 16 + filled, "░" * (bar_w - filled), BARE, BG)
        o += p(row, 31, f"{int(pct*100):>3d}%", AC if over else DK, BG)
        if not over:
            o += p(row, 36, f"${spent:>,d}", DK, BG)

    # Goals (right column)
    goals = [
        ("EMERGENCY FUND", 32100, 50000),
        ("VACATION", 1200, 3000),
        ("NEW CAR", 4800, 20000),
        ("RETIREMENT", 91221, 500000),
    ]
    for i, (name, current, target) in enumerate(goals):
        row = 29 + i
        pct = min(current / target, 1.0)
        bar_w = 12
        filled = int(pct * bar_w)
        o += p(row, 43, f"{name:<15}", MD, BG)
        o += p(row, 59, "█" * filled, BAR, BG)
        o += p(row, 59 + filled, "░" * (bar_w - filled), BARE, BG)
        o += p(row, 72, f"{int(pct*100):>3d}%", DK, BG)

    # Portfolio
    tp = "━━ PORTFOLIO "
    line35 = list("━" * inn)
    line35[0:len(tp)] = list(tp)
    line35[bc - L - 1] = "┻"
    o += p(35, L, "┣" + "".join(line35) + "┫", BR, BG)

    o += p(36, 4, "STOCKS", MD, BG)
    o += p(36, 12, "$62,450", HI, BG)
    o += p(36, 21, "+14.2%", AC, BOLD, BG)
    o += p(36, 30, "BONDS", MD, BG)
    o += p(36, 37, "$18,220", HI, BG)
    o += p(36, 46, "+3.1%", AC, BG)
    o += p(36, 54, "CRYPTO", MD, BG)
    o += p(36, 62, "$10,550", HI, BG)
    o += p(36, 71, "+8.7%", AC, BG)
    o += p(37, 4, "▁▂▃▄▅▆▇", DK, BG)
    o += p(37, 30, "▅▅▆▆▆▇▇", DK, BG)
    o += p(37, 54, "▂▄▅▃▆▇█", DK, BG)

    # Status bar embedded in second-to-last frame line
    o += p(38, L, "┣" + "━" * inn + "┫", BR, BG)

    # Keybind hints in row 39, embedded between frame walls
    o += p(39, 4, "O", AC, BOLD, BG)
    o += p(39, 5, "VERVIEW", DK, BG)
    o += p(39, 15, "A", AC, BOLD, BG)
    o += p(39, 16, "CCTS", DK, BG)
    o += p(39, 23, "B", AC, BOLD, BG)
    o += p(39, 24, "UDGET", DK, BG)
    o += p(39, 32, "I", AC, BOLD, BG)
    o += p(39, 33, "NVEST", DK, BG)
    o += p(39, 41, "T", AC, BOLD, BG)
    o += p(39, 42, "XNS", DK, BG)
    o += p(39, 48, "H", AC, BOLD, BG)
    o += p(39, 49, "ISTORY", DK, BG)

    o += p(39, 60, "●", AC, BG)
    o += p(39, 62, "SYNCED", DK, BG)
    o += p(39, 70, "2m AGO", DK, BG)

    o += finish()
    return o


# ============================================================
# DESIGN 17: PRESS
#
# Double-line frame (╔═╗║╚╝) with dense layout.
# Amber/gold accent on pure black — like 07-phosphor but with
# the new design criteria: no giant content box, titles embedded
# in frame lines, keybind first-letter highlights.
# Two-column layout for accounts/cash-flow with double-line
# vertical dividers. Transactions in a tight table.
# Navigation row with first-letter highlights right below title.
# Bottom frame has status info embedded directly.
# Every section packed tight, no wasted rows.
# ============================================================
def design_press():
    BG = bg(0, 0, 0)
    HI = fg(240, 220, 180)
    AC = fg(220, 165, 50)        # warm amber
    AC_BG = bg(220, 165, 50)
    MD = fg(150, 140, 120)
    DK = fg(70, 65, 55)
    VDK = fg(35, 32, 25)
    BR = fg(90, 80, 55)          # frame/border
    BAR = fg(160, 120, 40)       # expense bars
    BARE = fg(28, 25, 18)        # bar empty

    o = setup(BG)

    L, R = 1, 80
    inn = R - L - 1  # 78

    # Outer double frame
    o += p(1, L, "╔" + "═" * inn + "╗", BR, BG)
    for row in range(2, 40):
        o += p(row, L, "║", BR, BG)
        o += p(row, R, "║", BR, BG)
    o += p(40, L, "╚" + "═" * inn + "╝", BR, BG)

    # Title row — embedded in frame, no separate box
    o += p(1, 4, " GROSCHEN ", HI, BOLD, BG)
    o += p(1, 58, " APR 2025 ", DK, BG)

    # Row 2: Navigation with first-letter keybind highlights
    nav = [
        (4, "O", "VERVIEW", True),
        (16, "A", "CCOUNTS", False),
        (28, "B", "UDGET", False),
        (38, "I", "NVESTMENTS", False),
        (53, "T", "RANSACTIONS", False),
        (69, "H", "ISTORY", False),
    ]
    for col, key, rest, active in nav:
        if active:
            o += p(2, col, key, fg(0, 0, 0), BOLD, AC_BG)
            o += p(2, col + 1, rest, AC, BOLD, BG)
        else:
            o += p(2, col, key, AC, BOLD, BG)
            o += p(2, col + 1, rest, DK, BG)

    # NET WORTH
    title_nw = "═╡ NET WORTH ╞"
    o += p(3, L, "╠" + title_nw + "═" * (inn - len(title_nw)) + "╣", BR, BG)

    o += p(4, 4, "$127,842.56", HI, BOLD, BG)
    o += p(4, 20, "▁▂▃▃▄▅▅▆▆▇▇█", MD, BG)
    o += p(4, 40, "+$2,341.20", AC, BOLD, BG)
    o += p(4, 55, "+1.9%", AC, BG)

    # Two-column: ACCOUNTS | CASH FLOW
    c1 = 40
    seg1 = "═╡ ACCOUNTS ╞" + "═" * (c1 - L - 1 - 14)
    seg2 = "═╡ CASH FLOW ╞" + "═" * (R - c1 - 1 - 15)
    o += p(5, L, "╠" + seg1 + "╦" + seg2 + "╣", BR, BG)

    for row in range(6, 12):
        o += p(row, c1, "║", BR, BG)

    # Accounts
    o += p(6, 4, "CHECKING", MD, BG)
    o += p(6, 15, "·" * 10, VDK, BG)
    o += p(6, 26, "$ 4,521.30", HI, BG)
    o += p(7, 4, "SAVINGS", MD, BG)
    o += p(7, 15, "·" * 10, VDK, BG)
    o += p(7, 26, "$32,100.00", HI, BG)
    o += p(8, 4, "INVESTMENT", MD, BG)
    o += p(8, 15, "·" * 10, VDK, BG)
    o += p(8, 26, "$91,221.26", HI, BG)
    o += p(9, 4, "══════════════════════════════════", VDK, BG)
    o += p(10, 4, "TOTAL", MD, BG)
    o += p(10, 15, "·" * 10, VDK, BG)
    o += p(10, 25, "$127,842.56", AC, BOLD, BG)

    # Cash flow
    o += p(6, 43, "INCOME", MD, BG)
    o += p(6, 55, "·" * 8, VDK, BG)
    o += p(6, 64, "$ 6,200", AC, BG)
    o += p(7, 43, "EXPENSES", MD, BG)
    o += p(7, 55, "·" * 8, VDK, BG)
    o += p(7, 64, "$ 3,859", HI, BG)
    o += p(8, 43, "══════════════════════════════════", VDK, BG)
    o += p(9, 43, "NET SAVINGS", MD, BG)
    o += p(9, 55, "·" * 8, VDK, BG)
    o += p(9, 64, "$ 2,341", AC, BOLD, BG)
    o += p(10, 43, "SAVINGS RATE", DK, BG)
    o += p(10, 64, "  37.8%", DK, BG)

    # Expenses — merge columns
    line12 = list("═" * inn)
    te = "═╡ EXPENSES ╞"
    line12[0:len(te)] = list(te)
    line12[c1 - L - 1] = "╩"
    rl = " TOTAL: $3,858.80 ══"
    rs = inn - len(rl)
    line12[rs:rs + len(rl)] = list(rl)
    o += p(12, L, "╠" + "".join(line12) + "╣", BR, BG)

    maxbar = 30
    for i, (name, amt, pct) in enumerate(EXPENSES):
        row = 13 + i
        bw = int(pct / 31 * maxbar)
        o += p(row, 4, f"{name:<12}", MD, BG)
        o += p(row, 17, "█" * bw, BAR, BG)
        o += p(row, 17 + bw, "░" * (maxbar - bw), BARE, BG)
        o += p(row, 50, f"${amt:>7,d}", HI, BG)
        o += p(row, 60, f"{pct:>3d}%", DK, BG)

        # Over-budget indicator
        if pct >= 30:
            o += p(row, 66, "██", AC, BG)

    # Transactions
    tt = "═╡ TRANSACTIONS ╞"
    o += p(19, L, "╠" + tt + "═" * (inn - len(tt)) + "╣", BR, BG)

    o += p(20, 4, "DATE", DK, ULINE, BG)
    o += p(20, 12, "PAYEE", DK, ULINE, BG)
    o += p(20, 34, "CATEGORY", DK, ULINE, BG)
    o += p(20, 54, "AMOUNT", DK, ULINE, BG)

    for i, (date, desc, cat, amt) in enumerate(TXNS):
        row = 21 + i
        sign = "+" if amt > 0 else "-"
        clr = AC if amt > 0 else MD
        o += p(row, 4, date, DK, BG)
        o += p(row, 12, desc, clr, BG)
        o += p(row, 34, cat, DK, BG)
        o += p(row, 53, f"{sign}${abs(amt):>8,.2f}", clr, BG)

    # Allocation + Portfolio — two columns
    ac = 40
    seg_a1 = "═╡ ALLOCATION ╞" + "═" * (ac - L - 1 - 16)
    seg_a2 = "═╡ PORTFOLIO ╞" + "═" * (R - ac - 1 - 15)
    o += p(28, L, "╠" + seg_a1 + "╦" + seg_a2 + "╣", BR, BG)

    for row in range(29, 37):
        o += p(row, ac, "║", BR, BG)

    # Allocation (left)
    alloc_bars = [16, 5, 3, 10]
    for i, ((name, pct), bw) in enumerate(zip(ALLOCS, alloc_bars)):
        row = 29 + i
        o += p(row, 4, "█" * bw, BAR, BG)
        o += p(row, 4 + bw + 1, name, DK, BG)
        o += p(row, 30, f"${[62450, 18220, 10550, 36622][i]:>7,d}", HI, BG)

    o += p(34, 4, "TOTAL INVESTED", DK, BG)
    o += p(34, 29, f"${127842:>8,d}", AC, BOLD, BG)

    # Portfolio (right)
    portfolio = [
        ("AAPL", 15230, 12.2, True),
        ("VTSAX", 28400, 8.5, True),
        ("BTC", 10550, 22.1, True),
        ("BONDS", 18220, 3.1, True),
        ("VOO", 18800, 11.4, True),
    ]
    o += p(29, 43, "SYMBOL", DK, BG)
    o += p(29, 55, "VALUE", DK, BG)
    o += p(29, 68, "RETURN", DK, BG)
    for i, (sym, val, ret, up) in enumerate(portfolio):
        row = 30 + i
        o += p(row, 43, sym, MD, BG)
        o += p(row, 53, f"${val:>8,d}", HI, BG)
        o += p(row, 67, f"+{ret:>5.1f}%", AC, BG)

    o += p(36, 43, "═" * 35, VDK, BG)

    # Status bar — embedded in bottom frame
    o += p(38, L, "╠" + "═" * inn + "╣", BR, BG)

    # Row 39: keybind hints + status
    o += p(39, 3, "O", AC, BOLD, BG)
    o += p(39, 4, "verview", DK, BG)
    o += p(39, 13, "A", AC, BOLD, BG)
    o += p(39, 14, "ccts", DK, BG)
    o += p(39, 20, "B", AC, BOLD, BG)
    o += p(39, 21, "udget", DK, BG)
    o += p(39, 28, "I", AC, BOLD, BG)
    o += p(39, 29, "nvest", DK, BG)
    o += p(39, 36, "T", AC, BOLD, BG)
    o += p(39, 37, "xns", DK, BG)
    o += p(39, 42, "H", AC, BOLD, BG)
    o += p(39, 43, "istory", DK, BG)

    o += p(39, 55, "●", AC, BG)
    o += p(39, 57, "SYNCED", DK, BG)
    o += p(39, 66, "2 MIN AGO", DK, BG)

    o += finish()
    return o


# ============================================================
# MAIN
# ============================================================
def main():
    designs = [
        ("16-bunker.ansi", design_bunker, "Bunker (Heavy Grid, Violet)"),
        ("17-press.ansi",  design_press,  "Press (Double Frame, Amber)"),
    ]
    outdir = os.path.dirname(os.path.abspath(__file__))
    for fname, fn, label in designs:
        path = os.path.join(outdir, fname)
        with open(path, 'w') as f:
            f.write(fn())
        print(f"  ✓ {fname:<20} {label}")


if __name__ == "__main__":
    main()
