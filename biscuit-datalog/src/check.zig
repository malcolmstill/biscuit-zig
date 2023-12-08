const std = @import("std");
const schema = @import("biscuit-schema");
const Rule = @import("rule.zig").Rule;

pub const Check = struct {
    queries: std.ArrayList(Rule),

    pub fn fromSchema(allocator: std.mem.Allocator, schema_check: schema.CheckV2) !Check {
        var rules = std.ArrayList(Rule).init(allocator);
        for (schema_check.queries.items) |query| {
            try rules.append(try Rule.fromSchema(allocator, query));
        }

        return .{ .queries = rules };
    }

    pub fn deinit(check: *Check) void {
        for (check.queries.items) |*query| {
            query.deinit();
        }
        check.queries.deinit();
    }

    pub fn format(check: Check, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) std.os.WriteError!void {
        try writer.print("check if ", .{});
        for (check.queries.items, 0..) |*query, i| {
            try writer.print("{any}", .{query.*});
            if (i < check.queries.items.len - 1) try writer.print(", ", .{});
        }
        return writer.print("", .{});
    }
};
