const std = @import("std");
const mem = std.mem;
const meta = std.meta;
const Term = @import("term.zig").Term;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

const tag = meta.activeTag;

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

        // Integer operands
        if (tag(left) == .integer and tag(right) == .integer) {
            const i = left.integer;
            const j = right.integer;

            return switch (self) {
                .less_than => .{ .bool = i < j },
                .greater_than => .{ .bool = i > j },
                .less_or_equal => .{ .bool = i <= j },
                .greater_or_equal => .{ .bool = i >= j },
                .equal => .{ .bool = i == j },
                .not_equal => .{ .bool = i != j },
                .add => .{ .integer = i + j },
                .sub => .{ .integer = i - j },
                .mul => .{ .integer = i * j },
                .div => .{ .integer = @divExact(i, j) },
                .bitwise_and => .{ .integer = i & j },
                .bitwise_or => .{ .integer = i | j },
                .bitwise_xor => .{ .integer = i ^ j },
                else => return error.UnexpectedOperationForIntegerOperands,
            };
        } else if (tag(left) == .string and tag(right) == .string) {
            const sl = try symbols.getString(left.string);
            const sr = try symbols.getString(right.string);

            return switch (self) {
                .prefix => .{ .bool = mem.startsWith(u8, sl, sr) },
                .suffix => .{ .bool = mem.endsWith(u8, sl, sr) },
                .regex => @panic("unimplemented"),
                .contains => .{ .bool = mem.containsAtLeast(u8, sl, 1, sr) },
                .add => @panic("unimplemented"),
                .equal => .{ .bool = mem.eql(u8, sl, sr) },
                .not_equal => .{ .bool = !mem.eql(u8, sl, sr) },
                else => return error.UnexpectedOperationForStringOperands,
            };
        } else if (tag(left) == .date and tag(right) == .date) {
            const i = left.date;
            const j = right.date;

            return switch (self) {
                .less_than => .{ .bool = i < j },
                .greater_than => .{ .bool = i > j },
                .less_or_equal => .{ .bool = i <= j },
                .greater_or_equal => .{ .bool = i >= j },
                .equal => .{ .bool = i == j },
                .not_equal => .{ .bool = i != j },
                else => return error.UnexpectedOperationForDateOperands,
            };
        } else if (tag(left) == .bytes and tag(right) == .bytes) {
            return switch (self) {
                .equal => .{ .bool = left.eql(right) },
                .not_equal => .{ .bool = !left.eql(right) },
                else => return error.UnexpectedOperationForBytesOperands,
            };
        } else if (tag(left) == .bool and tag(right) == .bool) {
            const i = left.bool;
            const j = right.bool;

            return switch (self) {
                .@"and" => .{ .bool = i and j },
                .@"or" => .{ .bool = i or j },
                .equal => .{ .bool = i == j },
                .not_equal => .{ .bool = i != j },
                else => return error.UnexpectedOperationForBoolOperands,
            };
        }

        return error.UnexpectedExpression;
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
