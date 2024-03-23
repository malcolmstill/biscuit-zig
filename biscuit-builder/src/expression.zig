const std = @import("std");
const datalog = @import("biscuit-datalog");
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;

pub const Expression = struct {
    /// convert to datalog fact
    pub fn convert(_: Expression, _: std.mem.Allocator, _: *datalog.SymbolTable) !datalog.Expression {
        unreachable;
    }
};
