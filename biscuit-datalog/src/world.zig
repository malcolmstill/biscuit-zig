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

const log = std.log.scoped(.world);

pub const World = struct {
    arena: mem.Allocator,
    fact_set: FactSet,
    rule_set: RuleSet,

    pub fn init(arena: mem.Allocator) World {
        return .{
            .arena = arena,
            .fact_set = FactSet.init(arena),
            .rule_set = RuleSet.init(arena),
        };
    }

    pub fn deinit(_: *World) void {
        // world.symbols.deinit();
        // world.rule_set.deinit();
        // world.fact_set.deinit();
    }

    /// Generate all facts from rules and existing facts
    ///
    /// Uses default run limits.
    pub fn run(world: *World, symbols: *SymbolTable) !void {
        try world.runWithLimits(symbols, .{});
    }

    /// Generate all facts from rules and existing facts
    ///
    /// User specifies run limits.
    pub fn runWithLimits(world: *World, symbols: *SymbolTable, limits: RunLimits) !void {
        for (0..limits.max_iterations) |iteration| {
            log.debug("runWithLimits[{}]", .{iteration});
            const starting_fact_count = world.fact_set.count();

            var new_fact_sets = FactSet.init(world.arena);
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

                        try rule.apply(world.arena, origin_id, &world.fact_set, &new_fact_sets, symbols, trusted_origins);
                    }
                }
            }

            var it = new_fact_sets.iterator();
            while (it.next()) |origin_fact| {
                const origin = origin_fact.origin.*;
                const fact = origin_fact.fact.*;

                try world.fact_set.add(origin, fact);
            }

            log.debug("starting_fact_count = {}, world.facts.count() = {}", .{ starting_fact_count, world.fact_set.count() });
            // If we haven't generated any new facts, we're done.
            if (starting_fact_count == world.fact_set.count()) {
                log.debug("No new facts!", .{});
                return;
            }

            if (world.fact_set.count() > limits.max_facts) return error.TooManyFacts;
        }

        return error.TooManyIterations;
    }

    /// Add fact with origin to world
    pub fn addFact(world: *World, origin: Origin, fact: Fact) !void {
        log.debug("adding fact = {any}, origin = ({any})", .{ fact, origin });

        try world.fact_set.add(origin, fact);
    }

    // Add rule trusting scope from origin
    pub fn addRule(world: *World, origin_id: usize, scope: TrustedOrigins, rule: Rule) !void {
        log.debug("adding rule {any}, origin = {}, trusts {any}", .{ rule, origin_id, scope });
        try world.rule_set.add(origin_id, scope, rule);
    }

    pub fn queryMatch(world: *World, rule: *Rule, symbols: *SymbolTable, trusted_origins: TrustedOrigins) !bool {
        return rule.findMatch(world.arena, &world.fact_set, symbols, trusted_origins);
    }

    pub fn queryMatchAll(world: *World, rule: *Rule, symbols: *SymbolTable, trusted_origins: TrustedOrigins) !bool {
        return rule.checkMatchAll(world.arena, &world.fact_set, symbols, trusted_origins);
    }
};
