const std = @import("std");
const meta = std.meta;
const Term = @import("term.zig").Term;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

const Expression = []Op;

const OpKind = enum(u8) {
    value,
    unary,
    binary,
};

const Op = union(OpKind) {
    value: Term,
    unary: Unary,
    binary: Binary,
};

const Unary = enum {
    negate,
    parens,
    length,

    pub fn evaluate(self: Unary, value: Term, symbols: SymbolTable) !Term {
        _ = symbols; // Different type instead of SymbolTable
        //
        return switch (self) {
            .negate => if (meta.activeTag(value) == .bool) !value.bool else return error.UnexpectedTermInUnaryNegate,
            .parens => value,
            else => error.UnexpectedUnaryTermCombination,
        };
    }
};

const Binary = enum {
    less_than,
    greater_than,
    less_or_equal,
    greater_or_equal,
    equal,
    contains,
    prefix,
    suffix,
    regex,
    add,
    sub,
    mul,
    div,
    @"and",
    @"or",
    intersection,
    @"union",
    bitwise_and,
    bitwise_or,
    bitwise_xor,
    not_equal,

    pub fn evaluate(self: Binary, left: Term, right: Term, symbols: SymbolTable) !Term {
        _ = symbols;
        switch (self) {
            .less_than,
            .greater_than,
            .less_or_equal,
            .greater_or_equal,
            .equal,
            .not_equal,
            => |op| {
                const i = if (meta.activeTag(left) == .integer) left.integer else return error.BinaryExpectedInteger;
                const j = if (meta.activeTag(right) == .integer) right.integer else return error.BinaryExpectedInteger;

                const b = switch (op) {
                    .less_than => i < j,
                    .greater_than => i > j,
                    .less_or_equal => i <= j,
                    .greater_or_equal => i >= j,
                    .equal => i == j,
                    .not_equal => i != j,
                    else => @panic("unexpected op"),
                };

                return .{ .bool = b };
            },
            .add,
            .sub,
            .mul,
            .div,
            .bitwise_and,
            .bitwise_or,
            .bitwise_xor,
            => |op| {
                const i = if (meta.activeTag(left) == .integer) left.integer else return error.BinaryExpectedInteger;
                const j = if (meta.activeTag(right) == .integer) right.integer else return error.BinaryExpectedInteger;

                const res = switch (op) {
                    .add => i + j,
                    .sub => i - j,
                    .mul => i * j,
                    .div => @divExact(i, j),
                    .bitwise_and => i & j,
                    .bitwise_or => i | j,
                    .bitwise_xor => i ^ j,
                    else => @panic("unexpected op"),
                };

                return .{ .integer = res };
            },
            else => @panic("unimplemented"),
        }
    }
};

test {
    const testing = std.testing;

    const t1: Term = .{ .integer = 10 };
    const t2: Term = .{ .integer = 22 };

    try testing.expectEqual(@as(Term, .{ .bool = false }), try Binary.equal.evaluate(t1, t2, SymbolTable.init(testing.allocator)));
    try testing.expectEqual(@as(Term, .{ .bool = true }), try Binary.equal.evaluate(t1, t1, SymbolTable.init(testing.allocator)));

    try testing.expectEqual(@as(Term, .{ .integer = 32 }), try Binary.add.evaluate(t1, t2, SymbolTable.init(testing.allocator)));
    try testing.expectEqual(@as(Term, .{ .integer = 220 }), try Binary.mul.evaluate(t1, t2, SymbolTable.init(testing.allocator)));
}
