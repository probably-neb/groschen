//! Hash map using Xar tables. Pointers from get() remain valid after rehash.

const std = @import("std");
const assert = std.debug.assert;
const base = @import("base.zig");
const Arena = base.Arena;
const Xar = base.Xar;

pub fn XarMap(comptime K: type, comptime V: type, comptime prealloc_count: usize) type {
    return struct {
        const Self = @This();

        const Slot = struct {
            const empty_sentinel: u32 = std.math.maxInt(u32);
            const tombstone_sentinel: u32 = std.math.maxInt(u32) - 1;

            index: u32 = empty_sentinel,

            fn is_empty(slot: Slot) bool {
                return slot.index == empty_sentinel;
            }

            fn is_tombstone(slot: Slot) bool {
                return slot.index == tombstone_sentinel;
            }

            fn is_occupied(slot: Slot) bool {
                return slot.index != empty_sentinel and slot.index != tombstone_sentinel;
            }
        };

        const KeyXar = Xar(K, prealloc_count);
        const ValueXar = Xar(V, prealloc_count);
        const SlotXar = Xar(Slot, prealloc_count);

        keys: KeyXar = .{},
        values: ValueXar = .{},
        slots: SlotXar = .{},
        size: usize = 0,
        slot_count: usize = 0,

        pub const empty: Self = .{};

        pub const Entry = struct {
            key_ptr: *K,
            value_ptr: *V,
        };

        pub const ConstEntry = struct {
            key_ptr: *const K,
            value_ptr: *const V,
        };

        pub const GetOrPutResult = struct {
            key_ptr: *K,
            value_ptr: *V,
            found_existing: bool,
        };

        pub fn deinit(map: *Self, arena: *Arena) void {
            map.keys.deinit(arena);
            map.values.deinit(arena);
            map.slots.deinit(arena);
            map.* = undefined;
        }

        pub fn count(map: Self) usize {
            return map.size;
        }

        pub fn capacity(map: Self) usize {
            return map.slot_count;
        }

        pub fn get(map: *Self, key: K) ?*V {
            const idx = map.find_entry_index(key) orelse return null;
            return map.values.unchecked_at(idx);
        }

        pub fn get_const(map: *const Self, key: K) ?*const V {
            const idx = map.find_entry_index_const(key) orelse return null;
            return map.values.unchecked_at(idx);
        }

        pub fn get_key(map: *Self, key: K) ?*K {
            const idx = map.find_entry_index(key) orelse return null;
            return map.keys.unchecked_at(idx);
        }

        pub fn get_entry(map: *Self, key: K) ?Entry {
            const idx = map.find_entry_index(key) orelse return null;
            return Entry{
                .key_ptr = map.keys.unchecked_at(idx),
                .value_ptr = map.values.unchecked_at(idx),
            };
        }

        pub fn contains(map: *const Self, key: K) bool {
            return map.find_entry_index_const(key) != null;
        }

        pub fn put(map: *Self, arena: *Arena, key: K, value: V) Arena.AllocError!void {
            const result = try map.get_or_put(arena, key);
            result.value_ptr.* = value;
            if (!result.found_existing) {
                result.key_ptr.* = key;
            }
        }

        pub fn get_or_put(map: *Self, arena: *Arena, key: K) Arena.AllocError!GetOrPutResult {
            try map.ensure_capacity_for_insert(arena);

            const hash = hash_key(key);
            var slot_idx = hash % map.slot_count;

            var first_tombstone: ?usize = null;
            var probes: usize = 0;

            while (probes < map.slot_count) : (probes += 1) {
                const slot = map.slots.unchecked_at(slot_idx).*;

                if (slot.is_empty()) {
                    const insert_slot_idx = first_tombstone orelse slot_idx;
                    const entry_idx = try map.append_entry(arena);

                    map.slots.unchecked_at(insert_slot_idx).* = .{ .index = @intCast(entry_idx) };
                    map.size += 1;

                    return GetOrPutResult{
                        .key_ptr = map.keys.unchecked_at(entry_idx),
                        .value_ptr = map.values.unchecked_at(entry_idx),
                        .found_existing = false,
                    };
                } else if (slot.is_tombstone()) {
                    if (first_tombstone == null) {
                        first_tombstone = slot_idx;
                    }
                } else {
                    const existing_key = map.keys.unchecked_at(slot.index).*;
                    if (keys_equal(existing_key, key)) {
                        return GetOrPutResult{
                            .key_ptr = map.keys.unchecked_at(slot.index),
                            .value_ptr = map.values.unchecked_at(slot.index),
                            .found_existing = true,
                        };
                    }
                }

                slot_idx = (slot_idx + 1) % map.slot_count;
            }

            if (first_tombstone) |tombstone_idx| {
                const entry_idx = try map.append_entry(arena);
                map.slots.unchecked_at(tombstone_idx).* = .{ .index = @intCast(entry_idx) };
                map.size += 1;

                return GetOrPutResult{
                    .key_ptr = map.keys.unchecked_at(entry_idx),
                    .value_ptr = map.values.unchecked_at(entry_idx),
                    .found_existing = false,
                };
            }

            unreachable;
        }

        pub fn remove(map: *Self, key: K) bool {
            const slot_idx = map.find_slot_index(key) orelse return false;
            map.slots.unchecked_at(slot_idx).* = .{ .index = Slot.tombstone_sentinel };
            map.size -= 1;
            return true;
        }

        pub fn fetch_remove(map: *Self, key: K) ?V {
            const slot_idx = map.find_slot_index(key) orelse return null;
            const slot = map.slots.unchecked_at(slot_idx);
            const value = map.values.unchecked_at(slot.index).*;
            slot.* = .{ .index = Slot.tombstone_sentinel };
            map.size -= 1;
            return value;
        }

        pub fn clear(map: *Self) void {
            var i: usize = 0;
            while (i < map.slot_count) : (i += 1) {
                map.slots.unchecked_at(i).* = .{ .index = Slot.empty_sentinel };
            }
            map.keys.clear_retaining_capacity();
            map.values.clear_retaining_capacity();
            map.size = 0;
        }

        pub fn clear_and_free(map: *Self, arena: *Arena) void {
            map.keys.clear_and_free(arena);
            map.values.clear_and_free(arena);
            map.slots.clear_and_free(arena);
            map.slot_count = 0;
            map.size = 0;
        }

        pub const Iterator = struct {
            map: *Self,
            entry_idx: usize,

            pub fn next(it: *Iterator) ?Entry {
                while (it.entry_idx < it.map.keys.count()) {
                    const idx = it.entry_idx;
                    it.entry_idx += 1;

                    const key = it.map.keys.unchecked_at(idx).*;
                    if (it.map.find_entry_index(key)) |found_idx| {
                        if (found_idx == idx) {
                            return Entry{
                                .key_ptr = it.map.keys.unchecked_at(idx),
                                .value_ptr = it.map.values.unchecked_at(idx),
                            };
                        }
                    }
                }
                return null;
            }
        };

        pub fn iterator(map: *Self) Iterator {
            return Iterator{
                .map = map,
                .entry_idx = 0,
            };
        }

        pub const ConstIterator = struct {
            map: *const Self,
            slot_idx: usize,

            pub fn next(it: *ConstIterator) ?ConstEntry {
                while (it.slot_idx < it.map.slot_count) {
                    const idx = it.slot_idx;
                    it.slot_idx += 1;

                    const slot = it.map.slots.unchecked_at(idx).*;
                    if (slot.is_occupied()) {
                        return ConstEntry{
                            .key_ptr = it.map.keys.unchecked_at(slot.index),
                            .value_ptr = it.map.values.unchecked_at(slot.index),
                        };
                    }
                }
                return null;
            }
        };

        // TODO: use at_type for const/non const pointers in entries
        pub fn const_iterator(map: *const Self) ConstIterator {
            return ConstIterator{
                .map = map,
                .slot_idx = 0,
            };
        }

        pub const KeyIterator = struct {
            map: *const Self,
            slot_idx: usize,

            pub fn next(it: *KeyIterator) ?*const K {
                while (it.slot_idx < it.map.slot_count) {
                    const idx = it.slot_idx;
                    it.slot_idx += 1;

                    const slot = it.map.slots.unchecked_at(idx).*;
                    if (slot.is_occupied()) {
                        return it.map.keys.unchecked_at(slot.index);
                    }
                }
                return null;
            }
        };

        pub fn key_iterator(map: *const Self) KeyIterator {
            return KeyIterator{
                .map = map,
                .slot_idx = 0,
            };
        }

        pub const ValueIterator = struct {
            map: *Self,
            slot_idx: usize,

            pub fn next(it: *ValueIterator) ?*V {
                while (it.slot_idx < it.map.slot_count) {
                    const idx = it.slot_idx;
                    it.slot_idx += 1;

                    const slot = it.map.slots.unchecked_at(idx).*;
                    if (slot.is_occupied()) {
                        return it.map.values.unchecked_at(slot.index);
                    }
                }
                return null;
            }
        };

        pub fn value_iterator(map: *Self) ValueIterator {
            return ValueIterator{
                .map = map,
                .slot_idx = 0,
            };
        }

        fn find_slot_index(map: *Self, key: K) ?usize {
            if (map.slot_count == 0) return null;

            const hash = hash_key(key);
            var slot_idx = hash % map.slot_count;

            var probes: usize = 0;
            while (probes < map.slot_count) : (probes += 1) {
                const slot = map.slots.unchecked_at(slot_idx).*;

                if (slot.is_empty()) {
                    return null;
                } else if (slot.is_occupied()) {
                    const existing_key = map.keys.unchecked_at(slot.index).*;
                    if (keys_equal(existing_key, key)) {
                        return slot_idx;
                    }
                }
                slot_idx = (slot_idx + 1) % map.slot_count;
            }

            return null;
        }

        fn find_entry_index(map: *Self, key: K) ?usize {
            if (map.slot_count == 0) return null;

            const hash = hash_key(key);
            var slot_idx = hash % map.slot_count;

            var probes: usize = 0;
            while (probes < map.slot_count) : (probes += 1) {
                const slot = map.slots.unchecked_at(slot_idx).*;

                if (slot.is_empty()) {
                    return null;
                } else if (slot.is_occupied()) {
                    const existing_key = map.keys.unchecked_at(slot.index).*;
                    if (keys_equal(existing_key, key)) {
                        return slot.index;
                    }
                }

                slot_idx = (slot_idx + 1) % map.slot_count;
            }

            return null;
        }

        fn find_entry_index_const(map: *const Self, key: K) ?usize {
            if (map.slot_count == 0) return null;

            const hash = hash_key(key);
            var slot_idx = hash % map.slot_count;

            var probes: usize = 0;
            while (probes < map.slot_count) : (probes += 1) {
                const slot = map.slots.unchecked_at(slot_idx).*;

                if (slot.is_empty()) {
                    return null;
                } else if (slot.is_occupied()) {
                    const existing_key = map.keys.unchecked_at(slot.index).*;
                    if (keys_equal(existing_key, key)) {
                        return slot.index;
                    }
                }

                slot_idx = (slot_idx + 1) % map.slot_count;
            }

            return null;
        }

        fn append_entry(map: *Self, arena: *Arena) Arena.AllocError!usize {
            const idx = map.keys.count();
            _ = try map.keys.add_one(arena);
            _ = try map.values.add_one(arena);
            return idx;
        }

        fn ensure_capacity_for_insert(map: *Self, arena: *Arena) Arena.AllocError!void {
            if (map.slot_count == 0) {
                try map.init_slots(arena, initial_capacity());
            } else if ((map.size + 1) * 4 > map.slot_count * 3) {
                try map.rehash(arena, map.slot_count * 2);
            }
        }

        fn init_slots(map: *Self, arena: *Arena, new_cap: usize) Arena.AllocError!void {
            var i: usize = 0;
            while (i < new_cap) : (i += 1) {
                const slot_ptr = try map.slots.add_one(arena);
                slot_ptr.* = .{ .index = Slot.empty_sentinel };
            }
            map.slot_count = new_cap;
        }

        fn rehash(map: *Self, arena: *Arena, new_cap: usize) Arena.AllocError!void {
            const old_cap = map.slot_count;

            const scratch = Arena.get_scratch(&.{arena});
            defer scratch.release();
            const valid_indices = scratch.arena.alloc(u32, map.size) catch @panic("scratch arena OOM");
            var valid_count: usize = 0;

            var i: usize = 0;
            while (i < old_cap) : (i += 1) {
                const slot = map.slots.unchecked_at(i).*;
                if (slot.is_occupied()) {
                    valid_indices[valid_count] = slot.index;
                    valid_count += 1;
                }
            }

            while (map.slot_count < new_cap) {
                const slot_ptr = try map.slots.add_one(arena);
                slot_ptr.* = .{ .index = Slot.empty_sentinel };
                map.slot_count += 1;
            }

            i = 0;
            while (i < new_cap) : (i += 1) {
                map.slots.unchecked_at(i).* = .{ .index = Slot.empty_sentinel };
            }

            map.size = 0;
            for (valid_indices[0..valid_count]) |entry_idx| {
                const key = map.keys.unchecked_at(entry_idx).*;
                const hash = hash_key(key);
                var slot_idx = hash % map.slot_count;

                var probes: usize = 0;
                while (probes < map.slot_count) : (probes += 1) {
                    const slot = map.slots.unchecked_at(slot_idx).*;

                    if (slot.is_empty()) {
                        map.slots.unchecked_at(slot_idx).* = .{ .index = entry_idx };
                        map.size += 1;
                        break;
                    }

                    slot_idx = (slot_idx + 1) % map.slot_count;
                }
            }
        }

        fn initial_capacity() usize {
            return if (prealloc_count > 0) prealloc_count else 8;
        }

        fn hash_key(key: K) usize {
            if (comptime std.meta.hasMethod(K, "hash")) {
                return key.hash();
            } else if (K == []const u8) {
                return std.hash.Wyhash.hash(0, key);
            } else if (comptime std.meta.hasUniqueRepresentation(K)) {
                return std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
            } else {
                var hasher = std.hash.Wyhash.init(0);
                std.hash.autoHash(&hasher, key);
                return hasher.final();
            }
        }

        fn keys_equal(a: K, b: K) bool {
            if (comptime std.meta.hasMethod(K, "eql")) {
                return a.eql(b);
            } else if (K == []const u8) {
                return std.mem.eql(u8, a, b);
            } else {
                return a == b;
            }
        }
    };
}

