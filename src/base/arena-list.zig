//! ArenaList makes a few different trade-offs compared to std.ArrayList.
//! By requiring backing allocating memory with an arena, we don't have to worry about realloc + memcpy.
//! Instead, we track the high water mark position of the arena that we have reserved, and assert that
//! it hasn't changed when we ask for more space.
//! This gives us the power to reserve a bunch of capacity and then use the arena elsewhere if desired,
//! or bump the arena pointer each time we add an element, thereby avoiding unnecessary allocated capacity
const std = @import("std");
const assert = std.debug.assert;
const Arena = @import("arena.zig");

pub fn ArenaList(comptime T: type) type {
    return ArenaListAligned(T, null);
}

pub fn ArenaListAligned(comptime T: type, comptime alignment: ?std.mem.Alignment) type {
    if (alignment) |a| {
        if (a.toByteUnits() == @alignOf(T)) {
            return ArenaListAligned(T, null);
        }
    }
    return struct {
        const Self = @This();

        items: Slice = &[_]T{},
        capacity: usize = 0,
        saved_arena_pos: usize = 0,

        pub const empty: Self = .{};

        pub const Slice = if (alignment) |a| ([]align(a.toByteUnits()) T) else []T;

        pub fn sentinel_slice(comptime s: T) type {
            return if (alignment) |a| ([:s]align(a.toByteUnits()) T) else [:s]T;
        }

        pub fn init_capacity(arena: *Arena, num: usize) Arena.AllocError!Self {
            var result: Self = .{};
            try result.ensure_total_capacity_precise(arena, num);
            return result;
        }

        pub fn init_buffer(buffer: Slice) Self {
            return .{
                .items = buffer[0..0],
                .capacity = buffer.len,
                .saved_arena_pos = 0,
            };
        }

        pub fn from_owned_slice(slice: Slice) Self {
            return .{
                .items = slice,
                .capacity = slice.len,
                .saved_arena_pos = 0,
            };
        }

        pub fn from_owned_slice_sentinel(comptime sentinel: T, slice: [:sentinel]T) Self {
            return .{
                .items = slice,
                .capacity = slice.len + 1,
                .saved_arena_pos = 0,
            };
        }

        pub fn clone(list: Self, arena: *Arena) Arena.AllocError!Self {
            var cloned = try Self.init_capacity(arena, list.capacity);
            cloned.append_slice_assume_capacity(list.items);
            return cloned;
        }

        pub fn insert(list: *Self, arena: *Arena, i: usize, item: T) Arena.AllocError!void {
            const dst = try list.add_many_at(arena, i, 1);
            dst[0] = item;
        }

        pub fn insert_assume_capacity(list: *Self, i: usize, item: T) void {
            assert(list.items.len < list.capacity);
            list.items.len += 1;
            @memmove(list.items[i + 1 .. list.items.len], list.items[i .. list.items.len - 1]);
            list.items[i] = item;
        }

        pub fn add_many_at(list: *Self, arena: *Arena, index: usize, count: usize) Arena.AllocError![]T {
            const new_len = try add_or_oom(list.items.len, count);

            if (list.capacity >= new_len) {
                return list.add_many_at_assume_capacity(index, count);
            }

            list.assert_arena_contiguity(arena);

            const new_capacity = new_len;
            const additional = new_capacity - list.capacity;
            _ = try arena.push_aligned(additional * @sizeOf(T), @alignOf(T));
            list.saved_arena_pos = arena.pos;
            list.capacity = new_capacity;

            return list.add_many_at_assume_capacity(index, count);
        }

        pub fn add_many_at_assume_capacity(list: *Self, index: usize, count: usize) []T {
            const new_len = list.items.len + count;
            assert(list.capacity >= new_len);
            const to_move = list.items[index..];
            list.items.len = new_len;
            @memmove(list.items[index + count ..][0..to_move.len], to_move);
            const dst = list.items[index..][0..count];
            @memset(dst, @as(T, undefined));
            return dst;
        }

        pub fn insert_slice(list: *Self, arena: *Arena, index: usize, items: []const T) Arena.AllocError!void {
            const dst = try list.add_many_at(arena, index, items.len);
            @memcpy(dst, items);
        }

        pub fn replace_range(list: *Self, arena: *Arena, start: usize, len: usize, new_items: []const T) Arena.AllocError!void {
            const after_range = start + len;
            const range = list.items[start..after_range];
            if (range.len < new_items.len) {
                const first = new_items[0..range.len];
                const rest = new_items[range.len..];
                @memcpy(range[0..first.len], first);
                try list.insert_slice(arena, after_range, rest);
            } else {
                list.replace_range_assume_capacity(start, len, new_items);
            }
        }

        pub fn replace_range_assume_capacity(list: *Self, start: usize, len: usize, new_items: []const T) void {
            const after_range = start + len;
            const range = list.items[start..after_range];

            if (range.len == new_items.len) {
                @memcpy(range[0..new_items.len], new_items);
            } else if (range.len < new_items.len) {
                const first = new_items[0..range.len];
                const rest = new_items[range.len..];
                @memcpy(range[0..first.len], first);
                const dst = list.add_many_at_assume_capacity(after_range, rest.len);
                @memcpy(dst, rest);
            } else {
                const extra = range.len - new_items.len;
                @memcpy(range[0..new_items.len], new_items);
                const src = list.items[after_range..];
                @memmove(list.items[after_range - extra ..][0..src.len], src);
                @memset(list.items[list.items.len - extra ..], @as(T, undefined));
                list.items.len -= extra;
            }
        }

        pub fn append(list: *Self, arena: *Arena, item: T) Arena.AllocError!void {
            const new_item_ptr = try list.add_one(arena);
            new_item_ptr.* = item;
        }

        pub fn append_assume_capacity(list: *Self, item: T) void {
            list.add_one_assume_capacity().* = item;
        }

        pub fn ordered_remove(list: *Self, i: usize) T {
            const old_item = list.items[i];
            list.replace_range_assume_capacity(i, 1, &.{});
            return old_item;
        }

        pub fn ordered_remove_many(list: *Self, sorted_indexes: []const usize) void {
            if (sorted_indexes.len == 0) return;
            var shift: usize = 1;
            for (sorted_indexes[0 .. sorted_indexes.len - 1], sorted_indexes[1..]) |removed, end| {
                if (removed == end) continue;
                const start = removed + 1;
                const len = end - start;
                @memmove(list.items[start - shift ..][0..len], list.items[start..][0..len]);
                shift += 1;
            }
            const start = sorted_indexes[sorted_indexes.len - 1] + 1;
            const end = list.items.len;
            const len = end - start;
            @memmove(list.items[start - shift ..][0..len], list.items[start..][0..len]);
            list.items.len = end - shift;
        }

        pub fn swap_remove(list: *Self, i: usize) T {
            if (list.items.len - 1 == i) return list.pop().?;
            const old_item = list.items[i];
            list.items[i] = list.pop().?;
            return old_item;
        }

        pub fn append_slice(list: *Self, arena: *Arena, items: []const T) Arena.AllocError!void {
            try list.ensure_unused_capacity(arena, items.len);
            list.append_slice_assume_capacity(items);
        }

        pub fn append_slice_assume_capacity(list: *Self, items: []const T) void {
            const old_len = list.items.len;
            const new_len = old_len + items.len;
            assert(new_len <= list.capacity);
            list.items.len = new_len;
            @memcpy(list.items[old_len..][0..items.len], items);
        }

        pub fn append_unaligned_slice(list: *Self, arena: *Arena, items: []align(1) const T) Arena.AllocError!void {
            try list.ensure_unused_capacity(arena, items.len);
            list.append_unaligned_slice_assume_capacity(items);
        }

        pub fn append_unaligned_slice_assume_capacity(list: *Self, items: []align(1) const T) void {
            const old_len = list.items.len;
            const new_len = old_len + items.len;
            assert(new_len <= list.capacity);
            list.items.len = new_len;
            @memcpy(list.items[old_len..][0..items.len], items);
        }

        pub fn append_n_times(list: *Self, arena: *Arena, value: T, n: usize) Arena.AllocError!void {
            const old_len = list.items.len;
            try list.resize(arena, try add_or_oom(old_len, n));
            @memset(list.items[old_len..list.items.len], value);
        }

        pub fn append_n_times_assume_capacity(list: *Self, value: T, n: usize) void {
            const new_len = list.items.len + n;
            assert(new_len <= list.capacity);
            @memset(list.items.ptr[list.items.len..new_len], value);
            list.items.len = new_len;
        }

        pub fn resize(list: *Self, arena: *Arena, new_len: usize) Arena.AllocError!void {
            try list.ensure_total_capacity(arena, new_len);
            list.items.len = new_len;
        }

        pub fn shrink_retaining_capacity(list: *Self, new_len: usize) void {
            assert(new_len <= list.items.len);
            list.items.len = new_len;
        }

        pub fn clear_retaining_capacity(list: *Self) void {
            list.items.len = 0;
        }

        pub fn ensure_total_capacity(list: *Self, arena: *Arena, new_capacity: usize) Arena.AllocError!void {
            if (list.capacity >= new_capacity) return;
            try list.ensure_total_capacity_precise(arena, new_capacity);
        }

        pub fn ensure_total_capacity_precise(list: *Self, arena: *Arena, new_capacity: usize) Arena.AllocError!void {
            if (list.capacity >= new_capacity) return;

            list.assert_arena_contiguity(arena);

            if (list.capacity == 0) {
                const new_memory = try arena.alloc(T, new_capacity);
                list.items.ptr = new_memory.ptr;
                list.capacity = new_capacity;
            } else {
                const additional = new_capacity - list.capacity;
                _ = try arena.push_aligned(additional * @sizeOf(T), @alignOf(T));
                list.capacity = new_capacity;
            }
            list.saved_arena_pos = arena.pos;
        }

        pub fn ensure_unused_capacity(list: *Self, arena: *Arena, additional: usize) Arena.AllocError!void {
            return list.ensure_total_capacity(arena, try add_or_oom(list.items.len, additional));
        }

        pub fn expand_to_capacity(list: *Self) void {
            list.items.len = list.capacity;
        }

        pub fn add_one(list: *Self, arena: *Arena) Arena.AllocError!*T {
            const newlen = list.items.len + 1;
            try list.ensure_total_capacity(arena, newlen);
            return list.add_one_assume_capacity();
        }

        pub fn add_one_assume_capacity(list: *Self) *T {
            assert(list.items.len < list.capacity);
            list.items.len += 1;
            return &list.items[list.items.len - 1];
        }

        pub fn add_many_as_array(list: *Self, arena: *Arena, comptime n: usize) Arena.AllocError!*[n]T {
            const prev_len = list.items.len;
            try list.resize(arena, try add_or_oom(list.items.len, n));
            return list.items[prev_len..][0..n];
        }

        pub fn add_many_as_array_assume_capacity(list: *Self, comptime n: usize) *[n]T {
            assert(list.items.len + n <= list.capacity);
            const prev_len = list.items.len;
            list.items.len += n;
            return list.items[prev_len..][0..n];
        }

        pub fn add_many_as_slice(list: *Self, arena: *Arena, n: usize) Arena.AllocError![]T {
            const prev_len = list.items.len;
            try list.resize(arena, try add_or_oom(list.items.len, n));
            return list.items[prev_len..][0..n];
        }

        pub fn add_many_as_slice_assume_capacity(list: *Self, n: usize) []T {
            assert(list.items.len + n <= list.capacity);
            const prev_len = list.items.len;
            list.items.len += n;
            return list.items[prev_len..][0..n];
        }

        pub fn pop(list: *Self) ?T {
            if (list.items.len == 0) return null;
            const val = list.items[list.items.len - 1];
            list.items.len -= 1;
            return val;
        }

        pub fn allocated_slice(list: Self) Slice {
            return list.items.ptr[0..list.capacity];
        }

        pub fn unused_capacity_slice(list: Self) []T {
            return list.allocated_slice()[list.items.len..];
        }

        pub fn get_last(list: Self) T {
            return list.items[list.items.len - 1];
        }

        pub fn get_last_or_null(list: Self) ?T {
            if (list.items.len == 0) return null;
            return list.get_last();
        }

        fn assert_arena_contiguity(list: *Self, arena: *Arena) void {
            if (list.capacity == 0) return;
            assert(arena.pos == list.saved_arena_pos);
        }
    };
}

