const std = @import("std");
const datalog = @import("biscuit-datalog");
const Rule = @import("rule.zig").Rule;

pub const Policy = struct {
    kind: Kind,
    queries: std.ArrayList(Rule),

    pub const Kind = enum {
        allow,
        deny,
    };

    pub fn deinit(_: Policy) void {
        // for (policy.queries.items) |query| {
        //     query.deinit();
        // }

        // policy.queries.deinit();
    }

    // pub fn toDatalog(policy: Policy, allocator: std.mem.Allocator, symbols: *datalog.SymbolTable) !Policy {
    //     var queries = std.ArrayList(Rule).init(allocator);

    //     for (policy.queries.items) |query| {
    //         try queries.append(try query.toDatalog(allocator, symbols));
    //     }

    //     return .{ .kind = policy.kind, .queries = queries };
    // }

    pub fn format(policy: Policy, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("policy ", .{});

        switch (policy.kind) {
            .allow => try writer.print("allow if", .{}),
            .deny => try writer.print("deny if", .{}),
        }

        for (policy.queries.items) |query| {
            try writer.print(" {any}", .{query});
        }
    }
};
