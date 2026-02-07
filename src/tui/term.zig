const std = @import("std");
const base = @import("base");
const Arena = base.Arena;
const posix = std.posix;
const c = std.c;

// ---------------------------------------------------------------------------
// Terminal escape sequences
// ---------------------------------------------------------------------------

const mode = struct {
    const alt_screen_enter = "\x1b[?1049h";
    const alt_screen_exit = "\x1b[?1049l";
    const cursor_hide = "\x1b[?25l";
    const cursor_show = "\x1b[?25h";
    const mouse_button_on = "\x1b[?1002h";
    const mouse_button_off = "\x1b[?1002l";
    const mouse_sgr_on = "\x1b[?1006h";
    const mouse_sgr_off = "\x1b[?1006l";
    const bracketed_paste_on = "\x1b[?2004h";
    const bracketed_paste_off = "\x1b[?2004l";

    const enter_all = alt_screen_enter ++ cursor_hide ++ mouse_button_on ++ mouse_sgr_on ++ bracketed_paste_on;
    const exit_all = mouse_sgr_off ++ mouse_button_off ++ bracketed_paste_off ++ cursor_show ++ alt_screen_exit;
};

const sgr = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
    const italic = "\x1b[3m";
    const underline = "\x1b[4m";
    const reverse = "\x1b[7m";
    const strikethrough = "\x1b[9m";
    const default_fg = "\x1b[39m";
    const default_bg = "\x1b[49m";

    const fg_base: u16 = 30;
    const bg_base: u16 = 40;
    const bright_fg_base: u16 = 90;
    const bright_bg_base: u16 = 100;
    const fg_extended: u8 = 38;
    const bg_extended: u8 = 48;
};

const mouse_bits = struct {
    const shift: u16 = 4;
    const alt: u16 = 8;
    const ctrl: u16 = 16;
    const motion: u16 = 32;
    const scroll: u16 = 64;
    const button_mask: u16 = 0x43;
};

const xterm_mod_bits = struct {
    const shift: u16 = 1;
    const alt: u16 = 2;
    const ctrl: u16 = 4;
};

const paste_start = "200~";
const paste_end = "\x1b[201~";

const default_cols: u16 = 80;
const default_rows: u16 = 24;

// ---------------------------------------------------------------------------
// Color / Attrs / Cell
// ---------------------------------------------------------------------------

pub const Ansi = enum(u8) {
    black = 0,
    red = 1,
    green = 2,
    yellow = 3,
    blue = 4,
    magenta = 5,
    cyan = 6,
    white = 7,
    bright_black = 8,
    bright_red = 9,
    bright_green = 10,
    bright_yellow = 11,
    bright_blue = 12,
    bright_magenta = 13,
    bright_cyan = 14,
    bright_white = 15,
    _,
};

pub const Color = union(enum) {
    default,
    ansi: Ansi,
    rgb: [3]u8,

    pub fn eql(a: Color, b: Color) bool {
        const tag_a: u2 = switch (a) {
            .default => 0,
            .ansi => 1,
            .rgb => 2,
        };
        const tag_b: u2 = switch (b) {
            .default => 0,
            .ansi => 1,
            .rgb => 2,
        };
        if (tag_a != tag_b) return false;
        return switch (a) {
            .default => true,
            .ansi => |v| @intFromEnum(v) == @intFromEnum(b.ansi),
            .rgb => |v| v[0] == b.rgb[0] and v[1] == b.rgb[1] and v[2] == b.rgb[2],
        };
    }
};

pub const Attrs = packed struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    reverse: bool = false,
    strikethrough: bool = false,
    _pad: u2 = 0,

    pub fn eql(a: Attrs, b: Attrs) bool {
        return @as(u8, @bitCast(a)) == @as(u8, @bitCast(b));
    }
};

pub const Cell = struct {
    codepoint: u21 = ' ',
    fg: Color = .default,
    bg: Color = .default,
    attrs: Attrs = .{},

    pub fn eql(a: Cell, b: Cell) bool {
        return a.codepoint == b.codepoint and
            a.fg.eql(b.fg) and
            a.bg.eql(b.bg) and
            a.attrs.eql(b.attrs);
    }
};

