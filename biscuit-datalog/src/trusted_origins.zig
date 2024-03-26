const std = @import("std");
const mem = std.mem;
const Set = @import("set.zig").Set;
const Scope = @import("scope.zig").Scope;
const Origin = @import("origin.zig").Origin;

/// TrustedOrigin represents the set of origins trusted by a particular rule
pub const TrustedOrigins = struct {
    origin: Origin,

    pub fn init(allocator: mem.Allocator) TrustedOrigins {
        return .{ .origin = Origin.init(allocator) };
    }

    pub fn deinit(trusted_origins: *TrustedOrigins) void {
        trusted_origins.origin.block_ids.deinit();
    }

    pub fn clone(trusted_origins: *const TrustedOrigins) !TrustedOrigins {
        return .{ .origin = try trusted_origins.origin.clone() };
    }

    /// Return a TrustedOrigins default of trusting the authority block (0)
    /// and the authorizer (max int).
    pub fn defaultOrigins(allocator: mem.Allocator) !TrustedOrigins {
        var trusted_origins = TrustedOrigins.init(allocator);

        try trusted_origins.origin.insert(0);
        try trusted_origins.origin.insert(Origin.AuthorizerId);

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
        try trusted_origins.origin.insert(current_block);
        try trusted_origins.origin.insert(Origin.AuthorizerId);

        if (rule_scopes.len == 0) {
            var it = default_origins.origin.block_ids.keyIterator();

            while (it.next()) |block_id| {
                try trusted_origins.origin.insert(block_id.*);
            }
        } else {
            for (rule_scopes) |scope| {
                switch (scope) {
                    .authority => try trusted_origins.origin.insert(0),
                    .previous => {
                        if (current_block == Origin.AuthorizerId) continue;

                        for (0..current_block + 1) |i| {
                            try trusted_origins.origin.insert(i);
                        }
                    },
                    .public_key => |public_key_id| {
                        const block_id_list = public_key_to_block_id.get(public_key_id) orelse continue;

                        for (block_id_list.items) |block_id| {
                            try trusted_origins.origin.insert(block_id);
                        }
                    },
                }
            }
        }

        return trusted_origins;
    }

    /// Check that TrustedOrigins contain _all_ origin ids in fact_origin
    pub fn containsAll(trusted_origins: TrustedOrigins, fact_origin: Origin) bool {
        var origin_it = fact_origin.block_ids.keyIterator();

        while (origin_it.next()) |origin_id| {
            if (trusted_origins.origin.block_ids.contains(origin_id.*)) continue;

            return false;
        }

        return true;
    }
};
