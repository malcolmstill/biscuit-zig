const std = @import("std");
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
        allocator: std.mem.Allocator,
    };

    const Binary = struct {
        op: BinaryOp,
        left: *Expression,
        right: *Expression,
        allocator: std.mem.Allocator,
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

    pub fn deinit(_: *Expression) void {
        // switch (expression.*) {
        //     .value => |v| v.deinit(),
        //     .unary => |*u| {
        //         u.expression.deinit();

        //         u.allocator.destroy(u.expression);
        //     },
        //     .binary => |*b| {
        //         b.left.deinit();
        //         b.right.deinit();

        //         b.allocator.destroy(b.left);
        //         b.allocator.destroy(b.right);
        //     },
        // }
    }

    pub fn value(term: Term) !Expression {
        return .{ .value = term };
    }

    pub fn unary(allocator: std.mem.Allocator, op: UnaryOp, expr: Expression) !Expression {
        const expr_ptr = try allocator.create(Expression);

        expr_ptr.* = expr;

        return .{ .unary = .{ .op = op, .expression = expr_ptr, .allocator = allocator } };
    }

    pub fn binary(allocator: std.mem.Allocator, op: BinaryOp, left: Expression, right: Expression) !Expression {
        const left_ptr = try allocator.create(Expression);
        errdefer allocator.destroy(left_ptr);
        const right_ptr = try allocator.create(Expression);

        left_ptr.* = left;
        right_ptr.* = right;

        return .{ .binary = .{ .op = op, .left = left_ptr, .right = right_ptr, .allocator = allocator } };
    }

    pub fn format(expression: Expression, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (expression) {
            .value => |v| try writer.print("{any}", .{v}),
            .unary => |u| {
                switch (u.op) {
                    .negate => try writer.print("!{any}", .{u.expression}),
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
