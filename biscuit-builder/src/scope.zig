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

pub const Scope = struct {
    kind: ScopeKind,
    public_key: Ed25519.PublicKey,

    /// convert to datalog fact
    pub fn convert(_: Scope, _: std.mem.Allocator, _: *datalog.SymbolTable) !datalog.Scope {
        unreachable;
    }
};
