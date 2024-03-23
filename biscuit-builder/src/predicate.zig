const std = @import("std");
const datalog = @import("biscuit-datalog");
const Term = @import("term.zig").Term;

pub const Predicate = struct {
    name: []const u8,
    terms: std.ArrayList(Term),

    pub fn deinit(predicate: Predicate) void {
        predicate.terms.deinit();
    }

    /// convert to datalog predicate
    pub fn convert(_: Predicate) datalog.Predicate {
        unreachable;
    }
};
