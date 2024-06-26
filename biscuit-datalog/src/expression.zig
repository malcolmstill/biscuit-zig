const std = @import("std");
const mem = std.mem;
const schema = @import("biscuit-schema");
const builder = @import("biscuit-builder");
const Regex = @import("regex").Regex;
const Term = @import("term.zig").Term;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

const log = std.log.scoped(.expression);

pub const Expression = struct {
    ops: std.ArrayList(Op),

    pub fn fromSchema(arena: std.mem.Allocator, schema_expression: schema.ExpressionV2) !Expression {
        var ops = try std.ArrayList(Op).initCapacity(arena, schema_expression.ops.items.len);

        for (schema_expression.ops.items) |schema_op| {
            const schema_op_content = schema_op.Content orelse return error.ExpectedOp;
            const op: Op = switch (schema_op_content) {
                .value => |term| .{ .value = try Term.fromSchema(arena, term) },
                .unary => |unary_op| .{
                    .unary = switch (unary_op.kind) {
                        .Negate => .negate,
                        .Parens => .parens,
                        .Length => .length,
                        else => return error.UnknownSchemaUnaryOp,
                    },
                },
                .Binary => |binary_op| .{
                    .binary = switch (binary_op.kind) {
                        .LessThan => .less_than,
                        .GreaterThan => .greater_than,
                        .LessOrEqual => .less_or_equal,
                        .GreaterOrEqual => .greater_or_equal,
                        .Equal => .equal,
                        .Contains => .contains,
                        .Prefix => .prefix,
                        .Suffix => .suffix,
                        .Regex => .regex,
                        .Add => .add,
                        .Sub => .sub,
                        .Mul => .mul,
                        .Div => .div,
                        .And => .@"and",
                        .Or => .@"or",
                        .Intersection => .intersection,
                        .Union => .@"union",
                        .BitwiseAnd => .bitwise_and,
                        .BitwiseOr => .bitwise_or,
                        .BitwiseXor => .bitwise_xor,
                        .NotEqual => .not_equal,
                        else => return error.UnknownSchemaBinaryOp,
                    },
                },
            };

            try ops.append(op);
        }

        return .{ .ops = ops };
    }

    pub fn deinit(_: *Expression) void {
        // expression.ops.deinit();
    }

    pub fn evaluate(expr: Expression, allocator: mem.Allocator, values: std.AutoHashMap(u32, Term), symbols: *SymbolTable) !Term {
        var stack = std.ArrayList(Term).init(allocator);
        defer stack.deinit();

        for (expr.ops.items) |op| {
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

                    const result = try binary_op.evaluate(allocator, left, right, symbols);

                    try stack.append(result);
                },
            }
        }

        if (stack.items.len != 1) return error.InvalidStack;

        return stack.items[0];
    }

    pub fn remap(expression: Expression, old_symbols: *const SymbolTable, new_symbols: *SymbolTable) !Expression {
        const ops = try expression.ops.clone();

        for (ops.items, 0..) |op, i| {
            ops.items[i] = switch (op) {
                .value => |trm| .{ .value = try trm.remap(old_symbols, new_symbols) },
                else => op,
            };
        }

        return .{ .ops = ops };
    }

    /// convert to datalog fact
    pub fn from(expression: builder.Expression, allocator: std.mem.Allocator, symbols: *SymbolTable) !Expression {
        var ops = std.ArrayList(Op).init(allocator);

        try Expression.toOpcodes(expression, allocator, &ops, symbols);

        return .{ .ops = ops };
    }

    pub fn toOpcodes(expression: builder.Expression, allocator: std.mem.Allocator, ops: *std.ArrayList(Op), symbols: *SymbolTable) !void {
        switch (expression) {
            .value => |v| try ops.append(.{ .value = try Term.from(v, allocator, symbols) }),
            .unary => |u| {
                try Expression.toOpcodes(u.expression.*, allocator, ops, symbols);

                try ops.append(.{
                    .unary = switch (u.op) {
                        .negate => .negate,
                        .parens => .parens,
                        .length => .length,
                    },
                });
            },
            .binary => |b| {
                try Expression.toOpcodes(b.left.*, allocator, ops, symbols);
                try Expression.toOpcodes(b.right.*, allocator, ops, symbols);

                try ops.append(.{
                    .binary = switch (b.op) {
                        .less_than => .less_than,
                        .greater_than => .greater_than,
                        .less_or_equal => .less_or_equal,
                        .greater_or_equal => .greater_or_equal,
                        .equal => .equal,
                        .contains => .contains,
                        .prefix => .prefix,
                        .suffix => .suffix,
                        .regex => .regex,
                        .add => .add,
                        .sub => .sub,
                        .mul => .mul,
                        .div => .div,
                        .@"and" => .@"and",
                        .@"or" => .@"or",
                        .intersection => .intersection,
                        .@"union" => .@"union",
                        .bitwise_and => .bitwise_and,
                        .bitwise_or => .bitwise_or,
                        .bitwise_xor => .bitwise_xor,
                        .not_equal => .not_equal,
                    },
                });
            },
        }
    }

    pub fn format(expression: Expression, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        for (expression.ops.items) |op| {
            switch (op) {
                .value => |v| try writer.print("{any}", .{v}),
                .unary => |u| {
                    switch (u) {
                        .negate => try writer.print("neg", .{}),
                        .parens => try writer.print("paren", .{}),
                        .length => try writer.print("length", .{}),
                    }
                },
                .binary => |b| {
                    switch (b) {
                        .less_than => try writer.print("<", .{}),
                        .greater_than => try writer.print(">", .{}),
                        .less_or_equal => try writer.print("<=", .{}),
                        .greater_or_equal => try writer.print(">=", .{}),
                        .equal => try writer.print("==", .{}),
                        .contains => try writer.print("contains", .{}),
                        .prefix => try writer.print("starts_with", .{}),
                        .suffix => try writer.print("ends_with", .{}),
                        .regex => try writer.print("matches", .{}),
                        .add => try writer.print("+", .{}),
                        .sub => try writer.print("-", .{}),
                        .mul => try writer.print("*", .{}),
                        .div => try writer.print("/", .{}),
                        .@"and" => try writer.print("&&", .{}),
                        .@"or" => try writer.print("||", .{}),
                        .intersection => try writer.print("intersection", .{}),
                        .@"union" => try writer.print("union", .{}),
                        .bitwise_and => try writer.print("&", .{}),
                        .bitwise_or => try writer.print("|", .{}),
                        .bitwise_xor => try writer.print("^", .{}),
                        .not_equal => try writer.print("!=", .{}),
                    }
                },
            }

            try writer.print(" ", .{});
        }
    }
};

