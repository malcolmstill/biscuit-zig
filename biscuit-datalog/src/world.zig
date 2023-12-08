const std = @import("std");
const mem = std.mem;
const Fact = @import("fact.zig").Fact;
const Rule = @import("rule.zig").Rule;

const Set = @import("set.zig").Set;
const RunLimits = @import("run_limits.zig").RunLimits;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

pub const World = struct {
    allocator: mem.Allocator,
    facts: Set(Fact),
    rules: std.ArrayList(Rule),
    symbols: std.ArrayList([]const u8),

    /// init world
    ///
    /// Note: the allocator we pass in can be any allocator. This allocator
    /// is used purely for the toplevel Set and ArrayLists. Any facts allocated
    /// during world run will be allocated with a provided allocator that is
    /// specifically an arena. The world and rule code will reflect that by
    /// not doing explicit deallocation on the fact / predicate / term level.
    ///
    /// If we ever want to change away from that arena model, we'll have to
    /// fix up some code internally to allow that.
    pub fn init(allocator: mem.Allocator) World {
        return .{
            .allocator = allocator,
            .facts = Set(Fact).init(allocator),
            .rules = std.ArrayList(Rule).init(allocator),
            .symbols = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(world: *World) void {
        var it = world.facts.iterator();
        while (it.next()) |fact| {
            fact.deinit();
        }
        world.symbols.deinit();
        world.rules.deinit();
        world.facts.deinit();
    }

    pub fn run(world: *World, symbols: SymbolTable) !void {
        try world.runWithLimits(symbols, .{});
    }

    pub fn runWithLimits(world: *World, symbols: SymbolTable, limits: RunLimits) !void {
        std.log.debug("runWithLimits\n", .{});
        for (0..limits.max_iterations) |_| {
            const starting_fact_count = world.facts.count();

            var new_facts = Set(Fact).init(world.allocator);
            defer {
                var it = new_facts.iterator();
                while (it.next()) |fact| fact.deinit();
                new_facts.deinit();
            }

            for (world.rules.items) |*rule| {
                try rule.apply(world.allocator, &world.facts, &new_facts, symbols);
            }

            var it = new_facts.iterator();
            while (it.next()) |fact| {
                if (world.facts.contains(fact.*)) continue;
                try world.facts.add(try fact.cloneWithAllocator(world.allocator));
            }

            std.log.debug("starting_fact_count = {}, world.facts.count() = {}\n", .{ starting_fact_count, world.facts.count() });
            // If we haven't generated any new facts, we're done.
            if (starting_fact_count == world.facts.count()) {
                std.log.debug("No new facts!\n", .{});
                return;
            }

            if (world.facts.count() > limits.max_facts) return error.TooManyFacts;
        }

        return error.TooManyIterations;
    }

    pub fn addFact(world: *World, fact: Fact) !void {
        std.log.debug("world: adding fact = {any}\n", .{fact});
        try world.facts.add(fact);
    }

    pub fn addRule(world: *World, rule: Rule) !void {
        std.log.debug("world: adding rule = {any}\n", .{rule});
        try world.rules.append(rule);
    }

    pub fn queryMatch(world: *World, rule: *Rule, symbols: SymbolTable) !bool {
        return rule.findMatch(world.allocator, &world.facts, symbols);
    }
};
