pub const fact = @import("fact.zig");
pub const Fact = @import("fact.zig").Fact;
pub const predicate = @import("predicate.zig");
pub const Predicate = @import("predicate.zig").Predicate;
pub const Expression = @import("expression.zig").Expression;
pub const Scope = @import("scope.zig").Scope;
pub const rule = @import("rule.zig");
pub const Rule = @import("rule.zig").Rule;
pub const check = @import("check.zig");
pub const symbol_table = @import("symbol_table.zig");
pub const SymbolTable = @import("symbol_table.zig").SymbolTable;
pub const Term = @import("term.zig").Term;
pub const Check = @import("check.zig").Check;
pub const Origin = @import("origin.zig").Origin;
pub const TrustedOrigins = @import("trusted_origins.zig").TrustedOrigins;
pub const world = @import("world.zig");

test {
    _ = @import("check.zig");
    _ = @import("combinator.zig");
    _ = @import("expression.zig");
    _ = @import("fact.zig");
    _ = @import("matched_variables.zig");
    _ = @import("predicate.zig");
    _ = @import("rule.zig");
    _ = @import("run_limits.zig");
    _ = @import("set.zig");
    _ = @import("symbol_table.zig");
    _ = @import("term.zig");
    _ = @import("world.zig");
}