test "XarMap: basic operations" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    var map: XarMap(u32, []const u8, 4) = .{};
    defer map.deinit(&arena);

    try map.put(&arena, 1, "one");
    try map.put(&arena, 2, "two");
    try map.put(&arena, 3, "three");

    try std.testing.expectEqual(@as(usize, 3), map.count());
    try std.testing.expectEqualStrings("one", map.get(1).?.*);
    try std.testing.expectEqualStrings("two", map.get(2).?.*);
    try std.testing.expectEqualStrings("three", map.get(3).?.*);
    try std.testing.expect(map.get(4) == null);
}

test "XarMap: getOrPut" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    var map: XarMap(u32, u32, 4) = .{};
    defer map.deinit(&arena);

    const result1 = try map.get_or_put(&arena, 42);
    try std.testing.expect(!result1.found_existing);
    result1.key_ptr.* = 42;
    result1.value_ptr.* = 100;

    const result2 = try map.get_or_put(&arena, 42);
    try std.testing.expect(result2.found_existing);
    try std.testing.expectEqual(@as(u32, 100), result2.value_ptr.*);
}

test "XarMap: remove" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    var map: XarMap(u32, u32, 4) = .{};
    defer map.deinit(&arena);

    try map.put(&arena, 1, 10);
    try map.put(&arena, 2, 20);

    try std.testing.expect(map.remove(1));
    try std.testing.expect(map.get(1) == null);
    try std.testing.expectEqual(@as(usize, 1), map.count());

    try std.testing.expect(!map.remove(1)); // Already removed
    try std.testing.expectEqual(@as(u32, 20), map.get(2).?.*);
}

