#!/usr/bin/env python3
"""Generate 5 dashboard design mockups for groschen finance app."""
import os

# === Escape Helpers ===
E = "\033"
RST = f"{E}[0m"
BOLD = f"{E}[1m"
DIM = f"{E}[2m"
ITALIC = f"{E}[3m"
ULINE = f"{E}[4m"
REVERSE = f"{E}[7m"

def fg(r,g,b): return f"{E}[38;2;{r};{g};{b}m"
def bg(r,g,b): return f"{E}[48;2;{r};{g};{b}m"
def at(r,c): return f"{E}[{r};{c}H"

W, H = 80, 40

def setup(bgc):
    o = f"{E}[2J{E}[H{E}[?25l"
    for r in range(1, H+1):
        o += f"{at(r,1)}{bgc}{' '*W}"
    return o

def finish():
    return f"{RST}{at(H+1,1)}{E}[?25h"

def p(r, c, text, *styles):
    return f"{at(r,c)}{''.join(styles)}{text}{RST}"

def rbox(r1,c1,r2,c2,bs,ibg=""):
    w=c2-c1-1; o=""
    o+=f"{at(r1,c1)}{bs}╭{'─'*w}╮"
    for r in range(r1+1,r2):
        o+=f"{at(r,c1)}{bs}│{ibg}{' '*w}{bs}│"
    o+=f"{at(r2,c1)}{bs}╰{'─'*w}╯"
    return o

def dbox(r1,c1,r2,c2,bs,ibg=""):
    w=c2-c1-1; o=""
    o+=f"{at(r1,c1)}{bs}╔{'═'*w}╗"
    for r in range(r1+1,r2):
        o+=f"{at(r,c1)}{bs}║{ibg}{' '*w}{bs}║"
    o+=f"{at(r2,c1)}{bs}╚{'═'*w}╝"
    return o

def hbox(r1,c1,r2,c2,bs,ibg=""):
    w=c2-c1-1; o=""
    o+=f"{at(r1,c1)}{bs}┏{'━'*w}┓"
    for r in range(r1+1,r2):
        o+=f"{at(r,c1)}{bs}┃{ibg}{' '*w}{bs}┃"
    o+=f"{at(r2,c1)}{bs}┗{'━'*w}┛"
    return o

def dhsep(row,c1,c2,bs):
    w=c2-c1-1
    return f"{at(row,c1)}{bs}╠{'═'*w}╣"

def hhsep(row,c1,c2,bs):
    w=c2-c1-1
    return f"{at(row,c1)}{bs}┣{'━'*w}┫"


