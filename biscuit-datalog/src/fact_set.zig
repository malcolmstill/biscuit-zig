const std = @import("std");
const Wyhash = std.hash.Wyhash;
const Fact = @import("fact.zig").Fact;
const Set = @import("set.zig").Set;
const Origin = @import("origin.zig").Origin;
const TrustedOrigins = @import("origin.zig").TrustedOrigins;

pub const FactSet = struct {
    sets: InnerMap,
    allocator: std.mem.Allocator,

    const InnerMap = std.HashMap(Origin, Set(Fact), Context, 80);

    const Context = struct {
        pub fn hash(ctx: Context, key: Origin) u64 {
            _ = ctx;

            // We assume here there is a method `pub hash(set: K, hasher: anytype)` on type K.
            var hasher = Wyhash.init(0);
            key.hash(&hasher);
            return hasher.final();
        }

        pub fn eql(ctx: Context, a: Origin, b: Origin) bool {
            _ = ctx;
            return a.eql(b);
        }
    };

    pub fn init(allocator: std.mem.Allocator) FactSet {
        return .{
            .sets = InnerMap.init(allocator),
            .allocator = allocator,
        };
    }

    // FIXME: to free or not to free...that is the question (to free or not free the keys?)
    // We have a similar situation as we came across else where if we use some complicated
    // value as a key, and we try to insert into hashmap that already contains that value,
    // we will leak the key if we don't detect the existing version and deallocate one of the
    // keys.
    pub fn deinit(fact_set: *FactSet) void {
        var it = fact_set.sets.iterator();

        while (it.next()) |origin_facts| {
            origin_facts.key_ptr.deinit();
            origin_facts.value_ptr.deinit();
        }

        fact_set.sets.deinit();
    }

    pub const Iterator = struct {
        set_it: InnerMap.Iterator,
        origin_fact_it: ?struct { origin: *Origin, fact_it: Set(Fact).Iterator } = null,

        pub fn next(it: *Iterator) ?struct { origin: *Origin, fact: *Fact } {
            while (true) {
                if (it.origin_fact_it) |origin_fact_it| {
                    const origin = origin_fact_it.origin;
                    var fact_it = origin_fact_it.fact_it;

                    const fact = fact_it.next() orelse {
                        it.origin_fact_it = null;
                        continue;
                    };

                    return .{ .origin = origin, .fact = fact };
                } else {
                    const origin_set = it.set_it.next() orelse return null;

                    it.origin_fact_it = .{ .origin = origin_set.key_ptr, .fact_it = origin_set.value_ptr.iterator() };

                    continue;
                }

                unreachable;
            }
        }
    };

    pub fn iterator(fact_set: FactSet) Iterator {
        return .{ .set_it = fact_set.sets.iterator() };
    }

    pub const TrustedIterator = struct {
        trusted_origins: TrustedOrigins,
        set_it: std.AutoHashMap(Origin, Set(Fact)).Iterator,
        origin_fact_it: ?struct { origin: *Origin, fact_it: Set(Fact).Iterator } = null,

        pub fn next(it: *TrustedIterator) ?struct { origin: *Origin, fact: *Fact } {
            while (true) {
                std.debug.print("start\n", .{});
                if (it.origin_fact_it) |origin_fact_it| {
                    const origin = origin_fact_it.origin;
                    var fact_it = origin_fact_it.fact_it;

                    std.debug.print("Reading next fact for origin {any}\n", .{origin});
                    const fact = fact_it.next() orelse {
                        std.debug.print("no more facts in {any}\n", .{origin});
                        it.origin_fact_it = null;

                        std.debug.print("continue ultra\n", .{});
                        continue;
                    };

                    std.debug.print("Gotta be here?\n", .{});
                    return .{ .origin = origin, .fact = fact };
                } else {
                    std.debug.assert(it.origin_fact_it == null);

                    const origin_set = it.set_it.next() orelse return null;
                    const origin = origin_set.key_ptr;

                    // If we don't trust the origin of this set, we start the loop again
                    if (!it.trusted_origins.containsAll(origin.*)) {
                        std.debug.print("continue foxbat\n", .{});
                        continue;
                    }
                    defer std.debug.assert(it.origin_fact_it != null);

                    std.debug.print("here\n", .{});
                    it.origin_fact_it = .{
                        .origin = origin,
                        .fact_it = origin_set.value_ptr.iterator(),
                    };

                    std.debug.print("continue omega\n", .{});
                    continue;
                }

                unreachable;
            }
        }
    };

    /// Return an iterator over facts that match the trusted origin.
    pub fn trustedIterator(fact_set: FactSet, trusted_origins: TrustedOrigins) TrustedIterator {
        std.debug.print("Making trusted iterator\n", .{});
        return .{ .set_it = fact_set.sets.iterator(), .trusted_origins = trusted_origins };
    }

    /// Return the total number of facts in the fact set
    pub fn count(fact_set: *FactSet) usize {
        var n: usize = 0;

        var it = fact_set.sets.valueIterator();
        while (it.next()) |facts| {
            n += facts.count();
        }

        return n;
    }

    pub fn add(fact_set: *FactSet, origin: Origin, fact: Fact) !void {
        if (fact_set.sets.getEntry(origin)) |entry| {
            try entry.value_ptr.add(fact);
        } else {
            var set = Set(Fact).init(fact_set.allocator);
            try set.add(fact);

            try fact_set.sets.put(origin, set);
        }
    }

    pub fn contains(fact_set: *const FactSet, origin: Origin, fact: Fact) bool {
        const set = fact_set.sets.get(origin) orelse return false;

        return set.contains(fact);
    }
};

test "FactSet" {
    const testing = std.testing;
    const Term = @import("term.zig").Term;

    var fs = FactSet.init(testing.allocator);
    defer fs.deinit();

    var origin = Origin.init(testing.allocator);
    // defer origin.deinit(); Freed by fs.deinit();

    try origin.insert(0);

    // var origin_equivalent = Origin.init(testing.allocator);
    // defer origin_equivalent.deinit();

    // try origin_equivalent.insert(0);

    const fact: Fact = .{ .predicate = .{ .name = 2123, .terms = std.ArrayList(Term).init(testing.allocator) } };

    try fs.add(origin, fact);

    try testing.expect(fs.sets.contains(origin));
    // try testing.expect(fs.sets.contains(origin_equivalent));

    // const first_set_equivalent = fs.sets.getEntry(origin_equivalent) orelse return error.ExpectedSet;
    const first_set = fs.sets.getEntry(origin) orelse return error.ExpectedSet;
    // std.debug.print("EQUIV set = {any} (equiv)\n", .{first_set_equivalent.value_ptr});

    {
        std.debug.print("set = {any}\n", .{first_set.value_ptr});
        var it = first_set.value_ptr.iterator();

        while (it.next()) |iterated_fact| {
            // std.debug.print("fact = {any}\n", .{iterated_fact});
            try testing.expectEqual(fact.predicate.name, iterated_fact.predicate.name);
        }
    }

    // FIXME: this infinite loops
    {
        var it = fs.iterator();
        while (it.next()) |origin_fact| {
            std.debug.print("origin = {any}, fact = {any}\n", .{ origin_fact.origin, origin_fact.fact });
            try testing.expectEqual(fact.predicate.name, origin_fact.fact.predicate.name);
        }
    }
}
