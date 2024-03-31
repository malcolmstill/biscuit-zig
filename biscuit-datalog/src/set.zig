const std = @import("std");
const mem = std.mem;
const meta = std.meta;
const trait = std.meta.trait;
const Wyhash = std.hash.Wyhash;
const Fact = @import("fact.zig").Fact;

/// Set wraps the std.HashMap and uses a hash function defined
/// by a method assumed to exist on type K with name "hash".
pub fn Set(comptime K: type) type {
    return struct {
        inner: InnerSet,
        alloc: mem.Allocator,

        const InnerSet = std.HashMap(K, void, Context, 80);
        const Self = @This();

        pub const Iterator = InnerSet.KeyIterator;

        // Sets are used in two places: we have Set(Fact) for storing our body of facts
        // and Set(Term). Both Fact and Term define `.hash` and `.eql` (and internally
        // other fields define those as required). We don't need to support arbitrary Set(T)
        // and so don't have to consider other types that may or may not define these expected
        // methods.
        const Context = struct {
            pub fn hash(ctx: Context, key: K) u64 {
                _ = ctx;

                // We assume here there is a method `pub hash(set: K, hasher: anytype)` on type K.
                var hasher = Wyhash.init(0);
                key.hash(&hasher);
                return hasher.final();
            }

            pub fn eql(ctx: Context, a: K, b: K) bool {
                _ = ctx;
                return a.eql(b);
            }
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .inner = InnerSet.init(allocator),
                .alloc = allocator,
            };
        }

        pub fn deinit(set: *Self) void {
            set.inner.deinit();
        }

        pub fn clone(set: *const Self) !Self {
            return .{
                .inner = try set.inner.clone(),
                .alloc = set.alloc,
            };
        }

        pub fn iterator(set: Self) InnerSet.KeyIterator {
            return set.inner.keyIterator();
        }

        pub fn ptrIterator(set: *Self) InnerSet.KeyIterator {
            return set.inner.keyIterator();
        }

        pub fn add(set: *Self, value: K) !void {
            try set.inner.put(value, {});
        }

        pub fn contains(set: Self, value: K) bool {
            return set.inner.contains(value);
        }

        pub fn count(set: *const Self) u32 {
            return set.inner.count();
        }

        /// Calculate a hash for the given set.
        ///
        /// 1. Initialises the results hash to 0
        /// 2. Loops over all keys in the set and
        ///    individually calculates their hash. Each
        ///    hash is XOR'd onto the result hash (and
        ///    so key order does not affect the final value)
        /// 3. Returns resulting hash
        pub fn hash(set: Self, hasher: anytype) void {
            var h: u64 = 0;

            var it = set.iterator();
            while (it.next()) |key| {
                var key_hasher = Wyhash.init(0);
                key.hash(&key_hasher);
                h ^= key_hasher.final();
            }

            std.hash.autoHash(hasher, h);
        }

        /// Key-by-key equality check for two sets
        pub fn eql(left: Self, right: Self) bool {
            var it = left.iterator();

            while (it.next()) |key| {
                if (!right.contains(key.*)) return false;
            }

            return true;
        }

        pub fn format(set: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("set{{", .{});
            var it = set.iterator();

            const num_keys = set.count();
            var i: usize = 0;

            while (it.next()) |key| {
                defer i += 1;

                try writer.print("{any}", .{key});
                if (i < num_keys - 1) try writer.print(", ", .{});
            }
            return writer.print("}}", .{});
        }

        pub fn intersection(set: Self, s: Self) !Self {
            var new = Self.init(set.alloc);
            var it = set.iterator();

            while (it.next()) |term| {
                if (s.contains(term.*)) try new.add(term.*);
            }

            return new;
        }

        pub fn @"union"(set: Self, s: Self) !Self {
            var new = Self.init(set.alloc);

            {
                var it = set.iterator();
                while (it.next()) |term| {
                    try new.add(term.*);
                }
            }

            {
                var it = s.iterator();
                while (it.next()) |term| {
                    try new.add(term.*);
                }
            }

            return new;
        }

        pub fn isSuperset(set: Self, s: Self) bool {
            var it = s.iterator();
            while (it.next()) |term| {
                if (!set.contains(term.*)) return false;
            }

            return true;
        }
    };
}