# ============================================================
# DESIGN 1: ZEN (Nordic Minimalist)
# ============================================================
def design_zen():
    BG  = bg(46,52,64)
    CBG = bg(59,66,82)
    FG  = fg(236,239,244)
    ACC = fg(136,192,208)
    AC2 = fg(129,161,193)
    GRN = fg(163,190,140)
    RED = fg(191,97,106)
    DM  = fg(76,86,106)
    DM2 = fg(59,66,82)
    ORG = fg(208,135,112)
    YLW = fg(235,203,139)

    o = setup(BG)

    # Title
    o += p(2, 4, "g r o s c h e n", ACC, BOLD, BG)
    o += p(2, 55, "○", GRN, BG)
    o += p(2, 57, "connected · 3 accounts", DM, BG)

    # --- Net Worth Hero ---
    o += rbox(4, 4, 9, 77, ACC+CBG, CBG+FG)
    o += p(4, 6, " Net Worth ", ACC, BOLD, CBG)
    o += p(6, 8, "$127,842.56", FG, BOLD, CBG)
    o += p(6, 56, "▁▂▃▃▄▅▅▆▆▇▇█", ACC, CBG)
    o += p(7, 8, "↑", GRN, CBG)
    o += p(7, 10, "$2,341.20 this month", GRN, CBG)
    o += p(7, 56, "last 12 months", DM, CBG)

    # --- Accounts ---
    o += rbox(11, 4, 17, 31, AC2+CBG, CBG+FG)
    o += p(11, 6, " Accounts ", AC2, BOLD, CBG)
    o += p(13, 7, "◐", ACC, CBG)
    o += p(13, 9, "Checking", FG, CBG)
    o += p(13, 20, "$4,521.30", DM, CBG)
    o += p(14, 7, "◐", ACC, CBG)
    o += p(14, 9, "Savings", FG, CBG)
    o += p(14, 19, "$32,100.00", DM, CBG)
    o += p(15, 7, "◐", YLW, CBG)
    o += p(15, 9, "Invest.", FG, CBG)
    o += p(15, 19, "$91,221.26", DM, CBG)

    # --- This Month ---
    o += rbox(11, 34, 17, 77, AC2+CBG, CBG+FG)
    o += p(11, 36, " This Month ", AC2, BOLD, CBG)
    o += p(13, 37, "Income", FG, CBG)
    o += p(13, 47, "$6,200.00", FG, CBG)
    o += p(13, 59, "████████████████", GRN, CBG)
    o += p(14, 37, "Expenses", FG, CBG)
    o += p(14, 47, "$3,858.80", FG, CBG)
    o += p(14, 59, "██████████", RED, CBG)
    o += p(14, 69, "░░░░░░", DM2, CBG)
    o += p(15, 37, "Saved", FG, CBG)
    o += p(15, 47, "$2,341.20", FG, CBG)
    o += p(15, 59, "██████", ACC, CBG)
    o += p(15, 65, "░░░░░░░░░░", DM2, CBG)

    # --- Recent Transactions ---
    o += rbox(19, 4, 34, 31, AC2+CBG, CBG+FG)
    o += p(19, 6, " Recent ", AC2, BOLD, CBG)
    o += p(21, 7, "Today", DM, ITALIC, CBG)
    o += p(22, 7, "·", DM, CBG)
    o += p(22, 9, "Whole Foods", FG, CBG)
    o += p(22, 22, "-$84.32", RED, CBG)
    o += p(23, 7, "·", DM, CBG)
    o += p(23, 9, "Transfer", FG, CBG)
    o += p(23, 21, "+$200.00", GRN, CBG)
    o += p(25, 7, "Yesterday", DM, ITALIC, CBG)
    o += p(26, 7, "·", DM, CBG)
    o += p(26, 9, "Amazon", FG, CBG)
    o += p(26, 22, "-$34.99", RED, CBG)
    o += p(27, 7, "·", DM, CBG)
    o += p(27, 9, "Spotify", FG, CBG)
    o += p(27, 23, "-$9.99", RED, CBG)
    o += p(28, 7, "·", DM, CBG)
    o += p(28, 9, "Coffee", FG, CBG)
    o += p(28, 23, "-$5.50", RED, CBG)
    o += p(30, 7, "Apr 5", DM, ITALIC, CBG)
    o += p(31, 7, "·", DM, CBG)
    o += p(31, 9, "Gas station", FG, CBG)
    o += p(31, 21, "-$52.00", RED, CBG)
    o += p(32, 7, "·", DM, CBG)
    o += p(32, 9, "Restaurant", FG, CBG)
    o += p(32, 21, "-$67.80", RED, CBG)

    # --- Categories ---
    o += rbox(19, 34, 28, 77, AC2+CBG, CBG+FG)
    o += p(19, 36, " Categories ", AC2, BOLD, CBG)
    cats = [
        ("Housing",    "$1,200.00", 12, YLW),
        ("Food",       "  $642.30",  7, ORG),
        ("Transport",  "  $380.00",  4, ACC),
        ("Utilities",  "  $245.50",  3, AC2),
        ("Entertain.", "  $180.00",  2, GRN),
        ("Health",     "  $120.00",  1, GRN),
    ]
    for i, (name, amt, bw, clr) in enumerate(cats):
        r = 21 + i
        o += p(r, 37, "▸", ACC, CBG)
        o += p(r, 39, name, FG, CBG)
        o += p(r, 51, amt, DM, CBG)
        o += p(r, 62, "█"*bw, clr, CBG)

    # --- Investments ---
    o += rbox(30, 34, 36, 77, AC2+CBG, CBG+FG)
    o += p(30, 36, " Investments ", AC2, BOLD, CBG)
    invs = [
        ("Stocks", "$62,450", "▁▂▃▄▅▆▇", "+14.2%", ACC),
        ("Bonds",  "$18,220", "▅▅▆▆▆▇▇", "+ 3.1%", AC2),
        ("Crypto", "$10,550", "▂▄▅▃▆▇█", "+28.7%", ORG),
    ]
    for i, (name, amt, spark, pct, clr) in enumerate(invs):
        r = 32 + i
        o += p(r, 37, name, FG, CBG)
        o += p(r, 46, amt, DM, CBG)
        o += p(r, 55, spark, clr, CBG)
        o += p(r, 64, pct, GRN, CBG)

    # --- Navigation ---
    tabs = [("◆","overview",ACC,BOLD), ("◇","accounts",DM,""), ("◇","budget",DM,""), ("◇","investments",DM,""), ("◇","settings",DM,"")]
    col = 4
    for icon, label, clr, weight in tabs:
        o += p(38, col, icon, clr, weight, BG)
        o += p(38, col+2, label, clr, BG)
        col += len(label) + 5

    o += finish()
    return o


