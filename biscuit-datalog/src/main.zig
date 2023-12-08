pub const fact = @import("fact.zig");
pub const predicate = @import("predicate.zig");
pub const rule = @import("rule.zig");
pub const check = @import("check.zig");
pub const symbol_table = @import("symbol_table.zig");
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