const blank_cell: Cell = .{};

// ---------------------------------------------------------------------------
// Key / Modifiers / Events
// ---------------------------------------------------------------------------

pub const Key = enum {
    none,
    // printable mapped as codepoint
    codepoint,
    // special keys
    escape,
    enter,
    tab,
    backspace,
    insert,
    delete,
    home,
    end,
    page_up,
    page_down,
    up,
    down,
    left,
    right,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
};

pub const Modifiers = packed struct {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
    _pad: u5 = 0,

    pub const none: Modifiers = .{};

    pub fn eql(a: Modifiers, b: Modifiers) bool {
        return @as(u8, @bitCast(a)) == @as(u8, @bitCast(b));
    }
};

pub const KeyEvent = struct {
    key: Key = .none,
    codepoint: u21 = 0,
    mods: Modifiers = .{},
};

pub const MouseKind = enum { press, release, move, scroll_up, scroll_down };
pub const MouseButton = enum { left, middle, right, none };

pub const MouseEvent = struct {
    kind: MouseKind = .press,
    button: MouseButton = .none,
    col: u16 = 0,
    row: u16 = 0,
    mods: Modifiers = .{},
};

pub const InputEvent = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    resize,
};

// ---------------------------------------------------------------------------
// Global signal state
// ---------------------------------------------------------------------------

var resize_pending: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var global_tty_fd: posix.fd_t = -1;
var global_original_termios: posix.termios = undefined;
var global_installed: bool = false;

fn handle_sigwinch(_: c_int) callconv(.c) void {
    resize_pending.store(true, .release);
}

fn handle_fatal_signal(sig: c_int) callconv(.c) void {
    emergency_cleanup();
    const default_sa: posix.Sigaction = .{
        .handler = .{ .handler = posix.SIG.DFL },
        .mask = 0,
        .flags = 0,
    };
    posix.sigaction(@intCast(sig), &default_sa, null);
    _ = c.raise(sig);
}

fn emergency_cleanup() void {
    if (global_tty_fd < 0) return;
    const tty: std.fs.File = .{ .handle = global_tty_fd };
    tty.writeAll(mode.exit_all) catch {};
    posix.tcsetattr(global_tty_fd, .FLUSH, global_original_termios) catch {};
}

// ---------------------------------------------------------------------------
// Term
// ---------------------------------------------------------------------------