test "XarMap: fetchRemove" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    var map: XarMap(u32, u32, 4) = .{};
    defer map.deinit(&arena);

    try map.put(&arena, 1, 100);

    const value = map.fetch_remove(1);
    try std.testing.expectEqual(@as(?u32, 100), value);
    try std.testing.expect(map.get(1) == null);
}

test "XarMap: iteration" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    var map: XarMap(u32, u32, 4) = .{};
    defer map.deinit(&arena);

    try map.put(&arena, 1, 10);
    try map.put(&arena, 2, 20);
    try map.put(&arena, 3, 30);

    var sum: u32 = 0;
    var it = map.const_iterator();
    while (it.next()) |entry| {
        sum += entry.value_ptr.*;
    }
    try std.testing.expectEqual(@as(u32, 60), sum);
}

test "XarMap: growth and rehashing" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    var map: XarMap(u32, u32, 4) = .{};
    defer map.deinit(&arena);

    // Insert enough entries to trigger rehashing
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        try map.put(&arena, i, i * 10);
    }

    try std.testing.expectEqual(@as(usize, 100), map.count());

    // Verify all entries are still accessible
    i = 0;
    while (i < 100) : (i += 1) {
        try std.testing.expectEqual(i * 10, map.get(i).?.*);
    }
}