# ============================================================
# DESIGN 2: AMBER (Retro CRT Terminal)
# ============================================================
def design_amber():
    BG  = bg(10,8,0)
    AMB = fg(255,176,0)
    BRT = fg(255,216,100)
    DM  = fg(128,88,0)
    DK  = fg(80,55,0)
    BS  = AMB + BG

    o = setup(BG)

    # Outer frame
    o += dbox(1, 1, 40, 80, BS, BG+AMB)

    # Header
    o += p(2, 4, "G R O S C H E N", BRT, BOLD, BG)
    o += p(2, 23, "FINANCIAL TERMINAL v2.1", DM, BG)
    o += p(2, 60, "●", BRT, BOLD, BG)
    o += p(2, 62, "ONLINE", BRT, BG)
    o += p(2, 70, "04/08/25", DM, BG)
    o += dhsep(3, 1, 80, BS)

    # Account Summary (left) + Monthly P&L (right)
    o += p(5, 4, "ACCOUNT SUMMARY", BRT, BOLD, BG)
    o += p(5, 42, "MONTHLY P&L", BRT, BOLD, BG)
    o += p(6, 4, "═"*17, DM, BG)
    o += p(6, 42, "═"*11, DM, BG)
    o += p(7, 4, "CHECKING", AMB, BG)
    o += p(7, 15, ".........", DK, BG)
    o += p(7, 25, "$  4,521.30", AMB, BG)
    o += p(7, 42, "INCOME", AMB, BG)
    o += p(7, 51, "......", DK, BG)
    o += p(7, 58, "$  6,200.00", AMB, BG)
    o += p(8, 4, "SAVINGS", AMB, BG)
    o += p(8, 15, "..........", DK, BG)
    o += p(8, 25, "$ 32,100.00", AMB, BG)
    o += p(8, 42, "EXPENSES", AMB, BG)
    o += p(8, 51, "....", DK, BG)
    o += p(8, 58, "$  3,858.80", AMB, BG)
    o += p(9, 4, "INVESTMENT", AMB, BG)
    o += p(9, 15, ".......", DK, BG)
    o += p(9, 25, "$ 91,221.26", AMB, BG)
    o += p(9, 42, "═"*27, DM, BG)
    o += p(10, 4, "═"*32, DM, BG)
    o += p(10, 42, "NET CHANGE", AMB, BG)
    o += p(10, 53, "...", DK, BG)
    o += p(10, 58, "$  2,341.20", BRT, BOLD, BG)
    o += p(11, 4, "TOTAL NET WORTH", BRT, BOLD, BG)
    o += p(11, 20, "....", DK, BG)
    o += p(11, 25, "$127,842.56", BRT, BOLD, BG)
    o += dhsep(13, 1, 80, BS)

    # Expense Analysis
    o += p(14, 4, "EXPENSE ANALYSIS", BRT, BOLD, BG)
    o += p(15, 4, "═"*16, DM, BG)
    expenses = [
        ("HOUSING",   1200, 31.1),
        ("FOOD",       642, 16.6),
        ("TRANSPORT",  380,  9.8),
        ("UTILITIES",  245,  6.4),
        ("ENTERTAIN",  180,  4.7),
        ("HEALTH",     120,  3.1),
    ]
    maxbar = 28
    for i, (name, amt, pct) in enumerate(expenses):
        r = 16 + i
        bw = int(pct / 31.1 * maxbar)
        o += p(r, 4, f"{name:<12}", AMB, BG)
        o += p(r, 16, "█"*bw, BRT, BG)
        o += p(r, 16+bw, "░"*(maxbar-bw), DK, BG)
        o += p(r, 47, f"${amt:>8,.2f}", AMB, BG)
        o += p(r, 59, f"{pct:>5.1f}%", DM, BG)
    o += dhsep(23, 1, 80, BS)

    # Recent Transactions
    o += p(24, 4, "RECENT TRANSACTIONS", BRT, BOLD, BG)
    o += p(25, 4, "═"*19, DM, BG)
    o += p(26, 4, "DATE   PAYEE              CATEGORY      AMOUNT", DM, ULINE, BG)
    txns = [
        ("04/08", "WHOLE FOODS",    "FOOD",      "- $  84.32"),
        ("04/08", "BANK TRANSFER",  "TRANSFER",  "+ $ 200.00"),
        ("04/07", "AMAZON.COM",     "SHOPPING",  "- $  34.99"),
        ("04/07", "SPOTIFY",        "ENTERTAIN", "- $   9.99"),
        ("04/07", "STARBUCKS",      "FOOD",      "- $   5.50"),
        ("04/05", "SHELL OIL",      "TRANSPORT", "- $  52.00"),
        ("04/05", "OLIVE GARDEN",   "FOOD",      "- $  67.80"),
    ]
    for i, (date, payee, cat, amt) in enumerate(txns):
        r = 27 + i
        clr = BRT if "+" in amt else AMB
        o += p(r, 4, date, DM, BG)
        o += p(r, 11, f"{payee:<17}", AMB, BG)
        o += p(r, 30, f"{cat:<12}", DM, BG)
        o += p(r, 44, amt, clr, BG)
    o += dhsep(35, 1, 80, BS)

    # Portfolio
    o += p(36, 4, "PORTFOLIO", BRT, BOLD, BG)
    o += p(36, 16, "STOCKS $62,450", AMB, BG)
    o += p(36, 31, "+14.2%", BRT, BG)
    o += p(36, 40, "│", DM, BG)
    o += p(36, 42, "BONDS $18,220", AMB, BG)
    o += p(36, 56, "+3.1%", BRT, BG)
    o += p(36, 63, "│", DM, BG)
    o += p(36, 65, "CRYPTO $10,550", AMB, BG)
    o += p(37, 16, "▁▂▃▄▅▆▇", DM, BG)
    o += p(37, 42, "▅▅▆▆▆▇▇", DM, BG)
    o += p(37, 65, "▂▄▅▃▆▇█", DM, BG)
    o += dhsep(38, 1, 80, BS)

    # F-keys
    fkeys = "F1=ACCTS  F2=BUDGET  F3=INVEST  F4=TXNS  F5=REPORTS       F9=SYNC  F10=EXIT"
    o += p(39, 3, fkeys, DM, BG)

    o += finish()
    return o


