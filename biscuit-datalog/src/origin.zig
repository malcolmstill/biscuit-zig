const std = @import("std");
const mem = std.mem;
const Wyhash = std.hash.Wyhash;

const Set = @import("set.zig").Set;
const Scope = @import("scope.zig").Scope;

pub const Origin = struct {
    block_ids: std.AutoHashMap(usize, void),

    // Authorizer id is maximum int storable in u64
    pub const AUTHORIZER_ID = std.math.maxInt(u64);

    pub fn init(allocator: mem.Allocator) Origin {
        return .{ .block_ids = std.AutoHashMap(usize, void).init(allocator) };
    }

    pub fn initWithId(allocator: mem.Allocator, block_id: usize) !Origin {
        var block_ids = std.AutoHashMap(usize, void).init(allocator);

        try block_ids.put(block_id, {});

        return .{ .block_ids = block_ids };
    }

    pub fn testDeinit(origin: *Origin) void {
        origin.block_ids.deinit();
    }

    pub fn format(origin: Origin, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        var it = origin.block_ids.keyIterator();

        try writer.print("[", .{});
        while (it.next()) |block_id_ptr| {
            const block_id = block_id_ptr.*;

            if (block_id == Origin.AUTHORIZER_ID) {
                try writer.print("{s},", .{"Authorizer"});
            } else {
                try writer.print("{},", .{block_id});
            }
        }
        try writer.print("]", .{});
    }

    pub fn clone(origin: *const Origin) !Origin {
        return .{ .block_ids = try origin.block_ids.clone() };
    }

    // pub fn authorizer(allocator: mem.Allocator) !Origin {
    //     return try Origin.initWithId(allocator, AUTHORIZER_ID);
    // }

    pub fn insert(origin: *Origin, block_id: usize) !void {
        try origin.block_ids.put(block_id, {});
    }

    pub fn @"union"(origin: Origin, other: Origin) Origin {
        return .{ .block_ids = origin.block_ids.@"union"(other.block_ids) };
    }

    pub fn isSuperset(origin: Origin, other: Origin) Origin {
        return origin.block_ids.isSuperset(other.block_ids);
    }

    pub fn hash(origin: Origin, hasher: anytype) void {
        var h: usize = 0;

        var it = origin.block_ids.keyIterator();
        while (it.next()) |block_id_ptr| {
            const block_id = block_id_ptr.*;

            h ^= block_id;
        }

        std.hash.autoHash(hasher, h);
    }

    pub fn eql(a: Origin, b: Origin) bool {
        if (a.block_ids.count() != b.block_ids.count()) return false;

        var a_it = a.block_ids.keyIterator();
        while (a_it.next()) |a_block_id| {
            if (b.block_ids.contains(a_block_id.*)) continue;

            return false;
        }

        return true;
    }
};

test "Origins" {
    const testing = std.testing;

    var origins = Origin.init(testing.allocator);
    defer origins.testDeinit();

    try origins.insert(12);
    try origins.insert(13);
}