pub const Term = struct {
    tty_fd: posix.fd_t,
    tty: std.fs.File,
    original_termios: posix.termios,
    cols: u16,
    rows: u16,
    front: []Cell,
    back: []Cell,
    arena: *Arena,
    input_buf: [256]u8 = undefined,
    input_len: usize = 0,
    input_pos: usize = 0,

    pub const InitError = Arena.InitError || Arena.AllocError || posix.TermiosGetError || posix.TermiosSetError;

    pub fn init(arena: *Arena) InitError!Term {
        const fd = posix.open("/dev/tty", .{ .ACCMODE = .RDWR }, 0) catch posix.STDIN_FILENO;
        const original_termios = try posix.tcgetattr(fd);

        var raw = original_termios;
        raw.iflag.BRKINT = false;
        raw.iflag.ICRNL = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;
        raw.iflag.IXON = false;
        raw.oflag.OPOST = false;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.IEXTEN = false;
        raw.lflag.ISIG = false;
        raw.cflag.CSIZE = @enumFromInt(3); // CS8
        raw.cc[@intFromEnum(c.V.MIN)] = 0;
        raw.cc[@intFromEnum(c.V.TIME)] = 0;
        try posix.tcsetattr(fd, .FLUSH, raw);

        global_tty_fd = fd;
        global_original_termios = original_termios;

        if (!global_installed) {
            const winch_sa: posix.Sigaction = .{
                .handler = .{ .handler = &handle_sigwinch },
                .mask = 0,
                .flags = 0,
            };
            posix.sigaction(posix.SIG.WINCH, &winch_sa, null);

            const fatal_sa: posix.Sigaction = .{
                .handler = .{ .handler = &handle_fatal_signal },
                .mask = 0,
                .flags = 0,
            };
            posix.sigaction(posix.SIG.TERM, &fatal_sa, null);
            posix.sigaction(posix.SIG.HUP, &fatal_sa, null);
            posix.sigaction(posix.SIG.INT, &fatal_sa, null);
            global_installed = true;
        }

        const tty: std.fs.File = .{ .handle = fd };
        tty.writeAll(mode.enter_all) catch {};

        const size = query_size(fd);
        const total = @as(usize, size.cols) * @as(usize, size.rows);
        const front = try arena.alloc(Cell, total);
        const back = try arena.alloc(Cell, total);
        @memset(front, blank_cell);
        @memset(back, blank_cell);

        return .{
            .tty_fd = fd,
            .tty = tty,
            .original_termios = original_termios,
            .cols = size.cols,
            .rows = size.rows,
            .front = front,
            .back = back,
            .arena = arena,
        };
    }

    pub fn deinit(self: *Term) void {
        self.tty.writeAll(mode.exit_all) catch {};
        posix.tcsetattr(self.tty_fd, .FLUSH, self.original_termios) catch {};
        global_tty_fd = -1;
    }

    // -- Grid operations ----------------------------------------------------

    pub fn cell_at(self: *Term, col: u16, row: u16) ?*Cell {
        if (col >= self.cols or row >= self.rows) return null;
        return &self.back[@as(usize, row) * @as(usize, self.cols) + @as(usize, col)];
    }

    pub fn fill_rect(self: *Term, x: u16, y: u16, w: u16, h: u16, cell: Cell) void {
        const x_end = @min(@as(u32, x) + w, self.cols);
        const y_end = @min(@as(u32, y) + h, self.rows);
        var row: u32 = y;
        while (row < y_end) : (row += 1) {
            var col: u32 = x;
            while (col < x_end) : (col += 1) {
                const idx = row * @as(u32, self.cols) + col;
                self.back[idx] = cell;
            }
        }
    }

    pub fn write_text(self: *Term, col: u16, row: u16, max_width: u16, text: []const u8, fg: Color, bg: Color, attrs: Attrs) u16 {
        if (row >= self.rows or col >= self.cols) return 0;
        const limit: u16 = @min(col +| max_width, self.cols);
        var cur_col: u16 = col;
        var i: usize = 0;
        while (i < text.len and cur_col < limit) {
            const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch {
                i += 1;
                continue;
            };
            if (i + cp_len > text.len) break;
            const cp = std.unicode.utf8Decode(text[i..][0..cp_len]) catch {
                i += cp_len;
                continue;
            };
            const w = codepoint_width(cp);
            if (w == 0) {
                i += cp_len;
                continue;
            }
            if (cur_col + w > limit) break;
            const idx = @as(usize, row) * @as(usize, self.cols) + @as(usize, cur_col);
            self.back[idx] = .{ .codepoint = cp, .fg = fg, .bg = bg, .attrs = attrs };
            if (w == 2 and cur_col + 1 < self.cols) {
                self.back[idx + 1] = .{ .codepoint = 0, .fg = fg, .bg = bg, .attrs = attrs };
            }
            cur_col += w;
            i += cp_len;
        }
        return cur_col - col;
    }

    pub fn clear(self: *Term) void {
        @memset(self.back, blank_cell);
    }

    // -- Resize -------------------------------------------------------------

    pub fn check_resize(self: *Term) !bool {
        if (!resize_pending.swap(false, .acquire)) return false;
        const size = query_size(self.tty_fd);
        if (size.cols == self.cols and size.rows == self.rows) return false;
        self.cols = size.cols;
        self.rows = size.rows;
        const total = @as(usize, size.cols) * @as(usize, size.rows);
        self.front = try self.arena.alloc(Cell, total);
        self.back = try self.arena.alloc(Cell, total);
        @memset(self.front, blank_cell);
        @memset(self.back, blank_cell);
        return true;
    }

    // -- Flush (diff + ANSI output) -----------------------------------------

    pub fn flush(self: *Term) !void {
        const scratch = Arena.get_scratch(&.{self.arena});
        defer scratch.release();
        const a = scratch.arena;
        const start = a.get_pos();

        var cur_fg: Color = .default;
        var cur_bg: Color = .default;
        var cur_attrs: Attrs = .{};
        var cursor_row: u16 = 0;
        var cursor_col: u16 = 0;
        var cursor_valid = false;

        try emit(a, mode.cursor_hide);

        for (0..self.rows) |r| {
            const row: u16 = @intCast(r);
            for (0..self.cols) |cl| {
                const col: u16 = @intCast(cl);
                const idx = @as(usize, row) * @as(usize, self.cols) + @as(usize, col);
                const back_cell = self.back[idx];
                const front_cell = self.front[idx];

                if (back_cell.eql(front_cell)) {
                    cursor_valid = false;
                    continue;
                }

                if (back_cell.codepoint == 0) {
                    cursor_valid = false;
                    continue;
                }

                if (!cursor_valid or cursor_row != row or cursor_col != col) {
                    try emit_cup(a, row, col);
                }

                try emit_sgr(a, back_cell, &cur_fg, &cur_bg, &cur_attrs);

                var cp_buf: [4]u8 = undefined;
                const cp_len = std.unicode.utf8Encode(back_cell.codepoint, &cp_buf) catch 1;
                try emit(a, cp_buf[0..cp_len]);

                const w = codepoint_width(back_cell.codepoint);
                cursor_row = row;
                cursor_col = col +| w;
                cursor_valid = true;
            }
        }

        if (cur_fg != .default or cur_bg != .default or !cur_attrs.eql(.{})) {
            try emit(a, sgr.reset);
        }

        const end = a.get_pos();
        if (end > start) {
            try self.tty.writeAll(a.memory[start..end]);
        }

        const tmp = self.front;
        self.front = self.back;
        self.back = tmp;
    }

    fn emit(arena: *Arena, bytes: []const u8) Arena.AllocError!void {
        const dest = try arena.push(bytes.len);
        @memcpy(dest, bytes);
    }

    fn emit_fmt(arena: *Arena, comptime fmt: []const u8, args: anytype) Arena.AllocError!void {
        var tmp: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, fmt, args) catch unreachable;
        try emit(arena, s);
    }

    fn emit_cup(arena: *Arena, row: u16, col: u16) Arena.AllocError!void {
        try emit_fmt(arena, "\x1b[{};{}H", .{ @as(u32, row) + 1, @as(u32, col) + 1 });
    }

    fn emit_sgr(arena: *Arena, cell: Cell, cur_fg: *Color, cur_bg: *Color, cur_attrs: *Attrs) Arena.AllocError!void {
        const need_reset = (cur_attrs.bold and !cell.attrs.bold) or
            (cur_attrs.dim and !cell.attrs.dim) or
            (cur_attrs.italic and !cell.attrs.italic) or
            (cur_attrs.underline and !cell.attrs.underline) or
            (cur_attrs.reverse and !cell.attrs.reverse) or
            (cur_attrs.strikethrough and !cell.attrs.strikethrough);

        if (need_reset) {
            try emit(arena, sgr.reset);
            cur_fg.* = .default;
            cur_bg.* = .default;
            cur_attrs.* = .{};
        }

        if (cell.attrs.bold and !cur_attrs.bold) try emit(arena, sgr.bold);
        if (cell.attrs.dim and !cur_attrs.dim) try emit(arena, sgr.dim);
        if (cell.attrs.italic and !cur_attrs.italic) try emit(arena, sgr.italic);
        if (cell.attrs.underline and !cur_attrs.underline) try emit(arena, sgr.underline);
        if (cell.attrs.reverse and !cur_attrs.reverse) try emit(arena, sgr.reverse);
        if (cell.attrs.strikethrough and !cur_attrs.strikethrough) try emit(arena, sgr.strikethrough);
        cur_attrs.* = cell.attrs;

        if (!cell.fg.eql(cur_fg.*)) {
            try emit_color(arena, cell.fg, false);
            cur_fg.* = cell.fg;
        }
        if (!cell.bg.eql(cur_bg.*)) {
            try emit_color(arena, cell.bg, true);
            cur_bg.* = cell.bg;
        }
    }

    fn emit_color(arena: *Arena, color: Color, is_bg: bool) Arena.AllocError!void {
        const ext = @as(u8, if (is_bg) sgr.bg_extended else sgr.fg_extended);
        switch (color) {
            .default => try emit(arena, if (is_bg) sgr.default_bg else sgr.default_fg),
            .ansi => |v| {
                const n = @intFromEnum(v);
                if (n < 8) {
                    try emit_fmt(arena, "\x1b[{}m", .{(if (is_bg) sgr.bg_base else sgr.fg_base) + n});
                } else if (n < 16) {
                    try emit_fmt(arena, "\x1b[{}m", .{(if (is_bg) sgr.bright_bg_base else sgr.bright_fg_base) + n - 8});
                } else {
                    try emit_fmt(arena, "\x1b[{};5;{}m", .{ ext, n });
                }
            },
            .rgb => |v| try emit_fmt(arena, "\x1b[{};2;{};{};{}m", .{ ext, v[0], v[1], v[2] }),
        }
    }

    // -- Input parsing ------------------------------------------------------

    pub fn poll_event(self: *Term, timeout_ms: i32) !?InputEvent {
        if (resize_pending.load(.acquire)) return .resize;

        if (self.input_pos < self.input_len) {
            return self.drain_next();
        }

        var fds = [_]posix.pollfd{.{
            .fd = self.tty_fd,
            .events = posix.POLL.IN,
            .revents = 0,
        }};
        const n = try posix.poll(&fds, timeout_ms);
        if (n == 0) return null;

        const bytes_read = self.tty.read(&self.input_buf) catch |err| switch (err) {
            error.WouldBlock => return null,
            else => return err,
        };
        if (bytes_read == 0) return null;
        self.input_len = bytes_read;
        self.input_pos = 0;

        return self.drain_next();
    }

    fn drain_next(self: *Term) ?InputEvent {
        while (self.input_pos < self.input_len) {
            const buf = self.input_buf[self.input_pos..self.input_len];
            const result = parse_input(buf);
            self.input_pos += result.consumed;
            if (result.event) |ev| return ev;
            if (result.consumed == 0) return null;
        }
        return null;
    }
};