# ============================================================
# DESIGN 3: NEON (Cyberpunk)
# ============================================================
def design_neon():
    BG   = bg(13,2,33)
    PBG  = bg(21,5,53)
    MAG  = fg(255,0,255)
    CYN  = fg(0,255,255)
    PNK  = fg(255,64,129)
    GRN  = fg(0,230,118)
    WHT  = fg(255,255,255)
    DM   = fg(100,60,160)
    BLU  = fg(61,90,254)
    YLW  = fg(255,234,0)
    BS   = MAG + BG

    o = setup(BG)

    # Outer frame
    o += hbox(1, 1, 40, 80, BS, BG)

    # Nav bar
    o += p(2, 4, "⚡", YLW, BG)
    o += p(2, 6, "GROSCHEN", MAG, BOLD, BG)
    o += p(2, 34, "▸", CYN, BG)
    o += p(2, 36, "DASH", CYN, BOLD, BG)
    o += p(2, 43, "▹", DM, BG)
    o += p(2, 45, "ACCTS", DM, BG)
    o += p(2, 53, "▹", DM, BG)
    o += p(2, 55, "BUDGET", DM, BG)
    o += p(2, 64, "▹", DM, BG)
    o += p(2, 66, "INVEST", DM, BG)
    o += hhsep(3, 1, 80, BS)

    # --- Net Worth Panel ---
    o += hbox(5, 3, 12, 38, CYN+PBG, PBG)
    o += p(5, 5, " NET WORTH ", CYN, BOLD, PBG)
    o += p(7, 6, "$127,842", WHT, BOLD, PBG)
    o += p(7, 15, ".56", DM, PBG)
    o += p(8, 6, "░▒▓", MAG, PBG)
    o += p(8, 10, "+1.9%", GRN, BOLD, PBG)
    o += p(8, 16, "THIS MONTH", DM, PBG)
    o += p(10, 6, "▁▂▂▃▃▄▄▅▅▆▆▇▇█", CYN, PBG)
    o += p(11, 6, "J F M A M J J A S O N D", DM, PBG)

    # --- Cash Flow Panel ---
    o += hbox(5, 42, 12, 78, MAG+PBG, PBG)
    o += p(5, 44, " CASH FLOW ", MAG, BOLD, PBG)
    o += p(7, 45, "▲", GRN, BOLD, PBG)
    o += p(7, 47, "IN", GRN, PBG)
    o += p(7, 53, "$6,200.00", WHT, PBG)
    o += p(8, 45, "▼", PNK, BOLD, PBG)
    o += p(8, 47, "OUT", PNK, PBG)
    o += p(8, 53, "$3,858.80", WHT, PBG)
    o += p(9, 45, "━"*30, DM, PBG)
    o += p(10, 45, "Δ", CYN, BOLD, PBG)
    o += p(10, 47, "NET", CYN, PBG)
    o += p(10, 53, "+$2,341.20", GRN, BOLD, PBG)
    o += p(11, 45, "▓"*19, GRN, PBG)
    o += p(11, 64, "░"*10, DM, PBG)
    o += p(11, 75, "62%", CYN, PBG)

    # --- Accounts ---
    o += hbox(14, 3, 21, 38, CYN+PBG, PBG)
    o += p(14, 5, " ACCOUNTS ", CYN, BOLD, PBG)
    accts = [
        ("░ Checking",  "$4,521.30",  CYN),
        ("▒ Savings",   "$32,100.00", MAG),
        ("▓ Invest.",   "$91,221.26", GRN),
    ]
    for i, (name, amt, clr) in enumerate(accts):
        r = 16 + i*2
        o += p(r, 6, name, clr, PBG)
        o += p(r, 20, amt, WHT, PBG)

    # --- Categories ---
    o += hbox(14, 42, 21, 78, MAG+PBG, PBG)
    o += p(14, 44, " SPENDING ", MAG, BOLD, PBG)
    cats = [
        ("Housing",    1200, 28, PNK),
        ("Food",        642, 15, MAG),
        ("Transport",   380,  9, CYN),
        ("Utilities",   245,  6, BLU),
        ("Entertain.",  180,  4, GRN),
        ("Health",      120,  3, YLW),
    ]
    for i, (name, amt, bw, clr) in enumerate(cats):
        r = 16 + i
        o += p(r, 45, f"{name:<11}", WHT, PBG)
        o += p(r, 57, "▓"*bw, clr, PBG)

    # --- Transactions ---
    o += hbox(23, 3, 37, 38, CYN+PBG, PBG)
    o += p(23, 5, " RECENT ", CYN, BOLD, PBG)
    txns = [
        ("Whole Foods",  "-$84.32",  PNK),
        ("Transfer",     "+$200.00", GRN),
        ("Amazon",       "-$34.99",  PNK),
        ("Spotify",      "-$9.99",   PNK),
        ("Coffee",       "-$5.50",   PNK),
        ("Gas station",  "-$52.00",  PNK),
        ("Restaurant",   "-$67.80",  PNK),
    ]
    for i, (name, amt, clr) in enumerate(txns):
        r = 25 + i*2 if i < 4 else 25 + 7 + (i-4)
        if i < 6:
            r = 25 + i*2
            o += p(r, 6, name, WHT, PBG)
            o += p(r, 22, amt, clr, PBG)

    # --- Investments ---
    o += hbox(23, 42, 37, 78, MAG+PBG, PBG)
    o += p(23, 44, " PORTFOLIO ", MAG, BOLD, PBG)
    invs = [
        ("STOCKS", "$62,450", "▁▂▃▄▅▆▇█", "+14.2%", CYN),
        ("BONDS",  "$18,220", "▅▅▆▆▆▇▇█", "+ 3.1%", BLU),
        ("CRYPTO", "$10,550", "▂▄▅▃▆▇██", "+28.7%", GRN),
    ]
    for i, (name, amt, spark, pct, clr) in enumerate(invs):
        r = 25 + i*4
        o += p(r, 45, name, clr, BOLD, PBG)
        o += p(r, 54, amt, WHT, PBG)
        o += p(r, 64, pct, GRN, PBG)
        o += p(r+1, 45, spark, clr, PBG)
        o += p(r+1, 54, "━"*20, DM, PBG)

    # Status bar
    o += p(39, 3, "░▒▓", MAG, BG)
    o += p(39, 7, "3 accounts synced", DM, BG)
    o += p(39, 50, "last sync: 2 min ago", DM, BG)
    o += p(39, 75, "▓▒░", CYN, BG)

    o += finish()
    return o


