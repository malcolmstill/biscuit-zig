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

        rule.body.deinit();
        rule.expressions.deinit();
        rule.scopes.deinit();
    }

    /// convert to datalog predicate
    pub fn convert(_: Rule) datalog.Rule {
        unreachable;
    }
};
