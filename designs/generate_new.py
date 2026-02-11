#!/usr/bin/env python3
"""Generate 5 new brutal/clean dashboard designs for groschen finance app."""
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
# DESIGN 06: FORGE (Heavy Industrial Grid)
#
# Heavy box drawing (┏━┓┃┗┛) with titles embedded directly
# into the border of each section. Monochrome white/gray on
# pure black. Everything uppercase. Grid layout with vertical
# dividers between columns.
# ============================================================
def design_forge():
    BG = bg(0, 0, 0)
    HI = fg(255, 255, 255)
    MD = fg(140, 140, 140)
    DK = fg(70, 70, 70)
    BR = fg(100, 100, 100)
    BAR = fg(90, 90, 90)    # bars: visible but not louder than text
    BARE = fg(35, 35, 35)   # bar empty: just above background

    o = setup(BG)

    L, R = 1, 80
    inn = R - L - 1  # 78

    # Outer frame
    o += p(1, L, "┏" + "━" * inn + "┓", BR, BG)
    for row in range(2, 40):
        o += p(row, L, "┃", BR, BG)
        o += p(row, R, "┃", BR, BG)
    o += p(40, L, "┗" + "━" * inn + "┛", BR, BG)

    # Title bar
    o += p(2, 4, "GROSCHEN", HI, BOLD, BG)
    o += p(2, 30, "FINANCIAL OVERVIEW", MD, BG)
    o += p(2, 70, "APR 2025", DK, BG)

    # NET WORTH section
    title = " NET WORTH "
    o += p(3, L, "┣━━" + title + "━" * (inn - 3 - len(title)) + "┫", BR, BG)
    o += p(5, 4, "$127,842.56", HI, BOLD, BG)
    o += p(5, 20, "▁▂▃▃▄▅▅▆▆▇▇█", MD, BG)
    o += p(5, 40, "+$2,341.20", HI, BG)
    o += p(5, 55, "(+1.9%)", DK, BG)

    # Three-column split: ACCOUNTS | CASH FLOW | ALLOCATION
    c1 = 27  # first vertical divider column
    c2 = 53  # second vertical divider column
    t1, t2, t3 = " ACCOUNTS ", " CASH FLOW ", " ALLOCATION "
    s1 = "━━" + t1 + "━" * (c1 - L - 1 - 2 - len(t1))
    s2 = "━━" + t2 + "━" * (c2 - c1 - 1 - 2 - len(t2))
    s3 = "━━" + t3 + "━" * (R - c2 - 1 - 2 - len(t3))
    o += p(7, L, "┣" + s1 + "┳" + s2 + "┳" + s3 + "┫", BR, BG)

    for row in range(8, 14):
        o += p(row, c1, "┃", BR, BG)
        o += p(row, c2, "┃", BR, BG)

    # Accounts column
    o += p(9, 4, "CHECKING", MD, BG)
    o += p(9, 17, "$4,521", HI, BG)
    o += p(10, 4, "SAVINGS", MD, BG)
    o += p(10, 16, "$32,100", HI, BG)
    o += p(11, 4, "INVESTMENT", MD, BG)
    o += p(11, 16, "$91,221", HI, BG)

    # Cash flow column
    o += p(9, 30, "INCOME", MD, BG)
    o += p(9, 43, "$6,200", HI, BG)
    o += p(10, 30, "EXPENSES", MD, BG)
    o += p(10, 43, "$3,859", HI, BG)
    o += p(11, 30, "━" * 20, DK, BG)
    o += p(12, 30, "NET", MD, BG)
    o += p(12, 43, "$2,341", HI, BOLD, BG)

    # Allocation column
    alloc_bars = [10, 3, 2, 6]
    for i, ((name, pct), bw) in enumerate(zip(ALLOCS, alloc_bars)):
        row = 9 + i
        o += p(row, 56, "█" * bw, BAR, BG)
        o += p(row, 56 + bw + 1, name, DK, BG)
        o += p(row, 74, f"{pct:>3d}%", MD, BG)

    # Expenses: merge 3 columns back to 1
    line14 = list("━" * inn)
    te = "━━ EXPENSES "
    line14[0:len(te)] = list(te)
    line14[c1 - L - 1] = "┻"
    line14[c2 - L - 1] = "┻"
    rl = " TOTAL: $3,858.80 ━━"
    rs = inn - len(rl)
    line14[rs:rs + len(rl)] = list(rl)
    o += p(14, L, "┣" + "".join(line14) + "┫", BR, BG)

    maxbar = 35
    for i, (name, amt, pct) in enumerate(EXPENSES):
        row = 16 + i
        bw = int(pct / 31 * maxbar)
        o += p(row, 4, f"{name:<12}", MD, BG)
        o += p(row, 17, "█" * bw, BAR, BG)
        o += p(row, 17 + bw, "░" * (maxbar - bw), BARE, BG)
        o += p(row, 55, f"${amt:>7,d}", HI, BG)
        o += p(row, 66, f"{pct:>3d}%", DK, BG)

    # Transactions
    tt = " TRANSACTIONS "
    o += p(23, L, "┣━━" + tt + "━" * (inn - 3 - len(tt)) + "┫", BR, BG)

    o += p(25, 4, "DATE", DK, BG)
    o += p(25, 12, "DESCRIPTION", DK, BG)
    o += p(25, 34, "CATEGORY", DK, BG)
    o += p(25, 54, "AMOUNT", DK, BG)
    o += p(26, 4, "━" * 72, DK, BG)

    for i, (date, desc, cat, amt) in enumerate(TXNS):
        row = 27 + i
        sign = "+" if amt > 0 else "-"
        clr = HI if amt > 0 else MD
        o += p(row, 4, date, DK, BG)
        o += p(row, 12, desc, clr, BG)
        o += p(row, 34, cat, DK, BG)
        o += p(row, 53, f"{sign}${abs(amt):>8,.2f}", clr, BG)

    # Portfolio
    tp = " PORTFOLIO "
    o += p(35, L, "┣━━" + tp + "━" * (inn - 3 - len(tp)) + "┫", BR, BG)
    o += p(37, 4, "STOCKS $62,450", MD, BG)
    o += p(37, 20, "+14.2%", HI, BG)
    o += p(37, 30, "BONDS $18,220", MD, BG)
    o += p(37, 45, "+3.1%", HI, BG)
    o += p(37, 54, "CRYPTO $10,550", MD, BG)
    o += p(37, 70, "+8.7%", HI, BG)
    o += p(38, 4, "▁▂▃▄▅▆▇", DK, BG)
    o += p(38, 30, "▅▅▆▆▆▇▇", DK, BG)
    o += p(38, 54, "▂▄▅▃▆▇█", DK, BG)

    # Status bar
    o += p(39, L, "┣" + "━" * inn + "┫", BR, BG)
    o += p(39, 4, "3 ACCOUNTS", MD, BG)
    o += p(39, 17, "━", DK, BG)
    o += p(39, 19, "SYNCED", MD, BG)
    o += p(39, 28, "━", DK, BG)
    o += p(39, 30, "LAST UPDATE: 2 MIN AGO", DK, BG)

    o += finish()
    return o


