const std = @import("std");
const Fact = @import("./datalog/fact.zig").Fact;
const Rule = @import("./datalog/rule.zig").Rule;
const Check = @import("./datalog/check.zig").Check;

pub const Block = struct {
    version: u64,
    context: []const u8,
    symbol_table: std.ArrayList([]u8),
    facts: std.ArrayList(Fact),
    rules: std.ArrayList(Rule),
    checks: std.ArrayList(Check),

    pub fn init(allocator: std.mem.Allocator) !Block {
        var symbol_table = try std.ArrayList([]u8).init(allocator);
        errdefer symbol_table.deinit();

        var facts = try std.ArrayList(Fact).init(allocator);
        errdefer facts.deinit();

        var rules = try std.ArrayList(Rule).init(allocator);
        errdefer rules.deinit();

        var checks = try std.ArrayList(Check).init(allocator);

        return .{
            .version = 0,
            .context = "",
            .symbol_table = symbol_table,
            .facts = facts,
            .rules = rules,
            .checks = checks,
        };
    }

    pub fn deinit(self: *Block) void {
        self.checks.deinit();
        self.rules.deinit();
        self.facts.deinit();
        self.symbol_table.deinit();
    }
};