fn add_or_oom(a: usize, b: usize) error{OutOfMemory}!usize {
    const result, const overflow = @addWithOverflow(a, b);
    if (overflow != 0) return error.OutOfMemory;
    return result;
}

test "ArenaList: basic operations" {
    var arena = try Arena.init(.{ .reserve_size = 1024 * 1024 });
    defer arena.deinit();

    var list: ArenaList(i32) = .empty;

    try list.append(&arena, 1);
    try list.append(&arena, 2);
    try list.append(&arena, 3);

    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    try std.testing.expectEqual(@as(i32, 1), list.items[0]);
    try std.testing.expectEqual(@as(i32, 2), list.items[1]);
    try std.testing.expectEqual(@as(i32, 3), list.items[2]);
}

test "ArenaList: init_capacity" {
    var arena = try Arena.init(.{ .reserve_size = 1024 * 1024 });
    defer arena.deinit();

    var list = try ArenaList(i32).init_capacity(&arena, 100);

    try std.testing.expectEqual(@as(usize, 0), list.items.len);
    try std.testing.expectEqual(@as(usize, 100), list.capacity);

    for (0..100) |i| {
        list.append_assume_capacity(@intCast(i));
    }

    try std.testing.expectEqual(@as(usize, 100), list.items.len);
}

