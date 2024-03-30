const std = @import("std");
const Wyhash = std.hash.Wyhash;
const Fact = @import("fact.zig").Fact;
const Set = @import("set.zig").Set;
const Origin = @import("origin.zig").Origin;
const TrustedOrigins = @import("trusted_origins.zig").TrustedOrigins;

pub const FactSet = struct {
    sets: InnerMap,
    allocator: std.mem.Allocator,

    const InnerMap = std.HashMap(Origin, Set(Fact), Context, 80);

    const Context = struct {
        pub fn hash(ctx: Context, key: Origin) u64 {
            _ = ctx;

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
    pub fn deinit(_: *FactSet) void {
        // var it = fact_set.sets.iterator();

        // while (it.next()) |origin_facts| {
        //     origin_facts.key_ptr.deinit(); // Okay, in practice this is also giving us incorrect alignment issues
        //     origin_facts.value_ptr.deinit();
        // }

        // fact_set.sets.deinit();
    }

    pub const Iterator = struct {
        set_it: InnerMap.Iterator,
        origin_fact_it: ?struct { origin: *Origin, fact_it: Set(Fact).Iterator } = null,

        pub fn next(it: *Iterator) ?struct { origin: *Origin, fact: *Fact } {
            while (true) {
                if (it.origin_fact_it) |*origin_fact_it| {
                    if (origin_fact_it.fact_it.next()) |fact| return .{ .origin = origin_fact_it.origin, .fact = fact };

                    it.origin_fact_it = null;
                } else {
                    const origin_set = it.set_it.next() orelse return null;

                    it.origin_fact_it = .{ .origin = origin_set.key_ptr, .fact_it = origin_set.value_ptr.iterator() };
                }
            }
        }
    };

    pub fn iterator(fact_set: *const FactSet) Iterator {
        return .{ .set_it = fact_set.sets.iterator() };
    }

    pub const TrustedIterator = struct {
        trusted_origins: TrustedOrigins,
        set_it: InnerMap.Iterator,
        origin_fact_it: ?struct { origin: *Origin, fact_it: Set(Fact).Iterator } = null,

        pub fn next(it: *TrustedIterator) ?struct { origin: *Origin, fact: *Fact } {
            while (true) {
                if (it.origin_fact_it) |*origin_fact_it| {
                    if (origin_fact_it.fact_it.next()) |fact| {
                        return .{ .origin = origin_fact_it.origin, .fact = fact };
                    }

                    it.origin_fact_it = null;
                } else {
                    std.debug.assert(it.origin_fact_it == null);

                    const origin_set = it.set_it.next() orelse return null;

                    const set_ptr: *Set(Fact) = origin_set.value_ptr;
                    const origin: *Origin = origin_set.key_ptr;

                    // If we don't trust the origin of this set, we start the loop again
                    if (!it.trusted_origins.containsAll(origin)) continue;

                    defer std.debug.assert(it.origin_fact_it != null);

                    it.origin_fact_it = .{
                        .origin = origin,
                        .fact_it = set_ptr.iterator(), // Is this iterator taking
                    };
                }
            }
        }
    };

    /// Return an iterator over facts that match the trusted origin.
    pub fn trustedIterator(fact_set: *const FactSet, trusted_origins: TrustedOrigins) TrustedIterator {
        return .{ .set_it = fact_set.sets.iterator(), .trusted_origins = trusted_origins };
    }

    /// Return the total number of facts in the fact set
    pub fn count(fact_set: *const FactSet) usize {
        var n: usize = 0;

        var it = fact_set.sets.valueIterator();
        while (it.next()) |facts| {
            n += facts.count();
        }

        return n;
    }

    /// Add fact with origin to fact set.
    ///
    /// Takes ownership of (i.e. will free) origin and fact
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

test "FactSet trustedIterator" {
    const testing = std.testing;
    const Term = @import("term.zig").Term;

    var fs = FactSet.init(testing.allocator);
    defer fs.deinit();

    var origin = Origin.init(testing.allocator);
    try origin.insert(0);

    var origin2 = Origin.init(testing.allocator);
    try origin2.insert(1);

    const fact: Fact = .{ .predicate = .{ .name = 2123, .terms = std.ArrayList(Term).init(testing.allocator) } };
    const fact2: Fact = .{ .predicate = .{ .name = 2123, .terms = std.ArrayList(Term).init(testing.allocator) } };

    try fs.add(origin, fact);
    try fs.add(origin2, fact2);

    try testing.expect(fs.sets.contains(origin));
    try testing.expect(fs.sets.contains(origin2));

    // With a non-trusted iterator we expect 2 facts
    {
        var count: usize = 0;

        var it = fs.iterator();
        while (it.next()) |origin_fact| {
            defer count += 1;

            try testing.expectEqual(fact.predicate.name, origin_fact.fact.predicate.name);
        }

        try testing.expectEqual(2, count);
    }

    // With a trusted iterator only trusting [0] we only expect a single fact
    {
        var trusted_origins = try TrustedOrigins.defaultOrigins(testing.allocator);
        defer trusted_origins.deinit();

        var count: usize = 0;

        var it = fs.trustedIterator(trusted_origins);
        while (it.next()) |origin_fact| {
            defer count += 1;

            try testing.expectEqual(fact.predicate.name, origin_fact.fact.predicate.name);
        }

        try testing.expectEqual(1, count);
    }
}