# ============================================================
# DESIGN 07: PHOSPHOR (Amber Brutal)
#
# Amber/gold monochrome on near-black. Retro CRT warmth with
# brutal structural clarity. Double-line borders with embedded
# titles. Dot leaders for value alignment. F-key bar.
# ============================================================
def design_phosphor():
    BG = bg(8, 6, 0)
    AMB = fg(255, 176, 0)
    BRT = fg(255, 220, 100)
    MD = fg(180, 120, 0)
    DK = fg(90, 60, 0)
    BR = fg(200, 140, 0)

    o = setup(BG)

    L, R = 1, 80
    inn = R - L - 1  # 78

    # Outer double frame
    o += p(1, L, "╔" + "═" * inn + "╗", BR, BG)
    for row in range(2, 40):
        o += p(row, L, "║", BR, BG)
        o += p(row, R, "║", BR, BG)
    o += p(40, L, "╚" + "═" * inn + "╝", BR, BG)

    # Title
    o += p(2, 4, "G R O S C H E N", BRT, BOLD, BG)
    o += p(2, 28, "FINANCIAL TERMINAL v3.0", DK, BG)
    o += p(2, 62, "●", BRT, BOLD, BG)
    o += p(2, 64, "ONLINE", BRT, BG)
    o += p(2, 72, "04/08/25", DK, BG)

    # Net worth
    tn = " NET WORTH "
    o += p(3, L, "╠══" + tn + "═" * (inn - 3 - len(tn)) + "╣", BR, BG)
    o += p(5, 4, "$127,842.56", BRT, BOLD, BG)
    o += p(5, 20, "▁▂▃▃▄▅▅▆▆▇▇█", MD, BG)
    o += p(5, 42, "+$2,341.20", AMB, BG)
    o += p(5, 56, "(+1.9% THIS MONTH)", DK, BG)

    # Split: ACCOUNTS | CASH FLOW
    c_mid = 40
    tl = " ACCOUNTS "
    tr = " CASH FLOW "
    sl = "══" + tl + "═" * (c_mid - L - 1 - 2 - len(tl))
    sr = "══" + tr + "═" * (R - c_mid - 1 - 2 - len(tr))
    o += p(7, L, "╠" + sl + "╦" + sr + "╣", BR, BG)

    for row in range(8, 15):
        o += p(row, c_mid, "║", BR, BG)

    # Accounts with dot leaders
    accts = [("CHECKING", "$ 4,521.30"), ("SAVINGS", "$32,100.00"), ("INVESTMENT", "$91,221.26")]
    for i, (name, val) in enumerate(accts):
        row = 9 + i
        gap = 32 - len(name) - len(val)
        dots = "." * max(gap, 1)
        o += p(row, 4, name, AMB, BG)
        o += p(row, 4 + len(name), dots, DK, BG)
        o += p(row, 4 + len(name) + len(dots), val, BRT, BG)

    o += p(13, 4, "═" * 34, DK, BG)
    tn2, tv2 = "TOTAL", "$127,842.56"
    td = "." * (32 - len(tn2) - len(tv2))
    o += p(14, 4, tn2, AMB, BG)
    o += p(14, 4 + len(tn2), td, DK, BG)
    o += p(14, 4 + len(tn2) + len(td), tv2, BRT, BOLD, BG)

    # Cash flow with dot leaders
    flows = [("INCOME", "$ 6,200.00"), ("EXPENSES", "$ 3,858.80")]
    for i, (name, val) in enumerate(flows):
        row = 9 + i
        gap = 32 - len(name) - len(val)
        dots = "." * max(gap, 1)
        o += p(row, 43, name, AMB, BG)
        o += p(row, 43 + len(name), dots, DK, BG)
        o += p(row, 43 + len(name) + len(dots), val, BRT, BG)

    o += p(11, 43, "═" * 34, DK, BG)
    sn, sv = "NET SAVINGS", "$ 2,341.20"
    sd = "." * (32 - len(sn) - len(sv))
    o += p(12, 43, sn, AMB, BG)
    o += p(12, 43 + len(sn), sd, DK, BG)
    o += p(12, 43 + len(sn) + len(sd), sv, BRT, BOLD, BG)

    # Merge columns for expenses
    line15 = list("═" * inn)
    te = "══ EXPENSES "
    line15[0:len(te)] = list(te)
    line15[c_mid - L - 1] = "╩"
    rl = " TOTAL: $3,858.80 ══"
    rs = inn - len(rl)
    line15[rs:rs + len(rl)] = list(rl)
    o += p(15, L, "╠" + "".join(line15) + "╣", BR, BG)

    maxbar = 28
    for i, (name, amt, pct) in enumerate(EXPENSES):
        row = 17 + i
        bw = int(pct / 31 * maxbar)
        o += p(row, 4, f"{name:<12}", AMB, BG)
        o += p(row, 17, "█" * bw, BRT, BG)
        o += p(row, 17 + bw, "░" * (maxbar - bw), DK, BG)
        o += p(row, 48, f"${amt:>8,.2f}", AMB, BG)
        o += p(row, 60, f"{pct:>5.1f}%", DK, BG)

    # Transactions
    txn_t = " RECENT TRANSACTIONS "
    o += p(24, L, "╠══" + txn_t + "═" * (inn - 3 - len(txn_t)) + "╣", BR, BG)
    o += p(26, 4, "DATE", DK, ULINE, BG)
    o += p(26, 12, "PAYEE", DK, ULINE, BG)
    o += p(26, 32, "CATEGORY", DK, ULINE, BG)
    o += p(26, 52, "AMOUNT", DK, ULINE, BG)

    for i, (date, desc, cat, amt) in enumerate(TXNS):
        row = 27 + i
        sign = "+" if amt > 0 else "-"
        clr = BRT if amt > 0 else AMB
        o += p(row, 4, date, DK, BG)
        o += p(row, 12, desc, AMB, BG)
        o += p(row, 32, cat, DK, BG)
        o += p(row, 51, f"{sign} ${abs(amt):>7,.2f}", clr, BG)

    # Portfolio
    port_t = " PORTFOLIO "
    o += p(35, L, "╠══" + port_t + "═" * (inn - 3 - len(port_t)) + "╣", BR, BG)
    o += p(37, 4, "STOCKS", AMB, BG)
    o += p(37, 12, "$62,450", BRT, BG)
    o += p(37, 21, "+14.2%", BRT, BOLD, BG)
    o += p(37, 31, "BONDS", AMB, BG)
    o += p(37, 38, "$18,220", BRT, BG)
    o += p(37, 47, "+3.1%", BRT, BG)
    o += p(37, 56, "CRYPTO", AMB, BG)
    o += p(37, 64, "$10,550", BRT, BG)
    o += p(37, 73, "+8.7%", BRT, BG)
    o += p(38, 4, "▁▂▃▄▅▆▇", DK, BG)
    o += p(38, 31, "▅▅▆▆▆▇▇", DK, BG)
    o += p(38, 56, "▂▄▅▃▆▇█", DK, BG)

    # F-keys
    o += p(39, L, "╠" + "═" * inn + "╣", BR, BG)
    o += p(39, 3, "F1 ACCTS", DK, BG)
    o += p(39, 13, "F2 BUDGET", DK, BG)
    o += p(39, 24, "F3 INVEST", DK, BG)
    o += p(39, 35, "F4 TXNS", DK, BG)
    o += p(39, 44, "F5 REPORTS", DK, BG)
    o += p(39, 62, "F9 SYNC", DK, BG)
    o += p(39, 71, "F10 EXIT", DK, BG)

    o += finish()
    return o


