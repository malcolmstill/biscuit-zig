const std = @import("std");
const meta = std.meta;
const trait = std.meta.trait;
const Wyhash = std.hash.Wyhash;
const Fact = @import("fact.zig").Fact;

/// Set wraps the std.HashMap and uses a hash function defined
/// by a method assumed to exist on type K with name "hash".
pub fn Set(comptime K: type) type {
    return struct {
        inner: InnerSet,

        const InnerSet = std.HashMap(K, void, Context, 80);
        const Self = @This();

        pub const Iterator = InnerSet.KeyIterator;

        const Context = struct {
            pub fn hash(ctx: Context, key: K) u64 {
                _ = ctx;

                // We assume here there is a method `pub hash(self: K, hasher: anytype)` on type K.
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
            };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        pub fn iterator(self: Self) InnerSet.KeyIterator {
            return self.inner.keyIterator();
        }

        pub fn add(self: *Self, value: K) !void {
            try self.inner.put(value, {});
        }

        pub fn contains(self: *Self, value: K) bool {
            return self.inner.contains(value);
        }

        pub fn count(self: *Self) u32 {
            return self.inner.count();
        }
    };
}

test {
    const Predicate = @import("predicate.zig").Predicate;
    const testing = std.testing;
    const allocator = testing.allocator;

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
}
