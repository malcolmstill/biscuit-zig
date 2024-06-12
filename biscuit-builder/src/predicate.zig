const std = @import("std");
const Term = @import("term.zig").Term;

pub const Predicate = struct {
    name: []const u8,
    terms: std.ArrayList(Term),

    pub fn deinit(_: Predicate) void {
        // for (predicate.terms.items) |term| {
        //     term.deinit();
        // }

        // predicate.terms.deinit();
    }

    pub fn format(predicate: Predicate, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}(", .{predicate.name});
        for (predicate.terms.items, 0..) |*term, i| {
            try writer.print("{any}", .{term.*});
            if (i < predicate.terms.items.len - 1) try writer.print(", ", .{});
        }
        return writer.print(")", .{});
    }
};
