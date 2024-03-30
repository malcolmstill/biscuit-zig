const std = @import("std");
const datalog = @import("biscuit-datalog");
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;
const Rule = @import("rule.zig").Rule;

pub const Check = struct {
    kind: datalog.Check.Kind,
    queries: std.ArrayList(Rule),

    pub fn deinit(_: Check) void {
        // for (check.queries.items) |query| {
        //     query.deinit();
        // }

        // check.queries.deinit();
    }

    pub fn toDatalog(check: Check, allocator: std.mem.Allocator, symbols: *datalog.SymbolTable) !datalog.Check {
        var queries = std.ArrayList(datalog.Rule).init(allocator);

        for (check.queries.items) |query| {
            try queries.append(try query.toDatalog(allocator, symbols));
        }

        return .{ .kind = check.kind, .queries = queries };
    }

    pub fn format(check: Check, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("check ", .{});

        switch (check.kind) {
            .one => try writer.print("if", .{}),
            .all => try writer.print("all", .{}),
        }

        for (check.queries.items) |query| {
            try writer.print(" {any}", .{query});
        }
    }
};
