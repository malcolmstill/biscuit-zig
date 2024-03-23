const std = @import("std");
const schema = @import("biscuit-schema");
const Rule = @import("rule.zig").Rule;

pub const Check = struct {
    queries: std.ArrayList(Rule),
    kind: Kind,

    pub const Kind = enum(u8) { one, all };

    pub fn fromSchema(allocator: std.mem.Allocator, schema_check: schema.CheckV2) !Check {
        var rules = std.ArrayList(Rule).init(allocator);
        for (schema_check.queries.items) |query| {
            try rules.append(try Rule.fromSchema(allocator, query));
        }

        const kind: Kind = if (schema_check.kind) |kind| switch (kind) {
            .One => .one,
            .All => .all,
            else => return error.CheckUnknownKind,
        } else .one;

        return .{ .queries = rules, .kind = kind };
    }

    pub fn deinit(check: *Check) void {
        for (check.queries.items) |*query| {
            query.deinit();
        }

        check.queries.deinit();
    }

    pub fn format(check: Check, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("check if ", .{});
        for (check.queries.items, 0..) |*query, i| {
            try writer.print("{any}", .{query.*});
            if (i < check.queries.items.len - 1) try writer.print(", ", .{});
        }
        return writer.print("", .{});
    }
};