# ============================================================
# DESIGN 4: MODERN (Clean Cards / Catppuccin)
# ============================================================
def design_modern():
    BG   = bg(30,30,46)
    CBG  = bg(49,50,68)
    SBG  = bg(69,71,90)
    FG   = fg(205,214,244)
    SUB  = fg(166,173,200)
    OVR  = fg(108,112,134)
    MAU  = fg(203,166,247)
    BLU  = fg(137,180,250)
    GRN  = fg(166,227,161)
    RED  = fg(243,139,168)
    PCH  = fg(250,179,135)
    YLW  = fg(249,226,175)
    TEA  = fg(148,226,213)
    PNK  = fg(245,194,231)
    LAV  = fg(180,190,254)

    o = setup(BG)

    # Title bar
    o += p(2, 4, "groschen", MAU, BOLD, BG)
    o += p(2, 30, "dashboard", BLU, ULINE, BG)
    o += p(2, 42, "accounts", OVR, BG)
    o += p(2, 53, "budget", OVR, BG)
    o += p(2, 62, "investments", OVR, BG)
    o += p(3, 30, "─────────", BLU, BG)

    # --- Top Cards Row: Net Worth | Income | Savings Rate ---
    # Net Worth Card
    o += rbox(5, 3, 11, 28, OVR+CBG, CBG)
    o += p(6, 6, "Net Worth", SUB, CBG)
    o += p(7, 6, "$127,842", FG, BOLD, CBG)
    o += p(8, 6, "▁▂▃▃▄▅▅▆▇█", BLU, CBG)
    o += p(9, 6, "↑ 1.9%", GRN, CBG)
    o += p(9, 14, "this month", OVR, CBG)

    # Income Card
    o += rbox(5, 30, 11, 53, OVR+CBG, CBG)
    o += p(6, 33, "Monthly Income", SUB, CBG)
    o += p(7, 33, "$6,200", GRN, BOLD, CBG)
    o += p(9, 33, "Expenses", OVR, CBG)
    o += p(9, 43, "$3,859", RED, CBG)

    # Savings Card
    o += rbox(5, 55, 11, 78, OVR+CBG, CBG)
    o += p(6, 58, "Saved", SUB, CBG)
    o += p(7, 58, "$2,341", TEA, BOLD, CBG)
    o += p(9, 58, "◐", TEA, CBG)
    o += p(9, 60, "37.8% rate", OVR, CBG)

    # --- Categories Card ---
    o += rbox(13, 3, 27, 40, OVR+CBG, CBG)
    o += p(13, 5, " Spending ", OVR, BOLD, CBG)
    cats = [
        ("Housing",     "$1,200", 14, PCH),
        ("Food",          "$642",  8, YLW),
        ("Transport",     "$380",  5, BLU),
        ("Utilities",     "$246",  3, TEA),
        ("Entertain.",    "$180",  2, MAU),
        ("Health",        "$120",  2, PNK),
    ]
    for i, (name, amt, bw, clr) in enumerate(cats):
        r = 15 + i*2
        o += p(r, 6, "●", clr, CBG)
        o += p(r, 8, name, FG, CBG)
        o += p(r, 20, amt, SUB, CBG)
        o += p(r, 28, "█"*bw, clr, CBG)

    # --- Transactions Card ---
    o += rbox(13, 42, 27, 78, OVR+CBG, CBG)
    o += p(13, 44, " Transactions ", OVR, BOLD, CBG)
    txns = [
        ("Whole Foods",   "-$84.32",  "Food",     YLW),
        ("Transfer",      "+$200.00", "Income",   GRN),
        ("Amazon",        "-$34.99",  "Shop",     LAV),
        ("Spotify",       "-$9.99",   "Fun",      MAU),
        ("Coffee",        "-$5.50",   "Food",     YLW),
        ("Gas station",   "-$52.00",  "Transit",  BLU),
        ("Restaurant",    "-$67.80",  "Food",     YLW),
    ]
    for i, (name, amt, cat, clr) in enumerate(txns):
        r = 15 + i*2 if i < 7 else 0
        if r > 0 and r < 27:
            aclr = GRN if "+" in amt else RED
            o += p(r, 45, "●", clr, CBG)
            o += p(r, 47, name, FG, CBG)
            o += p(r, 62, amt, aclr, CBG)

    # --- Investments Card ---
    o += rbox(29, 3, 37, 78, OVR+CBG, CBG)
    o += p(29, 5, " Portfolio ", OVR, BOLD, CBG)
    invs = [
        ("Stocks",  "$62,450", "+14.2%", "▁▂▃▄▅▆▇█", GRN,  18),
        ("Bonds",   "$18,220", "+ 3.1%", "▅▅▆▆▆▇▇█", BLU,  18),
        ("Crypto",  "$10,550", "+28.7%", "▂▄▅▃▆▇██", PCH,  18),
    ]
    for i, (name, amt, pct, spark, clr, col_start) in enumerate(invs):
        c = 6 + i * 25
        o += p(31, c, name, SUB, CBG)
        o += p(32, c, amt, FG, BOLD, CBG)
        o += p(33, c, spark, clr, CBG)
        o += p(34, c, pct, GRN, CBG)

    # Bottom status
    o += p(39, 4, "●", GRN, BG)
    o += p(39, 6, "3 accounts connected", OVR, BG)
    o += p(39, 58, "Last sync: just now", OVR, BG)

    o += finish()
    return o


