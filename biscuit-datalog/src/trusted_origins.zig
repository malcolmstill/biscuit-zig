const std = @import("std");
const mem = std.mem;
const Set = @import("set.zig").Set;
const Scope = @import("scope.zig").Scope;
const Origin = @import("origin.zig").Origin;

/// TrustedOrigin represents the set of origins trusted by a particular rule
pub const TrustedOrigins = struct {
    ids: InnerSet,

    const InnerSet = std.AutoHashMap(usize, void);

    pub fn init(allocator: mem.Allocator) TrustedOrigins {
        return .{ .ids = InnerSet.init(allocator) };
    }

    pub fn testDeinit(trusted_origins: *TrustedOrigins) void {
        trusted_origins.ids.deinit();
    }

    pub fn clone(trusted_origins: *const TrustedOrigins) !TrustedOrigins {
        return .{ .ids = try trusted_origins.ids.clone() };
    }

    /// Return a TrustedOrigins default of trusting the authority block (0)
    /// and the authorizer (max int).
    pub fn defaultOrigins(allocator: mem.Allocator) !TrustedOrigins {
        var trusted_origins = TrustedOrigins.init(allocator);

        try trusted_origins.insert(0);
        try trusted_origins.insert(Origin.AUTHORIZER_ID);

        return trusted_origins;
    }

    /// Given a rule (rule scopes) generate trusted origins.
    ///
    /// The trusted origins always include the current block id and the authorizer id.
    ///
    /// Additional origins depend on rule scopes. If there are no role scopes, the
    /// origins from `default_origins` are added. Otherwise we convert the role scopes
    /// to block ids and add those.
    pub fn fromScopes(
        allocator: mem.Allocator,
        rule_scopes: []const Scope,
        default_origins: TrustedOrigins,
        current_block: usize,
        public_key_to_block_id: std.AutoHashMap(usize, std.ArrayList(usize)),
    ) !TrustedOrigins {
        var trusted_origins = TrustedOrigins.init(allocator);
        try trusted_origins.insert(current_block);
        try trusted_origins.insert(Origin.AUTHORIZER_ID);

        if (rule_scopes.len == 0) {
            var it = default_origins.ids.keyIterator();

            while (it.next()) |block_id| {
                try trusted_origins.insert(block_id.*);
            }
        } else {
            for (rule_scopes) |scope| {
                switch (scope) {
                    .authority => try trusted_origins.insert(0),
                    .previous => {
                        if (current_block == Origin.AUTHORIZER_ID) continue;

                        for (0..current_block + 1) |i| {
                            try trusted_origins.insert(i);
                        }
                    },
                    .public_key => |public_key_id| {
                        const block_id_list = public_key_to_block_id.get(public_key_id) orelse continue;

                        for (block_id_list.items) |block_id| {
                            try trusted_origins.insert(block_id);
                        }
                    },
                }
            }
        }

        return trusted_origins;
    }

    // FIXME: this could have a way better name like `fn trustsFact`
    /// Check that TrustedOrigins contai (at least) _all_ origin ids in fact_origin. In
    /// other words, check that the facts origins are a subset of the trusted origins.
    pub fn containsAll(trusted_origins: *TrustedOrigins, fact_origin: *Origin) bool {
        var it = fact_origin.block_ids.keyIterator();

        while (it.next()) |origin_id_ptr| {
            const origin_id = origin_id_ptr.*;

            if (trusted_origins.ids.contains(origin_id)) continue;

            return false;
        }

        return true;
    }

    pub fn format(trusted_origins: TrustedOrigins, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        var it = trusted_origins.ids.keyIterator();

        try writer.print("trusting [", .{});
        while (it.next()) |id_ptr| {
            const id = id_ptr.*;

            if (id == Origin.AUTHORIZER_ID) {
                try writer.print("{s},", .{"Authorizer"});
            } else {
                try writer.print("{},", .{id});
            }
        }
        try writer.print("]", .{});
    }

    pub fn insert(trusted_origins: *TrustedOrigins, block_id: usize) !void {
        try trusted_origins.ids.put(block_id, {});
    }
};

test "Trusted origin" {
    const testing = std.testing;

    var to = try TrustedOrigins.defaultOrigins(testing.allocator);
    defer to.testDeinit();

    var o = Origin.init(testing.allocator);
    defer o.testDeinit();

    try o.insert(22);

    _ = to.containsAll(&o);
}