test "ArenaList: append_slice" {
    var arena = try Arena.init(.{ .reserve_size = 1024 * 1024 });
    defer arena.deinit();

    var list: ArenaList(i32) = .empty;

    try list.append_slice(&arena, &[_]i32{ 1, 2, 3, 4, 5 });

    try std.testing.expectEqual(@as(usize, 5), list.items.len);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3, 4, 5 }, list.items);
}

test "ArenaList: pop" {
    var arena = try Arena.init(.{ .reserve_size = 1024 * 1024 });
    defer arena.deinit();

    var list: ArenaList(i32) = .empty;

    try list.append_slice(&arena, &[_]i32{ 1, 2, 3 });

    try std.testing.expectEqual(@as(?i32, 3), list.pop());
    try std.testing.expectEqual(@as(?i32, 2), list.pop());
    try std.testing.expectEqual(@as(?i32, 1), list.pop());
    try std.testing.expectEqual(@as(?i32, null), list.pop());
}

test "ArenaList: insert" {
    var arena = try Arena.init(.{ .reserve_size = 1024 * 1024 });
    defer arena.deinit();

    var list: ArenaList(i32) = .empty;

    try list.append_slice(&arena, &[_]i32{ 1, 3, 4 });
    try list.insert(&arena, 1, 2);

    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3, 4 }, list.items);
}

