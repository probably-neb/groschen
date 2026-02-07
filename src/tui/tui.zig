const std = @import("std");
pub const term = @import("term.zig");

test {
    std.testing.refAllDecls(@This());
}
