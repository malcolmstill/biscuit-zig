const std = @import("std");
const datalog = @import("biscuit-datalog");

const TermTag = enum(u8) {
    string,
    bool,
};

pub const Term = union(TermTag) {
    string: []const u8,
    bool: bool,

    pub fn deinit(_: Term) void {}

    pub fn convert(term: Term, _: std.mem.Allocator, symbols: *datalog.SymbolTable) !datalog.Term {
        return switch (term) {
            .string => |s| .{ .string = try symbols.insert(s) },
            .bool => |b| .{ .bool = b },
        };
    }
};
