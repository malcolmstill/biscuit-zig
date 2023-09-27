const std = @import("std");
const schema = @import("../token/format/schema.pb.zig");
const Set = @import("set.zig").Set;
const fct = @import("fact.zig");
const Fact = fct.Fact;
const Predicate = @import("predicate.zig").Predicate;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

pub const Rule = struct {
    head: Predicate,
    body: std.ArrayList(Predicate),

    pub fn fromSchema(allocator: std.mem.Allocator, rule: schema.RuleV2) !Rule {
        const head = try Predicate.fromSchema(allocator, rule.head orelse return error.NoHeadInRuleSchema);

        var body = std.ArrayList(Predicate).init(allocator);
        for (rule.body.items) |predicate| {
            try body.append(try Predicate.fromSchema(allocator, predicate));
        }

        return .{ .head = head, .body = body };
    }

    pub fn deinit(self: *Rule) void {
        self.head.deinit();
        for (self.body.items) |*predicate| {
            predicate.deinit();
        }
        self.body.deinit();
    }

    pub fn format(self: Rule, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) std.os.WriteError!void {
        try writer.print("{any} <- ", .{self.head});
        for (self.body.items, 0..) |*predicate, i| {
            try writer.print("{any}", .{predicate.*});
            if (i < self.body.items.len - 1) try writer.print(", ", .{});
        }
    }

    pub fn apply(self: *Rule, facts: *const Set(Fact), new_facts: *Set(Fact), symbols: SymbolTable) !void {
        _ = self;
        _ = symbols;
        _ = new_facts;
        var it = facts.iterator();
        while (it.next()) |fact| {
            _ = fact;
        }
    }
};
