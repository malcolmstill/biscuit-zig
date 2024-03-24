const std = @import("std");
const datalog = @import("biscuit-datalog");
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;

const ExpressionType = enum(u8) {
    value,
    unary,
    binary,
};

pub const Expression = union(ExpressionType) {
    value: Term,
    unary: Unary,
    binary: Binary,

    const Unary = struct {
        op: UnaryOp,
        expression: *Expression,
    };

    const Binary = struct {
        op: BinaryOp,
        left: *Expression,
        right: *Expression,
    };

    pub const UnaryOp = enum {
        negate,
        parens,
        length,
    };

    pub const BinaryOp = enum {
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
    };

    /// convert to datalog fact
    pub fn convert(_: Expression, _: std.mem.Allocator, _: *datalog.SymbolTable) !datalog.Expression {
        unreachable;
    }

    pub fn deinit(expression: *Expression) void {
        switch (expression.*) {
            .value => |v| v.deinit(),
            .unary => |u| u.expression.deinit(),
            .binary => |b| {
                b.left.deinit();
                b.right.deinit();
            },
        }
    }

    pub fn initValue(allocator: std.mem.Allocator, term: Term) !*Expression {
        const e = try allocator.create(Expression);

        e.* = .{ .value = term };

        return e;
    }

    pub fn initUnary(allocator: std.mem.Allocator, op: UnaryOp, expr: *Expression) !*Expression {
        const e = try allocator.create(Expression);

        e.* = .{ .unary = .{ .op = op, .expression = expr } };

        return e;
    }

    pub fn initBinary(allocator: std.mem.Allocator, op: BinaryOp, left: *Expression, right: *Expression) !*Expression {
        const e = try allocator.create(Expression);

        e.* = .{ .binary = .{ .op = op, .left = left, .right = right } };

        return e;
    }

    pub fn format(expression: Expression, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (expression) {
            .value => |v| try writer.print("{any}", .{v}),
            .unary => |u| {
                switch (u.op) {
                    .negate => try writer.print("-{any}", .{u.expression}),
                    .parens => try writer.print("({any})", .{u.expression}),
                    .length => try writer.print("{any}.length()", .{u.expression}),
                }
            },
            .binary => |b| {
                switch (b.op) {
                    .less_than => try writer.print("{any} < {any}", .{ b.left, b.right }),
                    .greater_than => try writer.print("{any} > {any}", .{ b.left, b.right }),
                    .less_or_equal => try writer.print("{any} <= {any}", .{ b.left, b.right }),
                    .greater_or_equal => try writer.print("{any} >= {any}", .{ b.left, b.right }),
                    .equal => try writer.print("{any} == {any}", .{ b.left, b.right }),
                    .contains => try writer.print("{any}.contains({any})", .{ b.left, b.right }),
                    .prefix => try writer.print("{any}.starts_with({any})", .{ b.left, b.right }),
                    .suffix => try writer.print("{any}.ends_with({any})", .{ b.left, b.right }),
                    .regex => try writer.print("{any}.matches({any})", .{ b.left, b.right }),
                    .add => try writer.print("{any} + {any}", .{ b.left, b.right }),
                    .sub => try writer.print("{any} - {any}", .{ b.left, b.right }),
                    .mul => try writer.print("{any} * {any}", .{ b.left, b.right }),
                    .div => try writer.print("{any} / {any}", .{ b.left, b.right }),
                    .@"and" => try writer.print("{any} && {any}", .{ b.left, b.right }),
                    .@"or" => try writer.print("{any} || {any}", .{ b.left, b.right }),
                    .intersection => try writer.print("{any}.intersection({any})", .{ b.left, b.right }),
                    .@"union" => try writer.print("{any}.union({any})", .{ b.left, b.right }),
                    .bitwise_and => try writer.print("{any} & {any}", .{ b.left, b.right }),
                    .bitwise_or => try writer.print("{any} | {any}", .{ b.left, b.right }),
                    .bitwise_xor => try writer.print("{any} ^ {any}", .{ b.left, b.right }),
                    .not_equal => try writer.print("{any} != {any}", .{ b.left, b.right }),
                }
            },
        }
    }
};
