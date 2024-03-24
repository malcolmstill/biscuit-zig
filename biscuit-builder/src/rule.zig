const std = @import("std");
const datalog = @import("biscuit-datalog");
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;
const Expression = @import("expression.zig").Expression;
const Scope = @import("scope.zig").Scope;

pub const Rule = struct {
    head: Predicate,
    body: std.ArrayList(Predicate),
    expressions: std.ArrayList(Expression),
    variables: ?std.StringHashMap(?Term),
    scopes: std.ArrayList(Scope),

    pub fn deinit(rule: Rule) void {
        rule.head.deinit();

        for (rule.body.items) |predicate| {
            predicate.deinit();
        }

        for (rule.expressions.items) |*expression| {
            expression.deinit();
        }

        rule.body.deinit();
        rule.expressions.deinit();
        rule.scopes.deinit();
    }

    /// convert to datalog predicate
    pub fn convert(rule: Rule, allocator: std.mem.Allocator, symbols: *datalog.SymbolTable) !datalog.Rule {
        const head = try rule.head.convert(allocator, symbols);

        var body = std.ArrayList(datalog.Predicate).init(allocator);
        var expressions = std.ArrayList(datalog.Expression).init(allocator);
        var scopes = std.ArrayList(datalog.Scope).init(allocator);

        for (rule.body.items) |predicate| {
            try body.append(try predicate.convert(allocator, symbols));
        }

        for (rule.expressions.items) |expression| {
            try expressions.append(try expression.convert(allocator, symbols));
        }

        for (rule.scopes.items) |scope| {
            try scopes.append(try scope.convert(allocator, symbols));
        }

        return .{
            .head = head,
            .body = body,
            .expressions = expressions,
            .scopes = scopes,
        };
    }

    pub fn format(rule: Rule, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{any} <- ", .{rule.head});
        for (rule.body.items, 0..) |*predicate, i| {
            try writer.print("{any}", .{predicate.*});
            if (i < rule.body.items.len - 1) try writer.print(", ", .{});
        }

        if (rule.expressions.items.len > 0) try writer.print(", ", .{});

        for (rule.expressions.items, 0..) |*expression, i| {
            try writer.print("{any}", .{expression.*});
            if (i < rule.expressions.items.len - 1) try writer.print(", ", .{});
        }
    }
};