const OpKind = enum(u8) {
    value,
    unary,
    binary,
};

pub const Op = union(OpKind) {
    value: Term,
    unary: Unary,
    binary: Binary,
};

const Unary = enum {
    negate,
    parens,
    length,

    pub fn evaluate(expr: Unary, value: Term, symbols: *SymbolTable) !Term {
        return switch (expr) {
            .negate => if (value == .bool) .{ .bool = !value.bool } else return error.UnexpectedTermInUnaryNegate,
            .parens => value,
            .length => .{
                .integer = switch (value) {
                    .string => |index| std.math.cast(i64, (try symbols.getString(index)).len) orelse return error.FailedToCaseInt,
                    .bytes => |b| std.math.cast(i64, b.len) orelse return error.FailedToCaseInt,
                    .set => |s| std.math.cast(i64, s.count()) orelse return error.FailedToCaseInt,
                    else => return error.LengthNotSupportedOnValue,
                },
            },
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

    pub fn evaluate(expr: Binary, allocator: std.mem.Allocator, left: Term, right: Term, symbols: *SymbolTable) !Term {
        // Integer operands
        if (left == .integer and right == .integer) {
            const i = left.integer;
            const j = right.integer;

            return switch (expr) {
                .less_than => .{ .bool = i < j },
                .greater_than => .{ .bool = i > j },
                .less_or_equal => .{ .bool = i <= j },
                .greater_or_equal => .{ .bool = i >= j },
                .equal => .{ .bool = i == j },
                .not_equal => .{ .bool = i != j },
                .add => .{ .integer = try std.math.add(i64, i, j) },
                .sub => .{ .integer = try std.math.sub(i64, i, j) },
                .mul => .{ .integer = try std.math.mul(i64, i, j) },
                .div => .{ .integer = @divExact(i, j) },
                .bitwise_and => .{ .integer = i & j },
                .bitwise_or => .{ .integer = i | j },
                .bitwise_xor => .{ .integer = i ^ j },
                else => return error.UnexpectedOperationForIntegerOperands,
            };
        } else if (left == .string and right == .string) {
            const sl = try symbols.getString(left.string);
            const sr = try symbols.getString(right.string);

            return switch (expr) {
                .prefix => .{ .bool = mem.startsWith(u8, sl, sr) },
                .suffix => .{ .bool = mem.endsWith(u8, sl, sr) },
                .regex => .{ .bool = try match(allocator, sr, sl) },
                .contains => .{ .bool = mem.containsAtLeast(u8, sl, 1, sr) },
                .add => .{ .string = try symbols.insert(try concat(allocator, sl, sr)) },
                .equal => .{ .bool = mem.eql(u8, sl, sr) },
                .not_equal => .{ .bool = !mem.eql(u8, sl, sr) },
                else => return error.UnexpectedOperationForStringOperands,
            };
        } else if (left == .date and right == .date) {
            const i = left.date;
            const j = right.date;

            return switch (expr) {
                .less_than => .{ .bool = i < j },
                .greater_than => .{ .bool = i > j },
                .less_or_equal => .{ .bool = i <= j },
                .greater_or_equal => .{ .bool = i >= j },
                .equal => .{ .bool = i == j },
                .not_equal => .{ .bool = i != j },
                else => return error.UnexpectedOperationForDateOperands,
            };
        } else if (left == .bytes and right == .bytes) {
            return switch (expr) {
                .equal => .{ .bool = left.eql(right) },
                .not_equal => .{ .bool = !left.eql(right) },
                else => return error.UnexpectedOperationForBytesOperands,
            };
        } else if (left == .set and right == .set) {
            return switch (expr) {
                .equal => .{ .bool = left.set.eql(right.set) },
                .not_equal => .{ .bool = !left.set.eql(right.set) },
                .intersection => .{ .set = try left.set.intersection(right.set) },
                .@"union" => .{ .set = try left.set.@"union"(right.set) },
                .contains => .{ .bool = left.set.isSuperset(right.set) },
                else => return error.UnexpectedOperationForSetSetOperands,
            };
        } else if (left == .set) {
            return switch (expr) {
                .contains => .{ .bool = left.set.contains(right) },
                else => return error.UnexpectedOperationForSetTermOperands,
            };
        } else if (left == .bool and right == .bool) {
            const i = left.bool;
            const j = right.bool;

            return switch (expr) {
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

fn match(allocator: std.mem.Allocator, regex: []const u8, string: []const u8) !bool {
    var re = try Regex.compile(allocator, regex);

    return re.partialMatch(string);
}

fn concat(allocator: std.mem.Allocator, left: []const u8, right: []const u8) ![]const u8 {
    return try std.mem.concat(allocator, u8, &[_][]const u8{ left, right });
}

test {
    const testing = std.testing;

    const allocator = testing.allocator;

    const t1: Term = .{ .integer = 10 };
    const t2: Term = .{ .integer = 22 };

    var symbols = SymbolTable.init("test", testing.allocator);
    defer symbols.deinit();

    try testing.expectEqual(@as(Term, .{ .bool = false }), try Binary.equal.evaluate(allocator, t1, t2, &symbols));
    try testing.expectEqual(@as(Term, .{ .bool = true }), try Binary.equal.evaluate(allocator, t1, t1, &symbols));
    try testing.expectEqual(@as(Term, .{ .integer = 32 }), try Binary.add.evaluate(allocator, t1, t2, &symbols));
    try testing.expectEqual(@as(Term, .{ .integer = 220 }), try Binary.mul.evaluate(allocator, t1, t2, &symbols));

    const s = .{ .string = try symbols.insert("prefix_middle_suffix") };
    const prefix = .{ .string = try symbols.insert("prefix") };
    const suffix = .{ .string = try symbols.insert("suffix") };
    const middle = .{ .string = try symbols.insert("middle") };

    try testing.expectEqual(@as(Term, .{ .bool = true }), try Binary.equal.evaluate(allocator, s, s, &symbols));
    try testing.expectEqual(@as(Term, .{ .bool = false }), try Binary.equal.evaluate(allocator, s, prefix, &symbols));
    try testing.expectEqual(@as(Term, .{ .bool = true }), try Binary.not_equal.evaluate(allocator, s, prefix, &symbols));
    try testing.expectEqual(@as(Term, .{ .bool = true }), try Binary.prefix.evaluate(allocator, s, prefix, &symbols));
    try testing.expectEqual(@as(Term, .{ .bool = true }), try Binary.suffix.evaluate(allocator, s, suffix, &symbols));
    try testing.expectEqual(@as(Term, .{ .bool = true }), try Binary.contains.evaluate(allocator, s, middle, &symbols));
}

// test "negate" {
//     const testing = std.testing;

//     var symbols = SymbolTable.init("test", testing.allocator);
//     defer symbols.deinit();

//     _ = try symbols.insert("test1");
//     _ = try symbols.insert("test2");
//     _ = try symbols.insert("var1");
//     // var tmp_symbols = TemporarySymbolTable.init(testing.allocator, &symbols);

//     var ops = [_]Op{
//         .{ .value = .{ .integer = 1 } },
//         .{ .value = .{ .variable = 2 } },
//         .{ .binary = .less_than },
//         .{ .unary = .parens },
//         .{ .unary = .negate },
//     };

//     var values = std.AutoHashMap(u32, Term).init(testing.allocator);
//     defer values.deinit();

//     try values.put(2, .{ .integer = 0 });

//     const expr: Expression = .{ .ops = ops[0..] };

//     // FIXME: tmp_symbols
//     const res = try expr.evaluate(testing.allocator, values, symbols);

//     try testing.expectEqual(@as(Term, .{ .bool = true }), res);
// }
