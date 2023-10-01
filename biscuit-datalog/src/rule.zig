const std = @import("std");
const mem = std.mem;
const schema = @import("biscuit-schema");
const Set = @import("set.zig").Set;
const Fact = @import("fact.zig").Fact;
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;
const SymbolTable = @import("symbol_table.zig").SymbolTable;
const MatchedVariables = @import("matched_variables.zig").MatchedVariables;
const Combinator = @import("combinator.zig").Combinator;

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
        var matched_variables = try MatchedVariables.init(allocator, self);
        defer matched_variables.deinit();

        // TODO: if body is empty stuff

        var it = Combinator.init(allocator, matched_variables, self.body, facts, symbols);
        while (it.next()) |*bindings| {
            var unbound = false;

            // Iterate over the terms in this rule's head. We make a copy
            // first
            var new_predicate: Predicate = try self.head.clone();
            for (new_predicate.terms.items, 0..) |head_term, i| {
                switch (head_term) {
                    .variable => |id| {
                        // Get the term bound to this variable (where it exists)
                        // in the potential new fact.
                        if (bindings.get(id)) |value| {
                            new_predicate.terms.items[i] = value;
                        } else {
                            unbound = true;
                        }
                    },
                    else => continue,
                }
            }

            if (!unbound) {
                try new_facts.add(Fact.init(new_predicate));
            }
        }
    }
};
