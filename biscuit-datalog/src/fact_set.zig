const std = @import("std");
const Fact = @import("fact.zig").Fact;
const Set = @import("set.zig").Set;
const Origin = @import("origin.zig").Origin;

pub const FactSet = struct {
    facts: std.AutoHashMap(Origin, Set(Fact)),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FactSet {
        return .{
            .facts = std.AutoHashMap(Origin, Set(Fact)).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(fact_set: *FactSet) void {
        var it = fact_set.facts.iterator();

        while (it.next()) |entry| {
            entry.key_ptr.deinit();
            entry.value_ptr.deinit();
        }

        fact_set.facts.deinit();
    }

    pub fn add(fact_set: *FactSet, origin: Origin, fact: Fact) !void {
        if (fact_set.facts.getEntry(origin)) |entry| {
            try entry.value_ptr.add(fact);
        } else {
            var set = Set(Fact).init(fact_set.allocator);
            try set.add(fact);

            try fact_set.facts.put(origin, set);
        }
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
