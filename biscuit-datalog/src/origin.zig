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

// TrustedOrigin represents the set of origins trusted by a particular rule
pub const TrustedOrigins = struct {
    origin: Origin,

    pub fn init(allocator: mem.Allocator) TrustedOrigins {
        return .{ .origin = Origin.init(allocator) };
    }

    pub fn initFromScopes(
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

            origins.insert(current_block);
            origins.insert(max_int);

            return origins;
        }

        var origins = Origin.init(allocator);
        origins.insert(max_int);
        origins.insert(current_block);

        for (rule_scopes) |scope| {
            switch (scope) {
                .authority => origins.insert(0),
                .previous => {
                    if (current_block == max_int) continue;
                    // TODO: extend
                },
                .public_key => |public_key_id| {
                    _ = public_key_id;
                    // TODO: extend
                },
            }
        }

        return .{ .origin = origins };
    }
};
