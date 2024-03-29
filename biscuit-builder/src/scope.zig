const std = @import("std");
const datalog = @import("biscuit-datalog");
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;

const Ed25519 = std.crypto.sign.Ed25519;

const ScopeKind = enum(u8) {
    authority,
    previous,
    public_key,
    parameter,
};

pub const Scope = union(ScopeKind) {
    authority: void,
    previous: void,
    public_key: Ed25519.PublicKey,
    parameter: []const u8,

    /// convert to datalog fact
    pub fn convert(scope: Scope, _: std.mem.Allocator, symbols: *datalog.SymbolTable) !datalog.Scope {
        return switch (scope) {
            .authority => .{ .authority = {} },
            .previous => .{ .previous = {} },
            .public_key => |pk| .{ .public_key = try symbols.insertPublicKey(pk) },
            .parameter => unreachable,
        };
    }
};
