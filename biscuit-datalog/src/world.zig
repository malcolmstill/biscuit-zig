const std = @import("std");
const mem = std.mem;
const Fact = @import("fact.zig").Fact;
const Origin = @import("origin.zig").Origin;
const Rule = @import("rule.zig").Rule;

const FactSet = @import("fact_set.zig").FactSet;
const RuleSet = @import("rule_set.zig").RuleSet;
const TrustedOrigins = @import("trusted_origins.zig").TrustedOrigins;
const RunLimits = @import("run_limits.zig").RunLimits;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

pub const World = struct {
    allocator: mem.Allocator,
    fact_set: FactSet,
    rule_set: RuleSet,
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
            .fact_set = FactSet.init(allocator),
            .rule_set = RuleSet.init(allocator),
            .symbols = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(world: *World) void {
        world.symbols.deinit();
        world.rule_set.deinit();
        world.fact_set.deinit();
    }

    pub fn run(world: *World, symbols: SymbolTable) !void {
        try world.runWithLimits(symbols, .{});
    }

    pub fn runWithLimits(world: *World, symbols: SymbolTable, limits: RunLimits) !void {
        for (0..limits.max_iterations) |iteration| {
            std.debug.print("\nrunWithLimits[{}]\n", .{iteration});
            const starting_fact_count = world.fact_set.count();

            var new_fact_sets = FactSet.init(world.allocator);
            defer new_fact_sets.deinit();

            // Iterate over rules to generate new facts
            {
                var it = world.rule_set.rules.iterator();

                while (it.next()) |origin_set| {
                    const trusted_origins = origin_set.key_ptr.*;
                    const set = origin_set.value_ptr;

                    for (set.items) |*origin_rule| {
                        const origin_id: u64 = origin_rule[0];
                        const rule: Rule = origin_rule[1];

                        try rule.apply(world.allocator, origin_id, &world.fact_set, &new_fact_sets, symbols, trusted_origins);
                    }
                }
            }

            var it = new_fact_sets.iterator();
            while (it.next()) |origin_fact| {
                const existing_origin = origin_fact.origin.*;
                const fact = origin_fact.fact.*;

                var origin = try existing_origin.clone();

                if (world.fact_set.contains(origin, fact)) {
                    origin.deinit();
                    continue;
                }

                try world.fact_set.add(origin, try fact.cloneWithAllocator(world.allocator));
            }

            std.debug.print("starting_fact_count = {}, world.facts.count() = {}\n", .{ starting_fact_count, world.fact_set.count() });
            // If we haven't generated any new facts, we're done.
            if (starting_fact_count == world.fact_set.count()) {
                std.debug.print("No new facts!\n", .{});
                return;
            }

            if (world.fact_set.count() > limits.max_facts) return error.TooManyFacts;
        }

        return error.TooManyIterations;
    }

    /// Add fact with origin to world
    pub fn addFact(world: *World, origin: Origin, fact: Fact) !void {
        std.debug.print("\nworld: adding fact = {any} ({any}) \n", .{ fact, origin });
        try world.fact_set.add(origin, fact);
    }

    pub fn addRule(world: *World, origin_id: usize, scope: TrustedOrigins, rule: Rule) !void {
        std.debug.print("\nworld: adding rule = {any} ({}, {any})\n", .{ rule, origin_id, scope });
        try world.rule_set.add(origin_id, scope, rule);
    }

    pub fn queryMatch(world: *World, rule: *Rule, symbols: SymbolTable, trusted_origins: TrustedOrigins) !bool {
        return rule.findMatch(world.allocator, &world.fact_set, symbols, trusted_origins);
    }

    pub fn queryMatchAll(world: *World, rule: *Rule, symbols: SymbolTable, trusted_origins: TrustedOrigins) !bool {
        return rule.checkMatchAll(world.allocator, &world.fact_set, symbols, trusted_origins);
    }
};
