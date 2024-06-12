const std = @import("std");
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;
const Rule = @import("rule.zig").Rule;

pub const Check = struct {
    kind: Kind,
    queries: std.ArrayList(Rule),

    pub const Kind = enum {
        one,
        all,
    };

    pub fn deinit(_: Check) void {
        // for (check.queries.items) |query| {
        //     query.deinit();
        // }

        // check.queries.deinit();
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