test "XarMap: collision handling with tombstones" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    var map: XarMap(u32, u32, 8) = .{};
    defer map.deinit(&arena);

    // Insert, remove, and reinsert to test tombstone handling
    try map.put(&arena, 1, 10);
    try map.put(&arena, 2, 20);
    try map.put(&arena, 3, 30);

    _ = map.remove(2);

    try map.put(&arena, 4, 40);

    try std.testing.expectEqual(@as(?u32, 10), if (map.get(1)) |v| v.* else null);
    try std.testing.expect(map.get(2) == null);
    try std.testing.expectEqual(@as(?u32, 30), if (map.get(3)) |v| v.* else null);
    try std.testing.expectEqual(@as(?u32, 40), if (map.get(4)) |v| v.* else null);
}

test "XarMap: clear" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    var map: XarMap(u32, u32, 4) = .{};
    defer map.deinit(&arena);

    try map.put(&arena, 1, 10);
    try map.put(&arena, 2, 20);

    map.clear();

    try std.testing.expectEqual(@as(usize, 0), map.count());
    try std.testing.expect(map.get(1) == null);
    try std.testing.expect(map.get(2) == null);

    // Can reuse after clear
    try map.put(&arena, 3, 30);
    try std.testing.expectEqual(@as(usize, 1), map.count());
}

