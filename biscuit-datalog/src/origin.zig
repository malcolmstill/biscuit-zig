const std = @import("std");
const mem = std.mem;
const Set = @import("set.zig").Set;
const Scope = @import("scope.zig").Scope;

pub const Origin = struct {
    block_ids: Set(usize),

    pub fn init(allocator: mem.Allocator) Origin {
        return .{ .block_ids = Set(usize).init(allocator) };
    }

    pub fn insert(origin: *Origin, block_id: usize) void {
        origin.block_ids.add(block_id);
    }

    pub fn @"union"(origin: Origin, other: Origin) Origin {
        return .{ .block_ids = origin.block_ids.@"union"(other.block_ids) };
    }

    pub fn isSuperset(origin: Origin, other: Origin) Origin {
        return origin.block_ids.isSuperset(other.block_ids);
    }
};

/// TrustedOrigin represents the set of origins trusted by a particular rule
pub const TrustedOrigins = struct {
    origin: Origin,

    pub fn init(allocator: mem.Allocator) TrustedOrigins {
        return .{ .origin = Origin.init(allocator) };
    }

    /// Return a TrustedOrigins default of trusting the authority block (0)
    /// and the authorizer (max int).
    pub fn defaultOrigins(allocator: mem.Allocator) TrustedOrigins {
        var trusted_origins = TrustedOrigins.init(allocator);

        try trusted_origins.origin.insert(0); // Authority block?
        try trusted_origins.origin.insert(std.math.maxInt(u64));

        return trusted_origins;
    }

    /// Given a rule (rule scopes) generate
    pub fn fromScopes(
        allocator: mem.Allocator,
        rule_scopes: []const Scope,
        default_origins: TrustedOrigins,
        current_block: usize,
        public_key_to_block_id: std.AutoHashMap(usize, std.ArrayList(usize)),
    ) TrustedOrigins {
        const max_int = std.math.maxInt(usize);
        _ = public_key_to_block_id;

        if (rule_scopes.len == 0) {
            var origins = default_origins.clone();

            try origins.insert(current_block);
            try origins.insert(max_int);

            return origins;
        }

        var trusted_origins = TrustedOrigins.init(allocator);
        trusted_origins.origin.insert(max_int);
        trusted_origins.origin.insert(current_block);

        for (rule_scopes) |scope| {
            switch (scope) {
                .authority => trusted_origins.origin.insert(0),
                .previous => {
                    if (current_block == max_int) continue;

                    for (0..current_block + 1) |i| {
                        try trusted_origins.origins.insert(i);
                    }
                },
                .public_key => |public_key_id| {
                    _ = public_key_id;

                    @panic("Unimplemented");
                },
            }
        }

        return trusted_origins;
    }
};