# ============================================================
# DESIGN 08: SLATE (Cool Minimal Brutal)
#
# Cool blue-gray palette on deep charcoal. Section titles as
# ─── TITLE ───. No outer frame - open and airy. Generous
# whitespace. Uppercase. Calm, modern feel.
# ============================================================
def design_slate():
    BG = bg(18, 20, 24)
    FG = fg(200, 210, 220)
    HI = fg(240, 245, 255)
    AC = fg(130, 155, 185)   # accent: muted steel blue for small highlights
    BAR = fg(65, 80, 105)    # bars: dim blue, visible but not dominant
    BARE = fg(35, 40, 50)    # bar empty: just above background
    MD = fg(130, 140, 155)
    DK = fg(65, 72, 85)
    BR = fg(55, 62, 75)

    o = setup(BG)

    # Top bar - inverse
    bar_bg = bg(200, 210, 220)
    bar_fg = fg(18, 20, 24)
    o += p(1, 1, " " * 80, bar_bg)
    o += p(1, 3, "GROSCHEN", bar_fg, BOLD, bar_bg)
    o += p(1, 34, "FINANCIAL OVERVIEW", bar_fg, bar_bg)
    o += p(1, 72, "APR 2025", bar_fg, bar_bg)

    # Navigation
    o += p(3, 3, "OVERVIEW", HI, BOLD, ULINE, BG)
    o += p(3, 15, "ACCOUNTS", DK, BG)
    o += p(3, 27, "BUDGET", DK, BG)
    o += p(3, 37, "INVESTMENTS", DK, BG)
    o += p(3, 52, "HISTORY", DK, BG)

    # Net worth
    o += p(5, 3, "─── NET WORTH " + "─" * 63, BR, BG)
    o += p(7, 5, "$127,842.56", HI, BOLD, BG)
    o += p(7, 22, "▁▂▃▃▄▅▅▆▆▇▇█", BAR, BG)
    o += p(7, 42, "+$2,341.20", FG, BG)
    o += p(7, 58, "+1.9%", DK, BG)

    # Three columns
    o += p(9, 3, "─── ACCOUNTS " + "─" * 10, BR, BG)
    o += p(9, 28, "─── CASH FLOW " + "─" * 9, BR, BG)
    o += p(9, 54, "─── ALLOCATION " + "─" * 11, BR, BG)

    o += p(11, 5, "CHECKING", MD, BG)
    o += p(11, 18, "$4,521", HI, BG)
    o += p(12, 5, "SAVINGS", MD, BG)
    o += p(12, 17, "$32,100", HI, BG)
    o += p(13, 5, "INVESTMENT", MD, BG)
    o += p(13, 17, "$91,221", HI, BG)

    o += p(11, 30, "INCOME", MD, BG)
    o += p(11, 43, "$6,200", HI, BG)
    o += p(12, 30, "EXPENSES", MD, BG)
    o += p(12, 43, "$3,859", HI, BG)
    o += p(13, 30, "─" * 20, DK, BG)
    o += p(14, 30, "NET", MD, BG)
    o += p(14, 43, "$2,341", AC, BOLD, BG)

    alloc_bars = [10, 3, 2, 6]
    for i, ((name, pct), bw) in enumerate(zip(ALLOCS, alloc_bars)):
        row = 11 + i
        o += p(row, 56, "█" * bw, BAR, BG)
        o += p(row, 56 + bw + 1, name, DK, BG)
        o += p(row, 74, f"{pct:>3d}%", MD, BG)

    # Expenses
    o += p(16, 3, "─── EXPENSES " + "─" * 34 + " TOTAL: $3,858.80 " + "─" * 8, BR, BG)

    maxbar = 38
    for i, (name, amt, pct) in enumerate(EXPENSES):
        row = 18 + i
        bw = int(pct / 31 * maxbar)
        o += p(row, 5, f"{name:<12}", MD, BG)
        o += p(row, 18, "█" * bw, BAR, BG)
        o += p(row, 18 + bw, "░" * (maxbar - bw), BARE, BG)
        o += p(row, 59, f"${amt:>7,d}", HI, BG)
        o += p(row, 70, f"{pct:>3d}%", DK, BG)

    # Transactions
    o += p(25, 3, "─── TRANSACTIONS " + "─" * 60, BR, BG)
    o += p(27, 5, "DATE", DK, BG)
    o += p(27, 13, "DESCRIPTION", DK, BG)
    o += p(27, 35, "CATEGORY", DK, BG)
    o += p(27, 55, "AMOUNT", DK, BG)

    for i, (date, desc, cat, amt) in enumerate(TXNS):
        row = 29 + i
        sign = "+" if amt > 0 else "-"
        clr = AC if amt > 0 else FG
        o += p(row, 5, date, DK, BG)
        o += p(row, 13, desc, FG if amt > 0 else MD, BG)
        o += p(row, 35, cat, DK, BG)
        o += p(row, 54, f"{sign}${abs(amt):>8,.2f}", clr, BG)

    # Portfolio
    o += p(37, 3, "─── PORTFOLIO " + "─" * 63, BR, BG)
    o += p(38, 5, "STOCKS $62,450", MD, BG)
    o += p(38, 21, "+14.2%", AC, BOLD, BG)
    o += p(38, 31, "BONDS $18,220", MD, BG)
    o += p(38, 46, "+3.1%", AC, BG)
    o += p(38, 55, "CRYPTO $10,550", MD, BG)
    o += p(38, 71, "+8.7%", AC, BG)

    # Bottom bar - inverse
    o += p(40, 1, " " * 80, bar_bg)
    o += p(40, 3, "3 ACCOUNTS", bar_fg, bar_bg)
    o += p(40, 16, "│", bar_fg, bar_bg)
    o += p(40, 18, "SYNCED", bar_fg, bar_bg)
    o += p(40, 27, "│", bar_fg, bar_bg)
    o += p(40, 29, "LAST UPDATE: 2 MIN AGO", bar_fg, bar_bg)

    o += finish()
    return o


