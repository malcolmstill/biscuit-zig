const std = @import("std");
const fct = @import("fact.zig");
const Fact = fct.Fact;
const Rule = @import("rule.zig").Rule;

const Set = @import("set.zig").Set;
const RunLimits = @import("run_limits.zig").RunLimits;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

pub const World = struct {
    allocator: std.mem.Allocator,
    facts: Set(Fact),
    rules: std.ArrayList(Rule),
    symbols: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) World {
        return .{
            .allocator = allocator,
            .facts = Set(Fact).init(allocator),
            .rules = std.ArrayList(Rule).init(allocator),
            .symbols = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *World) void {
        self.symbols.deinit();
        self.rules.deinit();
        self.facts.deinit();
    }

    pub fn run(self: *World, symbols: SymbolTable) !void {
        try self.runWithLimits(symbols, RunLimits{});
    }

    pub fn runWithLimits(self: *World, symbols: SymbolTable, limits: RunLimits) !void {
        for (0..limits.max_iterations) |_| {
            const starting_fact_count = self.facts.count();

            var new_facts = Set(Fact).init(self.allocator);
            defer new_facts.deinit();

            for (self.rules.items) |*rule| {
                try rule.apply(&self.facts, &new_facts, symbols);
            }

            var it = new_facts.iterator();
            while (it.next()) |fact| {
                try self.facts.add(fact.*);
            }

            // If we haven't generated any new facts, we're done.
            if (starting_fact_count == self.facts.count()) return;

            if (self.facts.count() > limits.max_facts) return error.TooManyFacts;
        }

        return error.TooManyIterations;
    }

    pub fn addFact(self: *World, fact: Fact) !void {
        std.debug.print("world: adding fact = {any}\n", .{fact});
        try self.facts.add(fact);
    }

    pub fn addRule(self: *World, rule: Rule) !void {
        std.debug.print("world: adding rule = {any}\n", .{rule});
        try self.rules.append(rule);
    }
};
