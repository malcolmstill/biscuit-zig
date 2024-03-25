const std = @import("std");
const Fact = @import("fact.zig").Fact;
const Set = @import("set.zig").Set;
const Origin = @import("origin.zig").Origin;
const TrustedOrigins = @import("origin.zig").TrustedOrigins;

pub const FactSet = struct {
    sets: std.AutoHashMap(Origin, Set(Fact)),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FactSet {
        return .{
            .sets = std.AutoHashMap(Origin, Set(Fact)).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(fact_set: *FactSet) void {
        var it = fact_set.sets.iterator();

        while (it.next()) |origin_facts| {
            origin_facts.key_ptr.deinit();
            origin_facts.value_ptr.deinit();
        }

        fact_set.sets.deinit();
    }

    pub const Iterator = struct {
        set_it: std.AutoHashMap(Origin, Set(Fact)).Iterator,
        origin_fact_it: ?struct { origin: *Origin, fact_it: Set(Fact).Iterator } = null,

        pub fn next(it: *Iterator) ?struct { origin: *Origin, fact: *Fact } {
            while (true) {
                if (it.origin_fact_it) |origin_fact_it| {
                    //
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

    var fs = FactSet.init(testing.allocator);
    defer fs.deinit();

    const origin = Origin.init(testing.allocator);
    const fact: Fact = undefined;

    try fs.add(origin, fact);
    std.debug.print("fs = {any}\n", .{fs});
}
