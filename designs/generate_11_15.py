#!/usr/bin/env python3
"""Generate 5 new dashboard designs (11-15) for groschen finance app.

Design direction:
- Minimal color aesthetic (strategic single-accent highlights)
- Clean top/bottom bars (no giant surrounding box required)
- Content is the focus, not UI chrome
- Keybind hints via highlighted first letters of sub-page names
- Based on the style of designs 06 (Forge), 07 (Phosphor), 10 (Vault)
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
# DESIGN 11: LEDGER
#
# No outer box at all. Content floats on black.
# Thin horizontal rules with embedded section names.
# Warm amber/gold accent for key numbers and first-letter keybinds.
# Navigation as highlighted first letters: [O]verview [A]ccounts etc.
# Clean ledger-book feel with dot leaders.
# ============================================================
def design_ledger():
    BG = bg(0, 0, 0)
    HI = fg(255, 255, 255)
    AC = fg(220, 170, 60)       # warm gold accent
    AC_BG = bg(220, 170, 60)    # for inverse first-letter
    MD = fg(150, 150, 150)
    DK = fg(70, 70, 70)
    VDK = fg(40, 40, 40)
    BAR = fg(140, 110, 30)
    BARE = fg(30, 28, 20)

    o = setup(BG)

    # Title line - floating, no box
    o += p(2, 4, "GROSCHEN", AC, BOLD, BG)
    o += p(2, 44, "FINANCIAL OVERVIEW", DK, BG)
    o += p(2, 72, "APR 2025", DK, BG)

    # Navigation with highlighted first letters
    # The first letter is rendered inverse (accent bg, black fg)
    nav_items = [
        (4, "O", "verview", True),
        (17, "A", "ccounts", False),
        (29, "B", "udget", False),
        (39, "I", "nvestments", False),
        (54, "T", "ransactions", False),
        (70, "H", "istory", False),
    ]
    for col, first, rest, active in nav_items:
        if active:
            o += p(3, col, first, fg(0, 0, 0), BOLD, AC_BG)
            o += p(3, col + 1, rest, AC, BOLD, BG)
        else:
            o += p(3, col, first, AC, BOLD, BG)
            o += p(3, col + 1, rest, DK, BG)

    # Net Worth section
    o += p(5, 4, "net worth", DK, BG)
    o += p(5, 14, "─" * 63, VDK, BG)

    o += p(7, 4, "$127,842.56", HI, BOLD, BG)
    o += p(7, 20, "▁▂▃▃▄▅▅▆▆▇▇█", MD, BG)
    o += p(7, 40, "+$2,341.20", AC, BG)
    o += p(7, 55, "+1.9% this month", DK, BG)

    # Accounts + Cash Flow side by side
    o += p(9, 4, "accounts", DK, BG)
    o += p(9, 13, "─" * 26, VDK, BG)
    o += p(9, 42, "cash flow", DK, BG)
    o += p(9, 52, "─" * 25, VDK, BG)

    o += p(11, 4, "Checking", MD, BG)
    dot1 = "·" * 14
    o += p(11, 13, dot1, VDK, BG)
    o += p(11, 28, "$ 4,521.30", HI, BG)

    o += p(12, 4, "Savings", MD, BG)
    o += p(12, 12, "·" * 15, VDK, BG)
    o += p(12, 28, "$32,100.00", HI, BG)

    o += p(13, 4, "Investment", MD, BG)
    o += p(13, 15, "·" * 12, VDK, BG)
    o += p(13, 28, "$91,221.26", HI, BG)

    o += p(15, 4, "Total", MD, BG)
    o += p(15, 10, "·" * 17, VDK, BG)
    o += p(15, 27, "$127,842.56", AC, BOLD, BG)

    # Cash flow
    o += p(11, 42, "Income", MD, BG)
    o += p(11, 49, "·" * 14, VDK, BG)
    o += p(11, 64, "$ 6,200.00", AC, BG)

    o += p(12, 42, "Expenses", MD, BG)
    o += p(12, 51, "·" * 12, VDK, BG)
    o += p(12, 64, "$ 3,858.80", HI, BG)

    o += p(13, 42, "─" * 34, VDK, BG)

    o += p(14, 42, "Net Savings", MD, BG)
    o += p(14, 54, "·" * 9, VDK, BG)
    o += p(14, 64, "$ 2,341.20", AC, BOLD, BG)

    # Expenses
    o += p(17, 4, "expenses", DK, BG)
    o += p(17, 13, "─" * 43, VDK, BG)
    o += p(17, 59, "total: $3,858.80", DK, BG)

    maxbar = 32
    for i, (name, amt, pct) in enumerate(EXPENSES):
        row = 19 + i
        bw = int(pct / 31 * maxbar)
        o += p(row, 4, f"{name.lower():<12}", MD, BG)
        o += p(row, 17, "█" * bw, BAR, BG)
        o += p(row, 17 + bw, "░" * (maxbar - bw), BARE, BG)
        o += p(row, 52, f"${amt:>7,d}", HI, BG)
        o += p(row, 63, f"{pct:>3d}%", DK, BG)

    # Transactions
    o += p(26, 4, "transactions", DK, BG)
    o += p(26, 17, "─" * 60, VDK, BG)

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

    # Portfolio
    o += p(37, 4, "portfolio", DK, BG)
    o += p(37, 14, "─" * 63, VDK, BG)

    o += p(38, 4, "Stocks $62,450", MD, BG)
    o += p(38, 20, "+14.2%", AC, BOLD, BG)
    o += p(38, 30, "Bonds $18,220", MD, BG)
    o += p(38, 45, "+3.1%", AC, BG)
    o += p(38, 54, "Crypto $10,550", MD, BG)
    o += p(38, 70, "+8.7%", AC, BG)

    # Bottom status - just floating text
    o += p(40, 4, "3 accounts synced", DK, BG)
    o += p(40, 30, "·", VDK, BG)
    o += p(40, 35, "last update: 2 min ago", DK, BG)
    o += p(40, 72, "● live", AC, BG)

    o += finish()
    return o


# ============================================================
# DESIGN 12: SIGNAL
#
# Top and bottom single horizontal lines only (no side borders).
# Title and keybinds embedded directly in the top/bottom rules.
# Single teal/cyan accent for positive values and keybind letters.
# Section dividers are dim labels with short underlines.
# Airy, signal-processing aesthetic.
# ============================================================
def design_signal():
    BG = bg(10, 12, 14)
    HI = fg(230, 235, 240)
    AC = fg(80, 200, 180)       # teal accent
    AC_BG = bg(80, 200, 180)
    MD = fg(140, 150, 155)
    DK = fg(70, 75, 80)
    VDK = fg(38, 42, 46)
    BAR = fg(50, 130, 115)
    BARE = fg(25, 35, 32)

    o = setup(BG)

    # Top rule with embedded title
    top = list("─" * 80)
    title = "─ GROSCHEN "
    top[0:len(title)] = list(title)
    subtitle = " Financial Overview ─"
    top[30:30+len(subtitle)] = list(subtitle)
    date_str = " Apr 2025 ─"
    top[80 - len(date_str):80] = list(date_str)
    o += p(1, 1, "".join(top), VDK, BG)
    o += p(1, 3, "GROSCHEN", HI, BOLD, BG)
    o += p(1, 31, "Financial Overview", DK, BG)
    o += p(1, 71, "Apr 2025", DK, BG)

    # Navigation with highlighted first letters (bracketed style)
    nav_items = [
        (4, "O", "verview", True),
        (16, "A", "ccounts", False),
        (28, "B", "udget", False),
        (38, "I", "nvestments", False),
        (53, "T", "ransactions", False),
    ]
    for col, first, rest, active in nav_items:
        if active:
            o += p(3, col, first, fg(10, 12, 14), BOLD, AC_BG)
            o += p(3, col + 1, rest, AC, BG)
            o += p(3, col + len(rest) + 1, " ◂", AC, BG)
        else:
            o += p(3, col, first, AC, BG)
            o += p(3, col + 1, rest, DK, BG)

    # Net Worth
    o += p(5, 4, "NET WORTH", DK, BG)
    o += p(5, 14, "·" * 3, VDK, BG)

    o += p(7, 4, "$127,842.56", HI, BOLD, BG)
    o += p(7, 20, "▁▂▃▃▄▅▅▆▆▇▇█", MD, BG)
    o += p(7, 40, "+$2,341.20", AC, BOLD, BG)
    o += p(7, 55, "+1.9%", AC, BG)

    # Accounts | Cash Flow (two columns, no boxes)
    o += p(9, 4, "ACCOUNTS", DK, BG)
    o += p(9, 42, "CASH FLOW", DK, BG)

    for i, (name, val) in enumerate(ACCOUNTS):
        row = 11 + i
        o += p(row, 4, name.capitalize(), MD, BG)
        o += p(row, 24, f"${val:>10,.2f}", HI, BG)

    o += p(14, 4, "─" * 34, VDK, BG)
    o += p(15, 4, "Total", MD, BG)
    o += p(15, 22, f"${NET_WORTH:>12,.2f}", AC, BOLD, BG)

    # Cash flow
    o += p(11, 42, "Income", MD, BG)
    o += p(11, 62, f"${6200:>10,.2f}", AC, BG)
    o += p(12, 42, "Expenses", MD, BG)
    o += p(12, 62, f"${3858.80:>10,.2f}", HI, BG)
    o += p(13, 42, "─" * 34, VDK, BG)
    o += p(14, 42, "Net", MD, BG)
    o += p(14, 62, f"${NET_CHANGE:>10,.2f}", AC, BOLD, BG)

    # Expenses
    o += p(17, 4, "EXPENSES", DK, BG)
    o += p(17, 62, "total $3,858.80", DK, BG)

    maxbar = 35
    for i, (name, amt, pct) in enumerate(EXPENSES):
        row = 19 + i
        bw = int(pct / 31 * maxbar)
        o += p(row, 4, f"{name:<12}", MD, BG)
        o += p(row, 17, "█" * bw, BAR, BG)
        o += p(row, 17 + bw, "░" * (maxbar - bw), BARE, BG)
        o += p(row, 55, f"${amt:>7,d}", HI, BG)
        o += p(row, 66, f"{pct:>3d}%", DK, BG)

    # Transactions
    o += p(26, 4, "TRANSACTIONS", DK, BG)

    o += p(28, 4, "date", VDK, BG)
    o += p(28, 12, "payee", VDK, BG)
    o += p(28, 34, "category", VDK, BG)
    o += p(28, 54, "amount", VDK, BG)

    for i, (date, desc, cat, amt) in enumerate(TXNS):
        row = 29 + i
        sign = "+" if amt > 0 else "-"
        clr = AC if amt > 0 else MD
        o += p(row, 4, date, DK, BG)
        o += p(row, 12, desc, clr, BG)
        o += p(row, 34, cat, DK, BG)
        o += p(row, 53, f"{sign}${abs(amt):>8,.2f}", clr, BG)

    # Portfolio
    o += p(37, 4, "PORTFOLIO", DK, BG)

    o += p(38, 4, "Stocks $62,450", MD, BG)
    o += p(38, 20, "+14.2%", AC, BOLD, BG)
    o += p(38, 30, "Bonds $18,220", MD, BG)
    o += p(38, 45, "+3.1%", AC, BG)
    o += p(38, 54, "Crypto $10,550", MD, BG)
    o += p(38, 70, "+8.7%", AC, BG)

    # Bottom rule with keybind hints
    bot = list("─" * 80)
    o += p(40, 1, "".join(bot), VDK, BG)
    # Keybinds embedded in bottom rule
    hints = [
        (3, "o", "verview"),
        (15, "a", "ccounts"),
        (27, "b", "udget"),
        (37, "i", "nvest"),
        (47, "t", "xns"),
        (55, "?", "help"),
        (65, "q", "uit"),
    ]
    for col, key, label in hints:
        o += p(40, col, key, AC, BOLD, BG)
        o += p(40, col + 1, "·" + label, DK, BG)

    o += finish()
    return o


# ============================================================
# DESIGN 13: INDEX
#
# Double-line header bar at top, single-line footer.
# No side borders at all. Tab-style navigation with [X] brackets.
# Sections separated by centered dot dividers.
# Soft blue accent (#6699cc) for highlights.
# Newspaper/financial-index feel.
# ============================================================
def design_index():
    BG = bg(5, 5, 10)
    HI = fg(225, 230, 240)
    AC = fg(100, 150, 210)      # soft blue
    AC_BG = bg(100, 150, 210)
    MD = fg(140, 145, 155)
    DK = fg(70, 72, 80)
    VDK = fg(35, 36, 42)
    BAR = fg(60, 95, 140)
    BARE = fg(25, 28, 38)

    o = setup(BG)

    # Double-line header
    o += p(1, 1, "═" * 80, DK, BG)
    o += p(2, 3, "GROSCHEN", HI, BOLD, BG)
    o += p(2, 36, "DASHBOARD", DK, BG)
    o += p(2, 72, "APR 2025", DK, BG)
    o += p(3, 1, "═" * 80, DK, BG)

    # Tab navigation - [X] style with first letter as shortcut key
    tabs = [
        (3, "O", "VERVIEW", True),
        (16, "A", "CCOUNTS", False),
        (29, "B", "UDGET", False),
        (40, "I", "NVEST", False),
        (51, "T", "XACTIONS", False),
        (65, "H", "ISTORY", False),
    ]
    for col, key, rest, active in tabs:
        if active:
            o += p(4, col, "[", DK, BG)
            o += p(4, col + 1, key, fg(5, 5, 10), BOLD, AC_BG)
            o += p(4, col + 2, "]", DK, BG)
            o += p(4, col + 3, rest, AC, BG)
        else:
            o += p(4, col, "[", VDK, BG)
            o += p(4, col + 1, key, AC, BG)
            o += p(4, col + 2, "]", VDK, BG)
            o += p(4, col + 3, rest, DK, BG)

    # Net Worth
    o += p(6, 30, "· · · · · · · · · ·", VDK, BG)
    o += p(6, 4, "NET WORTH", DK, BG)

    o += p(8, 4, "$127,842.56", HI, BOLD, BG)
    o += p(8, 20, "▁▂▃▃▄▅▅▆▆▇▇█", MD, BG)
    o += p(8, 40, "+$2,341.20", AC, BOLD, BG)
    o += p(8, 55, "(+1.9%)", AC, BG)

    # Accounts | Cash Flow | Allocation - three columns
    c1, c2 = 28, 54
    o += p(10, 4, "ACCOUNTS", DK, BG)
    o += p(10, c1 + 2, "CASH FLOW", DK, BG)
    o += p(10, c2 + 2, "ALLOCATION", DK, BG)

    o += p(11, 4, "─" * (c1 - 5), VDK, BG)
    o += p(11, c1 + 2, "─" * (c2 - c1 - 3), VDK, BG)
    o += p(11, c2 + 2, "─" * (78 - c2 - 1), VDK, BG)

    o += p(12, 4, "Checking", MD, BG)
    o += p(12, 18, "$4,521", HI, BG)
    o += p(13, 4, "Savings", MD, BG)
    o += p(13, 17, "$32,100", HI, BG)
    o += p(14, 4, "Investment", MD, BG)
    o += p(14, 17, "$91,221", HI, BG)

    o += p(12, c1 + 2, "Income", MD, BG)
    o += p(12, c1 + 15, "$6,200", AC, BG)
    o += p(13, c1 + 2, "Expenses", MD, BG)
    o += p(13, c1 + 15, "$3,859", HI, BG)
    o += p(14, c1 + 2, "─" * 22, VDK, BG)
    o += p(15, c1 + 2, "Net", MD, BG)
    o += p(15, c1 + 15, "$2,341", AC, BOLD, BG)

    alloc_bars = [10, 3, 2, 6]
    for i, ((name, pct), bw) in enumerate(zip(ALLOCS, alloc_bars)):
        row = 12 + i
        o += p(row, c2 + 2, "█" * bw, BAR, BG)
        o += p(row, c2 + 2 + bw + 1, name, DK, BG)
        o += p(row, 75, f"{pct:>3d}%", MD, BG)

    # Expenses
    o += p(17, 30, "· · · · · · · · · ·", VDK, BG)
    o += p(17, 4, "EXPENSES", DK, BG)
    o += p(17, 62, "$3,858.80 total", DK, BG)

    maxbar = 32
    for i, (name, amt, pct) in enumerate(EXPENSES):
        row = 19 + i
        bw = int(pct / 31 * maxbar)
        o += p(row, 4, f"{name:<12}", MD, BG)
        o += p(row, 17, "█" * bw, BAR, BG)
        o += p(row, 17 + bw, "░" * (maxbar - bw), BARE, BG)
        o += p(row, 52, f"${amt:>7,d}", HI, BG)
        o += p(row, 63, f"{pct:>3d}%", DK, BG)

    # Transactions
    o += p(26, 30, "· · · · · · · · · ·", VDK, BG)
    o += p(26, 4, "TRANSACTIONS", DK, BG)

    o += p(27, 4, "DATE", VDK, BG)
    o += p(27, 12, "PAYEE", VDK, BG)
    o += p(27, 34, "CATEGORY", VDK, BG)
    o += p(27, 54, "AMOUNT", VDK, BG)

    for i, (date, desc, cat, amt) in enumerate(TXNS):
        row = 28 + i
        sign = "+" if amt > 0 else "-"
        clr = AC if amt > 0 else MD
        o += p(row, 4, date, DK, BG)
        o += p(row, 12, desc, clr, BG)
        o += p(row, 34, cat, DK, BG)
        o += p(row, 53, f"{sign}${abs(amt):>8,.2f}", clr, BG)

    # Portfolio
    o += p(36, 30, "· · · · · · · · · ·", VDK, BG)
    o += p(36, 4, "PORTFOLIO", DK, BG)

    o += p(37, 4, "Stocks $62,450", MD, BG)
    o += p(37, 20, "+14.2%", AC, BOLD, BG)
    o += p(37, 30, "Bonds $18,220", MD, BG)
    o += p(37, 45, "+3.1%", AC, BG)
    o += p(37, 54, "Crypto $10,550", MD, BG)
    o += p(37, 70, "+8.7%", AC, BG)
    o += p(38, 4, "▁▂▃▄▅▆▇", DK, BG)
    o += p(38, 30, "▅▅▆▆▆▇▇", DK, BG)
    o += p(38, 54, "▂▄▅▃▆▇█", DK, BG)

    # Footer
    o += p(40, 1, "─" * 80, DK, BG)
    # Keybinds in footer
    o += p(40, 3, "[", VDK, BG)
    o += p(40, 4, "o", AC, BG)
    o += p(40, 5, "]verview", DK, BG)
    o += p(40, 16, "[", VDK, BG)
    o += p(40, 17, "a", AC, BG)
    o += p(40, 18, "]ccts", DK, BG)
    o += p(40, 26, "[", VDK, BG)
    o += p(40, 27, "b", AC, BG)
    o += p(40, 28, "]udget", DK, BG)
    o += p(40, 37, "[", VDK, BG)
    o += p(40, 38, "i", AC, BG)
    o += p(40, 39, "]nvest", DK, BG)
    o += p(40, 48, "[", VDK, BG)
    o += p(40, 49, "t", AC, BG)
    o += p(40, 50, "]xns", DK, BG)

    o += p(40, 60, "synced", DK, BG)
    o += p(40, 58, "●", AC, BG)
    o += p(40, 70, "2 min ago", DK, BG)

    o += finish()
    return o


# ============================================================
# DESIGN 14: CARBON
#
# Thin vertical side rails only (no horizontal top/bottom box).
# Title floats at top. Very dark background (#0a0a0a).
# Warm coral/red accent (#d05545) used extremely sparingly:
#   only for net worth change, positive keybind letters, and
#   a tiny bullet for the active page.
# Keybinds shown as "a·accounts" with first letter bold+colored.
# Section headers are reverse-video short tags.
# ============================================================
def design_carbon():
    BG = bg(10, 10, 10)
    HI = fg(220, 220, 215)
    AC = fg(210, 85, 70)        # warm coral
    AC_BG = bg(210, 85, 70)
    MD = fg(135, 135, 130)
    DK = fg(65, 65, 62)
    VDK = fg(32, 32, 30)
    BAR = fg(150, 60, 50)
    BARE = fg(30, 20, 18)
    RAIL = fg(45, 45, 42)

    o = setup(BG)

    # Vertical side rails only - no top/bottom horizontal lines
    for row in range(1, 41):
        o += p(row, 1, "│", RAIL, BG)
        o += p(row, 80, "│", RAIL, BG)

    # Title - floating at top
    o += p(2, 4, "GROSCHEN", HI, BOLD, BG)
    o += p(2, 72, "APR 2025", DK, BG)

    # Navigation: a·accounts style with first letter colored
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

    # Net Worth - reverse-video tag
    o += p(5, 4, " NET WORTH ", fg(10, 10, 10), BOLD, bg(65, 65, 62))
    o += p(7, 4, "$127,842.56", HI, BOLD, BG)
    o += p(7, 20, "▁▂▃▃▄▅▅▆▆▇▇█", DK, BG)
    o += p(7, 40, "+$2,341.20", AC, BOLD, BG)
    o += p(7, 55, "+1.9%", AC, BG)

    # Accounts
    o += p(9, 4, " ACCOUNTS ", fg(10, 10, 10), BOLD, bg(65, 65, 62))
    o += p(9, 42, " CASH FLOW ", fg(10, 10, 10), BOLD, bg(65, 65, 62))

    o += p(11, 4, "Checking", MD, BG)
    o += p(11, 24, f"${4521.30:>10,.2f}", HI, BG)
    o += p(12, 4, "Savings", MD, BG)
    o += p(12, 24, f"${32100:>10,.2f}", HI, BG)
    o += p(13, 4, "Investment", MD, BG)
    o += p(13, 24, f"${91221.26:>10,.2f}", HI, BG)
    o += p(14, 4, "─" * 32, VDK, BG)
    o += p(15, 4, "Total", MD, BG)
    o += p(15, 23, f"${NET_WORTH:>11,.2f}", AC, BOLD, BG)

    o += p(11, 42, "Income", MD, BG)
    o += p(11, 62, f"${6200:>10,.2f}", HI, BG)
    o += p(12, 42, "Expenses", MD, BG)
    o += p(12, 62, f"${3858.80:>10,.2f}", HI, BG)
    o += p(13, 42, "─" * 34, VDK, BG)
    o += p(14, 42, "Net Savings", MD, BG)
    o += p(14, 62, f"${NET_CHANGE:>10,.2f}", AC, BOLD, BG)

    # Expenses
    o += p(17, 4, " EXPENSES ", fg(10, 10, 10), BOLD, bg(65, 65, 62))
    o += p(17, 58, "total $3,858.80", DK, BG)

    maxbar = 32
    for i, (name, amt, pct) in enumerate(EXPENSES):
        row = 19 + i
        bw = int(pct / 31 * maxbar)
        o += p(row, 4, f"{name:<12}", MD, BG)
        o += p(row, 17, "█" * bw, BAR, BG)
        o += p(row, 17 + bw, "░" * (maxbar - bw), BARE, BG)
        o += p(row, 52, f"${amt:>7,d}", HI, BG)
        o += p(row, 63, f"{pct:>3d}%", DK, BG)

    # Transactions
    o += p(26, 4, " TRANSACTIONS ", fg(10, 10, 10), BOLD, bg(65, 65, 62))

    o += p(27, 4, "DATE", VDK, BG)
    o += p(27, 12, "PAYEE", VDK, BG)
    o += p(27, 34, "CATEGORY", VDK, BG)
    o += p(27, 54, "AMOUNT", VDK, BG)

    for i, (date, desc, cat, amt) in enumerate(TXNS):
        row = 28 + i
        sign = "+" if amt > 0 else "-"
        clr = AC if amt > 0 else MD
        o += p(row, 4, date, DK, BG)
        o += p(row, 12, desc, clr, BG)
        o += p(row, 34, cat, DK, BG)
        o += p(row, 53, f"{sign}${abs(amt):>8,.2f}", clr, BG)

    # Portfolio
    o += p(36, 4, " PORTFOLIO ", fg(10, 10, 10), BOLD, bg(65, 65, 62))

    o += p(37, 4, "Stocks $62,450", MD, BG)
    o += p(37, 20, "+14.2%", AC, BOLD, BG)
    o += p(37, 30, "Bonds $18,220", MD, BG)
    o += p(37, 45, "+3.1%", AC, BG)
    o += p(37, 54, "Crypto $10,550", MD, BG)
    o += p(37, 70, "+8.7%", AC, BG)
    o += p(38, 4, "▁▂▃▄▅▆▇", DK, BG)
    o += p(38, 30, "▅▅▆▆▆▇▇", DK, BG)
    o += p(38, 54, "▂▄▅▃▆▇█", DK, BG)

    # Bottom status - just text between the rails
    o += p(40, 4, "synced", DK, BG)
    o += p(40, 11, "●", AC, BG)
    o += p(40, 13, "3 accounts", DK, BG)
    o += p(40, 55, "last update: 2 min ago", DK, BG)

    o += finish()
    return o


# ============================================================
# DESIGN 15: TRACE
#
# Corner crop marks only (short lines at corners, no continuous
# border). Very airy and open.
# Title centered at top, status at bottom.
# Navigation: first letters bold+underline in accent color.
# Section headers lowercase with thin extending rule.
# Muted green accent (#7a9e7a) for positive values and keybinds.
# ============================================================
def design_trace():
    BG = bg(6, 8, 6)
    HI = fg(215, 225, 215)
    AC = fg(120, 170, 120)      # muted sage green
    AC_BG = bg(120, 170, 120)
    MD = fg(130, 140, 130)
    DK = fg(60, 68, 60)
    VDK = fg(30, 36, 30)
    BAR = fg(70, 110, 70)
    BARE = fg(22, 30, 22)
    MARK = fg(50, 60, 50)

    o = setup(BG)

    # Corner crop marks - 4 corners with short lines
    mark_len = 6
    o += p(1, 1, "┌" + "─" * mark_len, MARK, BG)
    o += p(2, 1, "│", MARK, BG)
    o += p(3, 1, "│", MARK, BG)

    o += p(1, 80 - mark_len, "─" * mark_len + "┐", MARK, BG)
    o += p(2, 80, "│", MARK, BG)
    o += p(3, 80, "│", MARK, BG)

    o += p(38, 1, "│", MARK, BG)
    o += p(39, 1, "│", MARK, BG)
    o += p(40, 1, "└" + "─" * mark_len, MARK, BG)

    o += p(38, 80, "│", MARK, BG)
    o += p(39, 80, "│", MARK, BG)
    o += p(40, 80 - mark_len, "─" * mark_len + "┘", MARK, BG)

    # Title - centered
    o += p(1, 11, "GROSCHEN", HI, BOLD, BG)
    o += p(1, 40, "·", VDK, BG)
    o += p(1, 42, "Financial Overview", DK, BG)
    o += p(1, 72, "Apr 2025", DK, BG)

    # Navigation with underlined first letters
    nav_items = [
        (4, "O", "verview", True),
        (16, "A", "ccounts", False),
        (28, "B", "udget", False),
        (38, "I", "nvestments", False),
        (53, "T", "ransactions", False),
        (69, "H", "istory", False),
    ]
    for col, first, rest, active in nav_items:
        if active:
            o += p(3, col, first, AC, BOLD, ULINE, BG)
            o += p(3, col + 1, rest, AC, BG)
            o += p(3, col + len(rest) + 2, "◂", AC, BG)
        else:
            o += p(3, col, first, AC, ULINE, BG)
            o += p(3, col + 1, rest, DK, BG)

    # Net Worth
    o += p(5, 4, "net worth", DK, BG)
    o += p(5, 14, "─" * 62, VDK, BG)

    o += p(7, 4, "$127,842.56", HI, BOLD, BG)
    o += p(7, 20, "▁▂▃▃▄▅▅▆▆▇▇█", MD, BG)
    o += p(7, 40, "+$2,341.20", AC, BOLD, BG)
    o += p(7, 56, "+1.9%", AC, BG)

    # Accounts | Cash Flow (two columns, thin divider)
    o += p(9, 4, "accounts", DK, BG)
    o += p(9, 13, "─" * 25, VDK, BG)
    o += p(9, 42, "cash flow", DK, BG)
    o += p(9, 52, "─" * 24, VDK, BG)

    # Thin vertical separator
    for row in range(10, 16):
        o += p(row, 39, "·", VDK, BG)

    o += p(11, 4, "Checking", MD, BG)
    o += p(11, 24, f"${4521.30:>10,.2f}", HI, BG)
    o += p(12, 4, "Savings", MD, BG)
    o += p(12, 24, f"${32100:>10,.2f}", HI, BG)
    o += p(13, 4, "Investment", MD, BG)
    o += p(13, 24, f"${91221.26:>10,.2f}", HI, BG)

    o += p(15, 4, "total", MD, BG)
    o += p(15, 23, f"${NET_WORTH:>11,.2f}", AC, BOLD, BG)

    o += p(11, 42, "Income", MD, BG)
    o += p(11, 64, f"${6200:>10,.2f}", AC, BG)
    o += p(12, 42, "Expenses", MD, BG)
    o += p(12, 64, f"${3858.80:>10,.2f}", HI, BG)
    o += p(13, 42, "─" * 34, VDK, BG)
    o += p(14, 42, "Net Savings", MD, BG)
    o += p(14, 64, f"${NET_CHANGE:>10,.2f}", AC, BOLD, BG)

    # Expenses
    o += p(17, 4, "expenses", DK, BG)
    o += p(17, 13, "─" * 42, VDK, BG)
    o += p(17, 58, "total $3,858.80", DK, BG)

    maxbar = 32
    for i, (name, amt, pct) in enumerate(EXPENSES):
        row = 19 + i
        bw = int(pct / 31 * maxbar)
        o += p(row, 4, f"{name.lower():<12}", MD, BG)
        o += p(row, 17, "█" * bw, BAR, BG)
        o += p(row, 17 + bw, "░" * (maxbar - bw), BARE, BG)
        o += p(row, 52, f"${amt:>7,d}", HI, BG)
        o += p(row, 63, f"{pct:>3d}%", DK, BG)

    # Transactions
    o += p(26, 4, "transactions", DK, BG)
    o += p(26, 17, "─" * 59, VDK, BG)

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

    # Portfolio
    o += p(37, 4, "portfolio", DK, BG)
    o += p(37, 14, "─" * 62, VDK, BG)

    o += p(38, 4, "Stocks $62,450", MD, BG)
    o += p(38, 20, "+14.2%", AC, BOLD, BG)
    o += p(38, 30, "Bonds $18,220", MD, BG)
    o += p(38, 45, "+3.1%", AC, BG)
    o += p(38, 54, "Crypto $10,550", MD, BG)
    o += p(38, 70, "+8.7%", AC, BG)

    # Bottom status - between corner marks
    o += p(40, 10, "synced", DK, BG)
    o += p(40, 17, "·", VDK, BG)
    o += p(40, 19, "3 accounts", DK, BG)
    o += p(40, 30, "·", VDK, BG)
    o += p(40, 32, "2 min ago", DK, BG)
    o += p(40, 50, "press", DK, BG)
    o += p(40, 56, "?", AC, BOLD, BG)
    o += p(40, 58, "for help", DK, BG)

    o += finish()
    return o


# ============================================================
# MAIN
# ============================================================
def main():
    designs = [
        ("11-ledger.ansi",  design_ledger,  "Ledger (No-Border Dot Leaders)"),
        ("12-signal.ansi",  design_signal,  "Signal (Top/Bottom Rules Only)"),
        ("13-index.ansi",   design_index,   "Index (Double Header, Tab Nav)"),
        ("14-carbon.ansi",  design_carbon,  "Carbon (Side Rails, Coral Tags)"),
        ("15-trace.ansi",   design_trace,   "Trace (Crop Marks, Sage Green)"),
    ]
    outdir = os.path.dirname(os.path.abspath(__file__))
    for fname, fn, label in designs:
        path = os.path.join(outdir, fname)
        with open(path, 'w') as f:
            f.write(fn())
        print(f"  ✓ {fname:<20} {label}")


if __name__ == "__main__":
    main()