test "ArenaList: ordered_remove" {
    var arena = try Arena.init(.{ .reserve_size = 1024 * 1024 });
    defer arena.deinit();

    var list: ArenaList(i32) = .empty;

    try list.append_slice(&arena, &[_]i32{ 1, 2, 3, 4, 5 });
    const removed = list.ordered_remove(2);

    try std.testing.expectEqual(@as(i32, 3), removed);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 4, 5 }, list.items);
}

test "ArenaList: swap_remove" {
    var arena = try Arena.init(.{ .reserve_size = 1024 * 1024 });
    defer arena.deinit();

    var list: ArenaList(i32) = .empty;

    try list.append_slice(&arena, &[_]i32{ 1, 2, 3, 4, 5 });
    const removed = list.swap_remove(1);

    try std.testing.expectEqual(@as(i32, 2), removed);
    try std.testing.expectEqual(@as(usize, 4), list.items.len);
    try std.testing.expectEqual(@as(i32, 5), list.items[1]);
}

test "ArenaList: reserved capacity allows arena use elsewhere" {
    var arena = try Arena.init(.{ .reserve_size = 1024 * 1024 });
    defer arena.deinit();

    var list = try ArenaList(i32).init_capacity(&arena, 10);

    _ = try arena.push(100);

    list.append_assume_capacity(1);
    list.append_assume_capacity(2);
    list.append_assume_capacity(3);

    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 2, 3 }, list.items);
}

