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

    pub fn deinit(self: *World) void {
        var it = self.facts.iterator();
        while (it.next()) |fact| {
            fact.deinit();
        }
        self.symbols.deinit();
        self.rules.deinit();
        self.facts.deinit();
    }

    pub fn run(self: *World, symbols: SymbolTable) !void {
        try self.runWithLimits(symbols, RunLimits{});
    }

    pub fn runWithLimits(self: *World, symbols: SymbolTable, limits: RunLimits) !void {
        std.debug.print("runWithLimits\n", .{});
        for (0..limits.max_iterations) |_| {
            const starting_fact_count = self.facts.count();

            var new_facts = Set(Fact).init(self.allocator);
            defer {
                var it = new_facts.iterator();
                while (it.next()) |fact| fact.deinit();
                new_facts.deinit();
            }

            for (self.rules.items) |*rule| {
                try rule.apply(self.allocator, &self.facts, &new_facts, symbols);
            }

            var it = new_facts.iterator();
            while (it.next()) |fact| {
                if (self.facts.contains(fact.*)) continue;
                try self.facts.add(try fact.cloneWithAllocator(self.allocator));
            }

            std.debug.print("starting_fact_count = {}, self.facts.count() = {}\n", .{ starting_fact_count, self.facts.count() });
            // If we haven't generated any new facts, we're done.
            if (starting_fact_count == self.facts.count()) {
                std.debug.print("No new facts!\n", .{});
                return;
            }

            if (self.facts.count() > limits.max_facts) return error.TooManyFacts;
        }

        return error.TooManyIterations;
    }

    pub fn addFact(self: *World, fact: Fact) !void {
        std.debug.print("world: adding fact = {any}\n", .{fact});
        try self.facts.add(try fact.clone());
    }

    pub fn addRule(self: *World, rule: Rule) !void {
        std.debug.print("world: adding rule = {any}\n", .{rule});
        try self.rules.append(rule);
    }
};
