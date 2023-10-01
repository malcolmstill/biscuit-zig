const std = @import("std");
const mem = std.mem;
const Fact = @import("fact.zig").Fact;
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;
const Set = @import("set.zig").Set;
const MatchedVariables = @import("matched_variables.zig").MatchedVariables;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

/// Combinator generates a stream of variable -> term binding maps
/// based upon:
/// - All of the existing facts
/// - The predicates in the body of the current rule
pub const Combinator = struct {
    allocator: mem.Allocator,
    current_bindings: ?std.AutoHashMap(u64, Term) = null,

    pub fn init(allocator: mem.Allocator, variables: MatchedVariables, rule_body: std.ArrayList(Predicate), all_facts: *const Set(Fact), symbols: SymbolTable) Combinator {
        _ = symbols;
        _ = all_facts;
        _ = rule_body;
        _ = variables;
        return .{ .allocator = allocator };
    }

    pub fn next(self: *Combinator) ?std.AutoHashMap(u64, Term) {
        if (self.current_bindings) |*current_bindings| {
            current_bindings.deinit();
        }

        return null;
    }
};
