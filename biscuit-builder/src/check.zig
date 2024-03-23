const std = @import("std");
const datalog = @import("biscuit-datalog");
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;

pub const Check = struct {
    pub fn deinit(_: Check) void {
        //
    }
};
