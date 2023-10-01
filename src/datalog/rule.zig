const std = @import("std");
const mem = std.mem;
const schema = @import("../token/format/schema.pb.zig");
const Set = @import("set.zig").Set;
const fct = @import("fact.zig");
const Fact = fct.Fact;
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;
const SymbolTable = @import("symbol_table.zig").SymbolTable;
const MatchedVariables = @import("matched_variables.zig").MatchedVariables;

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

    pub fn apply(self: *Rule, allocator: mem.Allocator, facts: *const Set(Fact), new_facts: *Set(Fact), symbols: SymbolTable) !void {
        _ = allocator;
        _ = self;
        _ = facts;
        _ = symbols;
        _ = new_facts;

        // var matched_variables = try MatchedVariables.init(allocator, self);
        // defer matched_variables.deinit();

        // TODO: if body is empty stuff
    }
};
