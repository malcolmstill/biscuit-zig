const std = @import("std");
const mem = std.mem;
const Set = @import("set.zig").Set;
const Scope = @import("scope.zig").Scope;

pub const Origin = struct {
    block_ids: std.AutoHashMap(usize, void),

    // Authorizer id is maximum int storable in u64
    pub const AuthorizerId = std.math.maxInt(u64);

    pub fn init(allocator: mem.Allocator) Origin {
        return .{ .block_ids = std.AutoHashMap(usize, void).init(allocator) };
    }

    // pub fn initWithId(allocator: mem.Allocator, block_id: usize) !Origin {
    //     var block_ids = std.AutoHashMap(usize, void).init(allocator);

    //     try block_ids.put(block_id, {});

    //     return .{ .block_ids = block_ids };
    // }

    pub fn deinit(origin: *Origin) void {
        origin.block_ids.deinit();
    }

    pub fn format(origin: Origin, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        var it = origin.block_ids.keyIterator();

        try writer.print("[", .{});
        while (it.next()) |block_id| {
            try writer.print("{}", .{block_id.*});
        }
        try writer.print("]", .{});
    }

    pub fn clone(origin: *const Origin) !Origin {
        return .{ .block_ids = try origin.block_ids.clone() };
    }

    // pub fn authorizer(allocator: mem.Allocator) !Origin {
    //     return try Origin.initWithId(allocator, AuthorizerId);
    // }

    pub fn insert(origin: *Origin, block_id: usize) !void {
        try origin.block_ids.put(block_id, {});
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
    ) !TrustedOrigins {
        _ = public_key_to_block_id;

        if (rule_scopes.len == 0) {
            var trusted_origins = try default_origins.clone();

            try trusted_origins.origin.insert(current_block);
            try trusted_origins.origin.insert(Origin.AuthorizerId);

            return trusted_origins;
        }

        var trusted_origins = TrustedOrigins.init(allocator);
        try trusted_origins.origin.insert(Origin.AuthorizerId);
        try trusted_origins.origin.insert(current_block);

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
                    _ = public_key_id;

                    @panic("Unimplemented");
                },
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