test "ArenaList: get_last and get_last_or_null" {
    var arena = try Arena.init(.{ .reserve_size = 1024 * 1024 });
    defer arena.deinit();

    var list: ArenaList(i32) = .empty;

    try std.testing.expectEqual(@as(?i32, null), list.get_last_or_null());

    try list.append(&arena, 42);
    try std.testing.expectEqual(@as(i32, 42), list.get_last());
    try std.testing.expectEqual(@as(?i32, 42), list.get_last_or_null());
}

test "ArenaList: replace_range" {
    var arena = try Arena.init(.{ .reserve_size = 1024 * 1024 });
    defer arena.deinit();

    var list: ArenaList(i32) = .empty;

    try list.append_slice(&arena, &[_]i32{ 1, 2, 3, 4, 5 });
    try list.replace_range(&arena, 1, 2, &[_]i32{ 10, 20, 30 });

    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 10, 20, 30, 4, 5 }, list.items);
}

test "ArenaList: append_n_times" {
    var arena = try Arena.init(.{ .reserve_size = 1024 * 1024 });
    defer arena.deinit();

    var list: ArenaList(i32) = .empty;

    try list.append_n_times(&arena, 7, 5);

    try std.testing.expectEqualSlices(i32, &[_]i32{ 7, 7, 7, 7, 7 }, list.items);
}

test "ArenaList: add_many_as_array" {
    var arena = try Arena.init(.{ .reserve_size = 1024 * 1024 });
    defer arena.deinit();

    var list: ArenaList(u8) = .empty;

    (try list.add_many_as_array(&arena, 4)).* = "test".*;

    try std.testing.expectEqualSlices(u8, "test", list.items);
}

test "ArenaList: shrink_retaining_capacity" {
    var arena = try Arena.init(.{ .reserve_size = 1024 * 1024 });
    defer arena.deinit();

    var list: ArenaList(i32) = .empty;

    try list.append_slice(&arena, &[_]i32{ 1, 2, 3, 4, 5 });
    const original_capacity = list.capacity;

    list.shrink_retaining_capacity(2);

    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqual(original_capacity, list.capacity);
    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 2 }, list.items);
}

test "ArenaList: clear_retaining_capacity" {
    var arena = try Arena.init(.{ .reserve_size = 1024 * 1024 });
    defer arena.deinit();

    var list: ArenaList(i32) = .empty;

    try list.append_slice(&arena, &[_]i32{ 1, 2, 3, 4, 5 });
    const original_capacity = list.capacity;

    list.clear_retaining_capacity();

    try std.testing.expectEqual(@as(usize, 0), list.items.len);
    try std.testing.expectEqual(original_capacity, list.capacity);
}
