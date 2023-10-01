const std = @import("std");

pub const Fact = struct {
    name: []const u8,
    terms: std.ArrayList(Term),

    pub fn init(name: []const u8, terms: std.ArrayList(Term)) Fact {
        return .{ .name = name, .terms = terms };
    }
};

const TermKind = enum(u8) {
    integer,
};

pub const Term = union(TermKind) {
    integer: i64,
};
