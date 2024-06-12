const std = @import("std");
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;

pub const Fact = struct {
    predicate: Predicate,
    variables: ?std.StringHashMap(?Term),

    pub fn deinit(_: Fact) void {
        // fact.predicate.deinit();
    }

    pub fn format(fact: Fact, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        return writer.print("{any}", .{fact.predicate});
    }
};