test {
    const Predicate = @import("predicate.zig").Predicate;
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_log = std.log.scoped(.test_set);

    var s = Set(Fact).init(allocator);
    defer s.deinit();

    try s.add(Fact{ .predicate = Predicate{ .name = 0, .terms = undefined } });
    try testing.expectEqual(@as(u32, 1), s.count());

    try s.add(Fact{ .predicate = Predicate{ .name = 0, .terms = undefined } });
    try testing.expectEqual(@as(u32, 1), s.count());

    try s.add(Fact{ .predicate = Predicate{ .name = 10, .terms = undefined } });
    try s.add(Fact{ .predicate = Predicate{ .name = 10, .terms = undefined } });
    try s.add(Fact{ .predicate = Predicate{ .name = 10, .terms = undefined } });
    try s.add(Fact{ .predicate = Predicate{ .name = 10, .terms = undefined } });
    try s.add(Fact{ .predicate = Predicate{ .name = 10, .terms = undefined } });
    try testing.expectEqual(@as(u32, 2), s.count());

    test_log.debug("set = {any}\n", .{s});
}

test "hashing" {
    const Term = @import("term.zig").Term;

    const testing = std.testing;
    const allocator = testing.allocator;

    var s1 = Set(Term).init(allocator);
    defer s1.deinit();

    var s2 = Set(Term).init(allocator);
    defer s2.deinit();

    try s1.add(.{ .integer = 1 });
    try s1.add(.{ .integer = 2 });
    try s1.add(.{ .integer = 3 });

    try s2.add(.{ .integer = 3 });
    try s2.add(.{ .integer = 2 });
    try s2.add(.{ .integer = 1 });

    // Sets are equal regardless of insertion order
    try testing.expect(s1.eql(s2));

    var s1_hasher = Wyhash.init(0);
    s1.hash(&s1_hasher);
    const s1_hash = s1_hasher.final();

    var s2_hasher = Wyhash.init(0);
    s2.hash(&s2_hasher);
    const s2_hash = s2_hasher.final();

    // Our sets that should be eql hash to the same value, regardless
    // of insertion order
    try testing.expect(s1_hash == s2_hash);
}

test "Superset" {
    const Term = @import("term.zig").Term;

    const testing = std.testing;
    const allocator = testing.allocator;

    var s1 = Set(Term).init(allocator);
    defer s1.deinit();

    var s2 = Set(Term).init(allocator);
    defer s2.deinit();

    var s3 = Set(Term).init(allocator);
    defer s3.deinit();

    try s1.add(.{ .integer = 1 });
    try s1.add(.{ .integer = 2 });
    try s1.add(.{ .integer = 3 });

    try s2.add(.{ .integer = 3 });
    try s2.add(.{ .integer = 2 });

    try s3.add(.{ .integer = 6 });
    try s3.add(.{ .integer = 2 });

    try testing.expect(s1.isSuperset(s2));
    try testing.expect(!s1.isSuperset(s3));
}

test "Union" {
    const Term = @import("term.zig").Term;

    const testing = std.testing;
    const allocator = testing.allocator;

    var s1 = Set(Term).init(allocator);
    defer s1.deinit();

    var s2 = Set(Term).init(allocator);
    defer s2.deinit();

    try s1.add(.{ .integer = 1 });
    try s1.add(.{ .integer = 2 });
    try s1.add(.{ .integer = 3 });

    try s2.add(.{ .integer = 4 });
    try s2.add(.{ .integer = 5 });

    var s3 = try s1.@"union"(s2);
    defer s3.deinit();

    try testing.expect(s3.contains(.{ .integer = 1 }));
    try testing.expect(s3.contains(.{ .integer = 2 }));
    try testing.expect(s3.contains(.{ .integer = 3 }));
    try testing.expect(s3.contains(.{ .integer = 4 }));
    try testing.expect(s3.contains(.{ .integer = 5 }));
}

test "Intersection" {
    const Term = @import("term.zig").Term;

    const testing = std.testing;
    const allocator = testing.allocator;

    var s1 = Set(Term).init(allocator);
    defer s1.deinit();

    var s2 = Set(Term).init(allocator);
    defer s2.deinit();

    try s1.add(.{ .integer = 1 });
    try s1.add(.{ .integer = 2 });
    try s1.add(.{ .integer = 3 });

    try s2.add(.{ .integer = 2 });
    try s2.add(.{ .integer = 3 });
    try s2.add(.{ .integer = 4 });

    var s3 = try s1.intersection(s2);
    defer s3.deinit();

    try testing.expect(s3.contains(.{ .integer = 2 }));
    try testing.expect(s3.contains(.{ .integer = 3 }));

    try testing.expect(!s3.contains(.{ .integer = 1 }));
    try testing.expect(!s3.contains(.{ .integer = 4 }));
}

test "Iterator" {
    const Term = @import("term.zig").Term;

    const testing = std.testing;
    const allocator = testing.allocator;

    var s1 = Set(Term).init(allocator);
    defer s1.deinit();

    try s1.add(.{ .integer = 1 });
    try s1.add(.{ .integer = 2 });

    var it = s1.iterator();

    try testing.expect(it.next() != null);
    try testing.expect(it.next() != null);
    try testing.expect(it.next() == null);
}