const ParseResult = struct {
    event: ?InputEvent,
    consumed: usize,
};

fn parse_input(buf: []const u8) ParseResult {
    if (buf.len == 0) return .{ .event = null, .consumed = 0 };

    if (is_escape(buf[0])) {
        if (buf.len == 1) return .{ .event = .{ .key = .{ .key = .escape } }, .consumed = 1 };
        if (buf[1] == '[') return parse_csi(buf);
        if (buf[1] == 'O') return parse_ss3(buf);
        const ke = char_to_key_event(buf[1]);
        return .{
            .event = .{ .key = .{
                .key = ke.key,
                .codepoint = ke.codepoint,
                .mods = .{ .alt = true, .shift = ke.mods.shift, .ctrl = ke.mods.ctrl },
            } },
            .consumed = 2,
        };
    }

    if (is_newline(buf[0])) return .{ .event = .{ .key = .{ .key = .enter } }, .consumed = 1 };
    if (is_tab(buf[0])) return .{ .event = .{ .key = .{ .key = .tab } }, .consumed = 1 };
    if (is_backspace(buf[0])) return .{ .event = .{ .key = .{ .key = .backspace } }, .consumed = 1 };
    if (is_ctrl_char(buf[0])) return .{
        .event = .{ .key = .{
            .key = .codepoint,
            .codepoint = ctrl_to_letter(buf[0]),
            .mods = .{ .ctrl = true },
        } },
        .consumed = 1,
    };

    const cp_len = std.unicode.utf8ByteSequenceLength(buf[0]) catch return .{ .event = null, .consumed = 1 };
    if (cp_len > buf.len) return .{ .event = null, .consumed = buf.len };
    const cp = std.unicode.utf8Decode(buf[0..cp_len]) catch return .{ .event = null, .consumed = cp_len };
    return .{
        .event = .{ .key = .{ .key = .codepoint, .codepoint = cp } },
        .consumed = cp_len,
    };
}

