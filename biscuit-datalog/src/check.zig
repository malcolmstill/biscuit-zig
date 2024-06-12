const std = @import("std");
const schema = @import("biscuit-schema");
const builder = @import("biscuit-builder");
const Rule = @import("rule.zig").Rule;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

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

    pub fn testDeinit(check: *Check) void {
        for (check.queries.items) |*query| {
            query.testDeinit();
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

    pub fn remap(check: Check, old_symbols: *const SymbolTable, new_symbols: *SymbolTable) !Check {
        var queries = try check.queries.clone();

        for (queries.items, 0..) |query, i| {
            queries.items[i] = try query.remap(old_symbols, new_symbols);
        }

        return .{
            .queries = queries,
            .kind = check.kind,
        };
    }

    /// Convert from builder to datalog
    pub fn from(check: builder.Check, allocator: std.mem.Allocator, symbols: *SymbolTable) !Check {
        var queries = std.ArrayList(Rule).init(allocator);

        for (check.queries.items) |query| {
            try queries.append(try Rule.from(query, allocator, symbols));
        }

        const kind: Check.Kind = switch (check.kind) {
            .one => .one,
            .all => .all,
        };

        return .{ .kind = kind, .queries = queries };
    }
};