test "XarMap: zero prealloc" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    var map: XarMap(u32, u32, 0) = .{};
    defer map.deinit(&arena);

    try map.put(&arena, 1, 10);
    try map.put(&arena, 2, 20);

    try std.testing.expectEqual(@as(usize, 2), map.count());
    try std.testing.expectEqual(@as(u32, 10), map.get(1).?.*);
    try std.testing.expectEqual(@as(u32, 20), map.get(2).?.*);
}

test "XarMap: pointer stability" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    var map: XarMap(u32, u32, 4) = .{};
    defer map.deinit(&arena);

    // Get pointer to first value
    try map.put(&arena, 1, 100);
    const ptr1 = map.get(1).?;
    const addr1 = @intFromPtr(ptr1);

    // Insert many more entries to trigger rehashing
    var i: u32 = 2;
    while (i < 50) : (i += 1) {
        try map.put(&arena, i, i * 10);
    }

    // Original pointer should still be valid (Xar guarantees pointer stability)
    const ptr1_after = map.get(1).?;
    const addr1_after = @intFromPtr(ptr1_after);

    try std.testing.expectEqual(addr1, addr1_after);
    try std.testing.expectEqual(@as(u32, 100), ptr1_after.*);
}

test "XarMap: const iterator" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    var map: XarMap(u32, u32, 4) = .{};
    defer map.deinit(&arena);

    try map.put(&arena, 1, 10);
    try map.put(&arena, 2, 20);

    const const_map: *const XarMap(u32, u32, 4) = &map;

    var sum: u32 = 0;
    var it = const_map.const_iterator();
    while (it.next()) |entry| {
        sum += entry.value_ptr.*;
    }
    try std.testing.expectEqual(@as(u32, 30), sum);
}

test "XarMap: contains" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    var map: XarMap(u32, u32, 4) = .{};
    defer map.deinit(&arena);

    try map.put(&arena, 1, 10);

    const const_map: *const XarMap(u32, u32, 4) = &map;
    try std.testing.expect(const_map.contains(1));
    try std.testing.expect(!const_map.contains(2));
}

test "XarMap: key and value iterators" {
    var arena = try Arena.init(.{});
    defer arena.deinit();

    var map: XarMap(u32, u32, 4) = .{};
    defer map.deinit(&arena);

    try map.put(&arena, 1, 10);
    try map.put(&arena, 2, 20);
    try map.put(&arena, 3, 30);

    var key_sum: u32 = 0;
    var key_it = map.key_iterator();
    while (key_it.next()) |key_ptr| {
        key_sum += key_ptr.*;
    }
    try std.testing.expectEqual(@as(u32, 6), key_sum);

    var value_sum: u32 = 0;
    var value_it = map.value_iterator();
    while (value_it.next()) |value_ptr| {
        value_sum += value_ptr.*;
    }
    try std.testing.expectEqual(@as(u32, 60), value_sum);
}
