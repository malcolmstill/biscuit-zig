const std = @import("std");
const datalog = @import("biscuit-datalog");
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;

pub const Fact = struct {
    predicate: Predicate,
    variables: ?std.StringHashMap(?Term),

    pub fn deinit(fact: Fact) void {
        fact.predicate.deinit();
    }

    /// convert to datalog fact
    pub fn convert(_: Fact) datalog.Fact {
        unreachable;
    }
};