# ============================================================
# DESIGN 5: BRUTAL (Monochrome Brutalist)
# ============================================================
def design_brutal():
    BG  = bg(0,0,0)
    FG  = fg(255,255,255)
    GRY = fg(160,160,160)
    DK  = fg(80,80,80)
    WBG = bg(255,255,255)
    BFG = fg(0,0,0)

    o = setup(BG)

    # Title - inverse bar
    o += p(1, 1, " "*80, WBG)
    o += p(1, 3, "GROSCHEN", BFG, BOLD, WBG)
    o += p(1, 40, "FINANCIAL OVERVIEW", BFG, WBG)
    o += p(1, 72, "APR 2025", BFG, WBG)

    # Navigation - inverse active tab
    o += p(2, 1, " "*80, BG)
    o += p(2, 2, " OVERVIEW ", FG, BOLD, REVERSE)
    o += p(2, 14, "ACCOUNTS", DK, BG)
    o += p(2, 25, "BUDGET", DK, BG)
    o += p(2, 34, "INVESTMENTS", DK, BG)
    o += p(2, 48, "HISTORY", DK, BG)

    # Heavy rule
    o += p(3, 1, "━"*80, GRY, BG)

    # Net Worth - big and bold
    o += p(5, 3, "NET WORTH", DK, BG)
    o += p(6, 3, "$127,842.56", FG, BOLD, BG)
    o += p(6, 18, "▁▂▃▃▄▅▅▆▆▇▇█", GRY, BG)
    o += p(6, 35, "+$2,341.20", FG, BG)
    o += p(6, 48, "(+1.9%)", GRY, BG)
    o += p(7, 3, "━"*75, DK, BG)

    # 3-column layout: Accounts | Monthly | Allocation
    col1, col2, col3 = 3, 29, 55
    o += p(9, col1, "ACCOUNTS", FG, BOLD, BG)
    o += p(9, col2, "MONTHLY", FG, BOLD, BG)
    o += p(9, col3, "ALLOCATION", FG, BOLD, BG)
    o += p(10, col1, "─"*24, DK, BG)
    o += p(10, col2, "─"*24, DK, BG)
    o += p(10, col3, "─"*24, DK, BG)

    o += p(11, col1, "Checking", GRY, BG)
    o += p(11, col1+14, "$4,521", FG, BG)
    o += p(12, col1, "Savings", GRY, BG)
    o += p(12, col1+13, "$32,100", FG, BG)
    o += p(13, col1, "Investment", GRY, BG)
    o += p(13, col1+13, "$91,221", FG, BG)

    o += p(11, col2, "Income", GRY, BG)
    o += p(11, col2+12, "$6,200", FG, BG)
    o += p(12, col2, "Expenses", GRY, BG)
    o += p(12, col2+12, "$3,859", FG, BG)
    o += p(13, col2, "─"*18, DK, BG)
    o += p(14, col2, "Net", GRY, BG)
    o += p(14, col2+12, "$2,341", FG, BOLD, BG)

    # Allocation bars
    allocs = [
        ("STOCKS", 49, "█"*10),
        ("BONDS",  14, "█"*3),
        ("CRYPTO",  8, "██"),
        ("CASH",   29, "██████"),
    ]
    for i, (name, pct, bar) in enumerate(allocs):
        r = 11 + i
        o += p(r, col3, bar, FG, BG)
        o += p(r, col3+12, name, GRY, BG)
        o += p(r, col3+20, f"{pct}%", FG, BG)

    o += p(16, 3, "━"*75, DK, BG)

    # Expenses
    o += p(17, 3, "EXPENSES", FG, BOLD, BG)
    o += p(17, 40, "TOTAL: $3,858.80", GRY, BG)
    o += p(18, 3, "─"*75, DK, BG)
    expenses = [
        ("Housing",     1200, 31),
        ("Food",         642, 17),
        ("Transport",    380, 10),
        ("Utilities",    246,  6),
        ("Entertainment",180,  5),
        ("Health",       120,  3),
    ]
    maxbar = 40
    for i, (name, amt, pct) in enumerate(expenses):
        r = 19 + i
        bw = int(pct / 31 * maxbar)
        o += p(r, 3, f"{name:<15}", GRY, BG)
        o += p(r, 19, "█"*bw, FG, BG)
        o += p(r, 19+bw, "░"*(maxbar-bw), DK, BG)
        o += p(r, 61, f"${amt:>7,.2f}", FG, BG)
        o += p(r, 72, f"{pct:>3d}%", DK, BG)

    o += p(26, 3, "━"*75, DK, BG)

    # Transactions
    o += p(27, 3, "TRANSACTIONS", FG, BOLD, BG)
    o += p(28, 3, "─"*75, DK, BG)
    o += p(29, 3, "DATE", DK, BG)
    o += p(29, 11, "DESCRIPTION", DK, BG)
    o += p(29, 35, "CATEGORY", DK, BG)
    o += p(29, 55, "AMOUNT", DK, BG)

    txns = [
        ("04/08", "Whole Foods",    "Food",      "- $84.32"),
        ("04/08", "Bank Transfer",  "Transfer",  "+$200.00"),
        ("04/07", "Amazon.com",     "Shopping",  "- $34.99"),
        ("04/07", "Spotify",        "Entertain", "-  $9.99"),
        ("04/07", "Starbucks",      "Food",      "-  $5.50"),
        ("04/05", "Shell Oil",      "Transport", "- $52.00"),
        ("04/05", "Olive Garden",   "Food",      "- $67.80"),
    ]
    for i, (date, desc, cat, amt) in enumerate(txns):
        r = 30 + i
        o += p(r, 3, date, DK, BG)
        o += p(r, 11, desc, FG, BG)
        o += p(r, 35, cat, DK, BG)
        clr = FG if "+" in amt else GRY
        o += p(r, 55, amt, clr, BG)

    # Bottom rule + status
    o += p(38, 3, "━"*75, DK, BG)
    o += p(39, 1, " "*80, WBG)
    o += p(39, 3, "3 ACCOUNTS", BFG, WBG)
    o += p(39, 16, "│", BFG, WBG)
    o += p(39, 18, "SYNCED", BFG, WBG)
    o += p(39, 27, "│", BFG, WBG)
    o += p(39, 29, "LAST UPDATE: 2 MIN AGO", BFG, WBG)

    o += finish()
    return o


# ============================================================
# MAIN
# ============================================================
def main():
    designs = [
        ("01-zen.ansi",    design_zen,    "Zen (Nordic Minimalist)"),
        ("02-amber.ansi",  design_amber,  "Amber (Retro CRT Terminal)"),
        ("03-neon.ansi",   design_neon,   "Neon (Cyberpunk)"),
        ("04-modern.ansi", design_modern, "Modern (Clean Cards)"),
        ("05-brutal.ansi", design_brutal, "Brutal (Monochrome)"),
    ]
    outdir = os.path.dirname(os.path.abspath(__file__))
    for fname, fn, label in designs:
        path = os.path.join(outdir, fname)
        with open(path, 'w') as f:
            f.write(fn())
        print(f"  ✓ {fname:<20} {label}")

if __name__ == "__main__":
    main()