# ============================================================
# DESIGN 09: GLYPH (Unicode Decorative)
#
# Heavy use of decorative Unicode characters for visual flair.
# Diamond corners, arrow bullets, geometric dividers, braille
# sparklines. White + warm amber accent on black.
# ============================================================
def design_glyph():
    BG = bg(0, 0, 0)
    HI = fg(255, 255, 255)
    AC = fg(255, 190, 60)
    MD = fg(160, 160, 160)
    DK = fg(80, 80, 80)
    VDK = fg(45, 45, 45)

    o = setup(BG)

    # Diamond corners with heavy rules
    o += p(1, 1, "◆" + "━" * 78 + "◆", AC, BG)
    for row in range(2, 40):
        o += p(row, 1, "┃", AC, BG)
        o += p(row, 80, "┃", AC, BG)
    o += p(40, 1, "◆" + "━" * 78 + "◆", AC, BG)

    # Title with decorative markers
    o += p(2, 4, "◈", AC, BG)
    o += p(2, 6, "GROSCHEN", HI, BOLD, BG)
    o += p(2, 30, "⟐ FINANCIAL OVERVIEW ⟐", MD, BG)
    o += p(2, 70, "APR 2025", DK, BG)

    # Navigation with arrow bullets
    o += p(3, 4, "▸ OVERVIEW", HI, BOLD, BG)
    o += p(3, 17, "▹ ACCOUNTS", DK, BG)
    o += p(3, 30, "▹ BUDGET", DK, BG)
    o += p(3, 41, "▹ INVESTMENTS", DK, BG)
    o += p(3, 57, "▹ HISTORY", DK, BG)

    # Decorative divider
    o += p(4, 1, "┣" + "━◆━" * 26 + "┫", DK, BG)

    # NET WORTH with diamond section marker
    o += p(6, 4, "◈ NET WORTH", AC, BOLD, BG)
    o += p(7, 6, "$127,842.56", HI, BOLD, BG)
    o += p(7, 22, "⣀⣠⣤⣤⣴⣶⣶⣾⣾⣿⣿", AC, BG)
    o += p(7, 42, "▲ $2,341.20", HI, BG)
    o += p(7, 58, "(+1.9%)", DK, BG)

    # Section: ACCOUNTS | CASH FLOW | ALLOCATION
    o += p(9, 1, "┣━━◆ ACCOUNTS ◆━━━━━━━━━━┳━━◆ CASH FLOW ◆━━━━━━━━━┳━━◆ ALLOCATION ◆━━━━━━┫", AC, BG)

    c1, c2 = 27, 53
    for row in range(10, 16):
        o += p(row, c1, "┃", AC, BG)
        o += p(row, c2, "┃", AC, BG)

    # Accounts
    o += p(11, 4, "▸ CHECKING", MD, BG)
    o += p(11, 18, "$4,521", HI, BG)
    o += p(12, 4, "▸ SAVINGS", MD, BG)
    o += p(12, 17, "$32,100", HI, BG)
    o += p(13, 4, "▸ INVESTMENT", MD, BG)
    o += p(13, 17, "$91,221", HI, BG)

    # Cash flow
    o += p(11, 30, "INCOME", MD, BG)
    o += p(11, 43, "$6,200", HI, BG)
    o += p(12, 30, "EXPENSES", MD, BG)
    o += p(12, 43, "$3,859", HI, BG)
    o += p(13, 30, "─" * 20, DK, BG)
    o += p(14, 30, "NET", MD, BG)
    o += p(14, 43, "$2,341", AC, BOLD, BG)

    # Allocation with geometric bars
    allocs_data = [("STOCKS", 49, 10), ("BONDS", 14, 3), ("CRYPTO", 8, 2), ("CASH", 29, 6)]
    for i, (name, pct, bw) in enumerate(allocs_data):
        row = 11 + i
        o += p(row, 56, "▰" * bw + "▱" * (10 - bw), AC, BG)
        o += p(row, 68, name, DK, BG)
        o += p(row, 75, f"{pct}%", MD, BG)

    # Expenses
    line16 = list("━" * 78)
    te = "━◆ EXPENSES ◆"
    line16[1:1 + len(te)] = list(te)
    line16[c1 - 1] = "┻"
    line16[c2 - 1] = "┻"
    rl = " TOTAL: $3,858.80 ━━"
    rs = 78 - len(rl)
    line16[rs:rs + len(rl)] = list(rl)
    o += p(16, 1, "┣" + "".join(line16)[:78] + "┫", AC, BG)

    maxbar = 30
    for i, (name, amt, pct) in enumerate(EXPENSES):
        row = 18 + i
        bw = int(pct / 31 * maxbar)
        o += p(row, 4, f"{'▸ ' + name:<14}", MD, BG)
        o += p(row, 18, "▰" * bw + "▱" * (maxbar - bw), AC, BG)
        o += p(row, 51, f"${amt:>7,d}", HI, BG)
        o += p(row, 62, f"{pct:>3d}%", DK, BG)

    # Transactions
    o += p(25, 1, "┣━━◆ TRANSACTIONS ◆" + "━" * 59 + "┫", AC, BG)
    o += p(27, 4, "DATE", DK, BG)
    o += p(27, 12, "DESCRIPTION", DK, BG)
    o += p(27, 34, "CATEGORY", DK, BG)
    o += p(27, 54, "AMOUNT", DK, BG)

    for i, (date, desc, cat, amt) in enumerate(TXNS):
        row = 28 + i
        sign = "▲" if amt > 0 else "▼"
        clr = AC if amt > 0 else MD
        o += p(row, 4, date, DK, BG)
        o += p(row, 12, desc, HI if amt > 0 else MD, BG)
        o += p(row, 34, cat, DK, BG)
        o += p(row, 53, f"{sign} ${abs(amt):>7,.2f}", clr, BG)

    # Portfolio
    o += p(36, 1, "┣━━◆ PORTFOLIO ◆" + "━" * 62 + "┫", AC, BG)
    o += p(37, 4, "STOCKS $62,450", MD, BG)
    o += p(37, 20, "▲14.2%", AC, BOLD, BG)
    o += p(37, 30, "BONDS $18,220", MD, BG)
    o += p(37, 45, "▲3.1%", AC, BG)
    o += p(37, 54, "CRYPTO $10,550", MD, BG)
    o += p(37, 70, "▲8.7%", AC, BG)
    o += p(38, 4, "⣀⣠⣤⣴⣶⣾⣿", DK, BG)
    o += p(38, 30, "⣶⣶⣾⣾⣾⣿⣿", DK, BG)
    o += p(38, 54, "⣠⣴⣶⣤⣾⣿⣿", DK, BG)

    # Status bar
    o += p(39, 1, "┣" + "━" * 78 + "┫", AC, BG)
    o += p(39, 4, "● 3 ACCOUNTS", AC, BG)
    o += p(39, 19, "◆", DK, BG)
    o += p(39, 21, "● SYNCED", AC, BG)
    o += p(39, 32, "◆", DK, BG)
    o += p(39, 34, "LAST UPDATE: 2 MIN AGO", DK, BG)

    o += finish()
    return o


