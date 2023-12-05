const std = @import("std");
const mem = std.mem;
const Term = @import("term.zig").Term;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

const Expression = struct {
    ops: []Op,

    pub fn evaluate(expr: Expression, allocator: mem.Allocator, values: std.AutoHashMap(u32, Term), symbols: SymbolTable) !Term {
        var stack = std.ArrayList(Term).init(allocator);
        defer stack.deinit();

        for (expr.ops) |op| {
            switch (op) {
                .value => |term| {
                    switch (term) {
                        .variable => |i| {
                            const value = values.get(i) orelse return error.UnknownVariable;
                            try stack.append(value);
                        },
                        else => try stack.append(term),
                    }
                },
                .unary => |unary_op| {
                    const operand = stack.popOrNull() orelse return error.StackUnderflow;

                    const result = try unary_op.evaluate(operand, symbols);

                    try stack.append(result);
                },
                .binary => |binary_op| {
                    const right = stack.popOrNull() orelse return error.StackUnderflow;
                    const left = stack.popOrNull() orelse return error.StackUnderflow;

                    const result = try binary_op.evaluate(left, right, symbols);

                    try stack.append(result);
                },
            }
        }

        if (stack.items.len != 1) return error.InvalidStack;

        return stack.items[0];
    }
};

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
            .negate => if (value == .bool) .{ .bool = !value.bool } else return error.UnexpectedTermInUnaryNegate,
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
        if (left == .integer and right == .integer) {
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
        } else if (left == .string and right == .string) {
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
        } else if (left == .date and right == .date) {
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
        } else if (left == .bytes and right == .bytes) {
            return switch (self) {
                .equal => .{ .bool = left.eql(right) },
                .not_equal => .{ .bool = !left.eql(right) },
                else => return error.UnexpectedOperationForBytesOperands,
            };
        } else if (left == .set and right == .set) {
            return switch (self) {
                .equal => .{ .bool = left.set.eql(right.set) },
                .not_equal => .{ .bool = !left.set.eql(right.set) },
                .intersection => .{ .set = try left.set.intersection(right.set) },
                .@"union" => .{ .set = try left.set.@"union"(right.set) },
                .contains => .{ .bool = left.set.isSuperset(right.set) },
                else => return error.UnexpectedOperationForSetSetOperands,
            };
        } else if (left == .set) {
            return switch (self) {
                .contains => .{ .bool = left.set.contains(right) },
                else => return error.UnexpectedOperationForSetTermOperands,
            };
        } else if (left == .bool and right == .bool) {
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

    var symbols = SymbolTable.init(testing.allocator);
    defer symbols.deinit();

    const s = .{ .string = try symbols.insert("prefix_middle_suffix") };
    const prefix = .{ .string = try symbols.insert("prefix") };
    const suffix = .{ .string = try symbols.insert("suffix") };
    const middle = .{ .string = try symbols.insert("middle") };

    try testing.expectEqual(@as(Term, .{ .bool = true }), try Binary.equal.evaluate(s, s, symbols));
    try testing.expectEqual(@as(Term, .{ .bool = false }), try Binary.equal.evaluate(s, prefix, symbols));
    try testing.expectEqual(@as(Term, .{ .bool = true }), try Binary.not_equal.evaluate(s, prefix, symbols));
    try testing.expectEqual(@as(Term, .{ .bool = true }), try Binary.prefix.evaluate(s, prefix, symbols));
    try testing.expectEqual(@as(Term, .{ .bool = true }), try Binary.suffix.evaluate(s, suffix, symbols));
    try testing.expectEqual(@as(Term, .{ .bool = true }), try Binary.contains.evaluate(s, middle, symbols));
}

test "negate" {
    const testing = std.testing;

    var symbols = SymbolTable.init(testing.allocator);
    defer symbols.deinit();

    _ = try symbols.insert("test1");
    _ = try symbols.insert("test2");
    _ = try symbols.insert("var1");
    // var tmp_symbols = TemporarySymbolTable.init(testing.allocator, &symbols);

    var ops = [_]Op{
        .{ .value = .{ .integer = 1 } },
        .{ .value = .{ .variable = 2 } },
        .{ .binary = .less_than },
        .{ .unary = .parens },
        .{ .unary = .negate },
    };

    var values = std.AutoHashMap(u32, Term).init(testing.allocator);
    defer values.deinit();

    try values.put(2, .{ .integer = 0 });

    const expr: Expression = .{ .ops = ops[0..] };

    // FIXME: tmp_symbols
    const res = try expr.evaluate(testing.allocator, values, symbols);

    try testing.expectEqual(@as(Term, .{ .bool = true }), res);
}