fn parse_csi(buf: []const u8) ParseResult {
    if (buf.len < 3) return .{ .event = .{ .key = .{ .key = .escape } }, .consumed = buf.len };

    if (buf[2] == '<') return parse_sgr_mouse(buf);

    if (buf.len >= 6 and std.mem.startsWith(u8, buf[2..], paste_start)) {
        const header_len = 2 + paste_start.len;
        if (std.mem.indexOf(u8, buf[header_len..], paste_end)) |offset| {
            return .{ .event = null, .consumed = header_len + offset + paste_end.len };
        }
        return .{ .event = null, .consumed = buf.len };
    }

    var params: [8]u16 = .{0} ** 8;
    var param_count: usize = 0;
    var i: usize = 2;
    while (i < buf.len) : (i += 1) {
        if (is_digit(buf[i])) {
            if (param_count == 0) param_count = 1;
            params[param_count - 1] = params[param_count - 1] *| 10 +| (buf[i] - '0');
        } else if (buf[i] == ';') {
            param_count += 1;
            if (param_count > params.len) break;
        } else if (is_csi_final(buf[i])) {
            break;
        } else {
            break;
        }
    }
    if (i >= buf.len) return .{ .event = .{ .key = .{ .key = .escape } }, .consumed = buf.len };

    const final_byte = buf[i];
    const consumed = i + 1;
    const mods = if (param_count >= 2) decode_xterm_mods(params[1]) else Modifiers{};

    const key_event: KeyEvent = switch (final_byte) {
        'A' => .{ .key = .up, .mods = mods },
        'B' => .{ .key = .down, .mods = mods },
        'C' => .{ .key = .right, .mods = mods },
        'D' => .{ .key = .left, .mods = mods },
        'H' => .{ .key = .home, .mods = mods },
        'F' => .{ .key = .end, .mods = mods },
        'Z' => .{ .key = .tab, .mods = .{ .shift = true } },
        '~' => .{ .key = tilde_param_to_key(params[0]), .mods = mods },
        else => .{ .key = .none },
    };
    return .{ .event = .{ .key = key_event }, .consumed = consumed };
}

