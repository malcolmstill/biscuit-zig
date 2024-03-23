const std = @import("std");
const datalog = @import("biscuit-datalog");
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;
const Rule = @import("rule.zig").Rule;

pub const Check = struct {
    kind: datalog.Check.Kind,
    queries: std.ArrayList(Rule),

    pub fn deinit(_: Check) void {
        //
    }
};