# ============================================================
# DESIGN 10: VAULT (Corporate Mainframe)
#
# Double borders everywhere. Titles as ═╡ TITLE ╞═══.
# White on black with green accent for positive values.
# Dense tabular data. Status indicators with ● ○.
# Corporate mainframe feel meets brutal structure.
# ============================================================
def design_vault():
    BG = bg(0, 0, 0)
    HI = fg(255, 255, 255)
    GR = fg(0, 180, 75)     # green accent for small text highlights
    BAR = fg(0, 90, 40)     # bars: muted green, visible but not dominant
    BARE = fg(30, 35, 30)   # bar empty: just above background
    MD = fg(160, 160, 160)
    DK = fg(80, 80, 80)
    BR = fg(100, 100, 100)

    o = setup(BG)

    L, R = 1, 80
    inn = R - L - 1  # 78

    # Outer double frame
    o += p(1, L, "╔" + "═" * inn + "╗", BR, BG)
    for row in range(2, 40):
        o += p(row, L, "║", BR, BG)
        o += p(row, R, "║", BR, BG)
    o += p(40, L, "╚" + "═" * inn + "╝", BR, BG)

    # Title - inverse bar inside frame
    o += p(2, 2, " " * 78, bg(255, 255, 255))
    o += p(2, 4, "GROSCHEN", fg(0, 0, 0), BOLD, bg(255, 255, 255))
    o += p(2, 30, "FINANCIAL OVERVIEW", fg(0, 0, 0), bg(255, 255, 255))
    o += p(2, 70, "APR 2025", fg(0, 0, 0), bg(255, 255, 255))

    # Navigation
    o += p(3, 4, "● OVERVIEW", HI, BOLD, BG)
    o += p(3, 17, "○ ACCOUNTS", DK, BG)
    o += p(3, 30, "○ BUDGET", DK, BG)
    o += p(3, 41, "○ INVESTMENTS", DK, BG)
    o += p(3, 57, "○ HISTORY", DK, BG)

    # NET WORTH
    o += p(4, L, "╠═╡ NET WORTH ╞" + "═" * (inn - 15) + "╣", BR, BG)
    o += p(6, 4, "$127,842.56", HI, BOLD, BG)
    o += p(6, 20, "▁▂▃▃▄▅▅▆▆▇▇█", MD, BG)
    o += p(6, 40, "+$2,341.20", GR, BG)
    o += p(6, 55, "(+1.9%)", GR, BG)

    # Three columns: ACCOUNTS | CASH FLOW | ALLOCATION
    c1, c2 = 27, 53
    seg1 = "═╡ ACCOUNTS ╞" + "═" * (c1 - L - 1 - 14)
    seg2 = "═╡ CASH FLOW ╞" + "═" * (c2 - c1 - 1 - 15)
    seg3 = "═╡ ALLOCATION ╞" + "═" * (R - c2 - 1 - 16)
    o += p(8, L, "╠" + seg1 + "╦" + seg2 + "╦" + seg3 + "╣", BR, BG)

    for row in range(9, 15):
        o += p(row, c1, "║", BR, BG)
        o += p(row, c2, "║", BR, BG)

    o += p(10, 4, "CHECKING", MD, BG)
    o += p(10, 17, "$4,521", HI, BG)
    o += p(11, 4, "SAVINGS", MD, BG)
    o += p(11, 16, "$32,100", HI, BG)
    o += p(12, 4, "INVESTMENT", MD, BG)
    o += p(12, 16, "$91,221", HI, BG)

    o += p(10, 30, "INCOME", MD, BG)
    o += p(10, 43, "$6,200", GR, BG)
    o += p(11, 30, "EXPENSES", MD, BG)
    o += p(11, 43, "$3,859", HI, BG)
    o += p(12, 30, "═" * 20, DK, BG)
    o += p(13, 30, "NET", MD, BG)
    o += p(13, 43, "$2,341", GR, BOLD, BG)

    alloc_bars = [10, 3, 2, 6]
    for i, ((name, pct), bw) in enumerate(zip(ALLOCS, alloc_bars)):
        row = 10 + i
        o += p(row, 56, "█" * bw, BAR, BG)
        o += p(row, 56 + bw + 1, name, DK, BG)
        o += p(row, 74, f"{pct:>3d}%", MD, BG)

    # Expenses
    line15 = list("═" * inn)
    te = "═╡ EXPENSES ╞"
    line15[0:len(te)] = list(te)
    line15[c1 - L - 1] = "╩"
    line15[c2 - L - 1] = "╩"
    rl = " TOTAL: $3,858.80 ══"
    rs = inn - len(rl)
    line15[rs:rs + len(rl)] = list(rl)
    o += p(15, L, "╠" + "".join(line15) + "╣", BR, BG)

    maxbar = 35
    for i, (name, amt, pct) in enumerate(EXPENSES):
        row = 17 + i
        bw = int(pct / 31 * maxbar)
        o += p(row, 4, f"{name:<12}", MD, BG)
        o += p(row, 17, "█" * bw, BAR, BG)
        o += p(row, 17 + bw, "░" * (maxbar - bw), BARE, BG)
        o += p(row, 55, f"${amt:>7,d}", HI, BG)
        o += p(row, 66, f"{pct:>3d}%", DK, BG)

    # Transactions
    o += p(24, L, "╠═╡ TRANSACTIONS ╞" + "═" * (inn - 18) + "╣", BR, BG)
    o += p(26, 4, "DATE", DK, BG)
    o += p(26, 12, "DESCRIPTION", DK, BG)
    o += p(26, 34, "CATEGORY", DK, BG)
    o += p(26, 54, "AMOUNT", DK, BG)

    for i, (date, desc, cat, amt) in enumerate(TXNS):
        row = 27 + i
        sign = "+" if amt > 0 else "-"
        clr = GR if amt > 0 else MD
        o += p(row, 4, date, DK, BG)
        o += p(row, 12, desc, HI if amt > 0 else MD, BG)
        o += p(row, 34, cat, DK, BG)
        o += p(row, 53, f"{sign}${abs(amt):>8,.2f}", clr, BG)

    # Portfolio
    o += p(35, L, "╠═╡ PORTFOLIO ╞" + "═" * (inn - 15) + "╣", BR, BG)
    o += p(37, 4, "STOCKS $62,450", MD, BG)
    o += p(37, 20, "+14.2%", GR, BOLD, BG)
    o += p(37, 30, "BONDS $18,220", MD, BG)
    o += p(37, 45, "+3.1%", GR, BG)
    o += p(37, 54, "CRYPTO $10,550", MD, BG)
    o += p(37, 70, "+8.7%", GR, BG)
    o += p(38, 4, "▁▂▃▄▅▆▇", DK, BG)
    o += p(38, 30, "▅▅▆▆▆▇▇", DK, BG)
    o += p(38, 54, "▂▄▅▃▆▇█", DK, BG)

    # Status
    o += p(39, L, "╠" + "═" * inn + "╣", BR, BG)
    o += p(39, 4, "● 3 ACCOUNTS", GR, BG)
    o += p(39, 20, "║", BR, BG)
    o += p(39, 22, "● SYNCED", GR, BG)
    o += p(39, 33, "║", BR, BG)
    o += p(39, 35, "LAST UPDATE: 2 MIN AGO", DK, BG)

    o += finish()
    return o


# ============================================================
# MAIN
# ============================================================
def main():
    designs = [
        ("06-forge.ansi",    design_forge,    "Forge (Heavy Industrial)"),
        ("07-phosphor.ansi", design_phosphor, "Phosphor (Amber Brutal)"),
        ("08-slate.ansi",    design_slate,    "Slate (Cool Minimal)"),
        ("09-glyph.ansi",    design_glyph,    "Glyph (Unicode Decorative)"),
        ("10-vault.ansi",    design_vault,    "Vault (Corporate Mainframe)"),
    ]
    outdir = os.path.dirname(os.path.abspath(__file__))
    for fname, fn, label in designs:
        path = os.path.join(outdir, fname)
        with open(path, 'w') as f:
            f.write(fn())
        print(f"  ✓ {fname:<20} {label}")

if __name__ == "__main__":
    main()