fn parse_ss3(buf: []const u8) ParseResult {
    if (buf.len < 3) return .{ .event = .{ .key = .{ .key = .escape } }, .consumed = buf.len };
    const key_event: KeyEvent = .{ .key = switch (buf[2]) {
        'A' => .up,
        'B' => .down,
        'C' => .right,
        'D' => .left,
        'H' => .home,
        'F' => .end,
        'P' => .f1,
        'Q' => .f2,
        'R' => .f3,
        'S' => .f4,
        else => .none,
    } };
    return .{ .event = .{ .key = key_event }, .consumed = 3 };
}

fn parse_sgr_mouse(buf: []const u8) ParseResult {
    var i: usize = 3;
    var params: [3]u16 = .{ 0, 0, 0 };
    var param_idx: usize = 0;
    while (i < buf.len) : (i += 1) {
        if (is_digit(buf[i])) {
            params[param_idx] = params[param_idx] *| 10 +| (buf[i] - '0');
        } else if (buf[i] == ';') {
            param_idx += 1;
            if (param_idx >= 3) break;
        } else if (is_sgr_mouse_final(buf[i])) {
            return .{
                .event = .{ .mouse = decode_sgr_mouse(params, is_mouse_release(buf[i])) },
                .consumed = i + 1,
            };
        } else {
            break;
        }
    }
    return .{ .event = null, .consumed = buf.len };
}

fn decode_sgr_mouse(params: [3]u16, release: bool) MouseEvent {
    const cb = params[0];
    const col: u16 = if (params[1] > 0) params[1] - 1 else 0;
    const row: u16 = if (params[2] > 0) params[2] - 1 else 0;

    const mods: Modifiers = .{
        .shift = cb & mouse_bits.shift != 0,
        .alt = cb & mouse_bits.alt != 0,
        .ctrl = cb & mouse_bits.ctrl != 0,
    };

    const base_button = cb & mouse_bits.button_mask;
    const motion = cb & mouse_bits.motion != 0;
    const scroll = cb & mouse_bits.scroll != 0;

    if (scroll) return .{
        .kind = if (base_button & 1 != 0) .scroll_down else .scroll_up,
        .button = .none,
        .col = col,
        .row = row,
        .mods = mods,
    };

    return .{
        .kind = if (release) .release else if (motion) .move else .press,
        .button = switch (base_button & 3) {
            0 => .left,
            1 => .middle,
            2 => .right,
            else => .none,
        },
        .col = col,
        .row = row,
        .mods = mods,
    };
}

