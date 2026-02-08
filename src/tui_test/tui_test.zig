const std = @import("std");
const grid = @import("grid.zig");
const basic_ui = @import("basic_ui.zig");
const scroll = @import("scroll.zig");
const widgets = @import("widgets.zig");

const tests = .{
    .{ "grid", grid.run },
    .{ "basic_ui", basic_ui.run },
    .{ "scroll", scroll.run },
    .{ "widgets", widgets.run },
};

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const name = args.next() orelse {
        print_usage();
        return;
    };

    inline for (tests) |t| {
        if (std.mem.eql(u8, name, t[0])) {
            return t[1]();
        }
    }

    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "unknown test: {s}\n\n", .{name}) catch "unknown test\n\n";
    const stderr: std.fs.File = .{ .handle = std.posix.STDERR_FILENO };
    stderr.writeAll(msg) catch {};
    print_usage();
}

fn print_usage() void {
    const stderr: std.fs.File = .{ .handle = std.posix.STDERR_FILENO };
    stderr.writeAll("usage: tui-test <name>\n\navailable tests:\n") catch return;
    inline for (tests) |t| {
        stderr.writeAll("  " ++ t[0] ++ "\n") catch return;
    }
}

test {
    std.testing.refAllDecls(@This());
}