fn tilde_param_to_key(param: u16) Key {
    return switch (param) {
        1 => .home,
        2 => .insert,
        3 => .delete,
        4 => .end,
        5 => .page_up,
        6 => .page_down,
        11 => .f1,
        12 => .f2,
        13 => .f3,
        14 => .f4,
        15 => .f5,
        17 => .f6,
        18 => .f7,
        19 => .f8,
        20 => .f9,
        21 => .f10,
        23 => .f11,
        24 => .f12,
        else => .none,
    };
}

// ---------------------------------------------------------------------------
// Byte classification
// ---------------------------------------------------------------------------

fn is_escape(byte: u8) bool {
    return byte == 0x1b;
}

fn is_newline(byte: u8) bool {
    return byte == '\r' or byte == '\n';
}

fn is_tab(byte: u8) bool {
    return byte == '\t';
}

fn is_backspace(byte: u8) bool {
    return byte == 0x7f;
}

fn is_ctrl_char(byte: u8) bool {
    return byte < 0x20;
}

fn ctrl_to_letter(byte: u8) u21 {
    return @as(u21, byte) + 'a' - 1;
}

fn is_digit(byte: u8) bool {
    return byte >= '0' and byte <= '9';
}

fn is_csi_final(byte: u8) bool {
    return byte >= 0x40 and byte <= 0x7E;
}

fn is_sgr_mouse_final(byte: u8) bool {
    return byte == 'M' or byte == 'm';
}

fn is_mouse_release(byte: u8) bool {
    return byte == 'm';
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn char_to_key_event(byte: u8) KeyEvent {
    if (is_newline(byte)) return .{ .key = .enter };
    if (is_tab(byte)) return .{ .key = .tab };
    if (is_backspace(byte)) return .{ .key = .backspace };
    if (is_ctrl_char(byte)) return .{
        .key = .codepoint,
        .codepoint = ctrl_to_letter(byte),
        .mods = .{ .ctrl = true },
    };
    return .{
        .key = .codepoint,
        .codepoint = @as(u21, byte),
    };
}

fn decode_xterm_mods(param: u16) Modifiers {
    if (param == 0) return .{};
    const v = param -| 1;
    return .{
        .shift = v & xterm_mod_bits.shift != 0,
        .alt = v & xterm_mod_bits.alt != 0,
        .ctrl = v & xterm_mod_bits.ctrl != 0,
    };
}

fn query_size(fd: posix.fd_t) struct { cols: u16, rows: u16 } {
    var ws: c.winsize = .{ .col = 0, .row = 0, .xpixel = 0, .ypixel = 0 };
    _ = c.ioctl(fd, c.T.IOCGWINSZ, @intFromPtr(&ws));
    return .{
        .cols = if (ws.col > 0) ws.col else default_cols,
        .rows = if (ws.row > 0) ws.row else default_rows,
    };
}

fn codepoint_width(cp: u21) u16 {
    if (cp == 0) return 0;
    if (cp < 0x20) return 0;
    if (cp == 0x7f) return 0;
    // CJK Unified Ideographs and common wide ranges
    if ((cp >= 0x1100 and cp <= 0x115F) or
        (cp >= 0x2E80 and cp <= 0x303E) or
        (cp >= 0x3041 and cp <= 0x33BF) or
        (cp >= 0xFE30 and cp <= 0xFE6B) or
        (cp >= 0xFF01 and cp <= 0xFF60) or
        (cp >= 0xFFE0 and cp <= 0xFFE6) or
        (cp >= 0x4E00 and cp <= 0x9FFF) or
        (cp >= 0xF900 and cp <= 0xFAFF) or
        (cp >= 0x20000 and cp <= 0x2FFFD) or
        (cp >= 0x30000 and cp <= 0x3FFFD))
    {
        return 2;
    }
    return 1;
}
