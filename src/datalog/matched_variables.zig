const std = @import("std");
const mem = std.mem;
const Rule = @import("rule.zig").Rule;
const Term = @import("term.zig").Term;

pub const MatchedVariables = struct {
    variables: std.AutoHashMap(u64, ?Term),

    pub fn init(allocator: mem.Allocator, self: *Rule) !MatchedVariables {
        var variables = std.AutoHashMap(u64, ?Term).init(allocator);

        // Add all variables in predicates in the rule's body to variable set
        for (self.body.items) |predicate| {
            for (predicate.terms.items) |term| {
                switch (term) {
                    .variable => |v| try variables.put(v, null), // Should we check the key doesn't exist?
                    else => continue,
                }
            }
        }

        return .{ .variables = variables };
    }

    pub fn deinit(self: *MatchedVariables) void {
        self.variables.deinit();
    }

    /// Attempt to bind a variable to a term. If we have already bound
    /// the variable, we return true only if the existing and new term
    /// match.
    ///
    /// If the variable is unset we bind to the term unconditionally and
    /// return true.
    pub fn insert(self: *MatchedVariables, variable: u64, term: Term) !bool {
        var entry = self.variables.getEntry(variable) orelse return false;

        if (entry.value_ptr.*) |existing_term| {
            // The variable is already set to an existing term.
            // We don't reinsert but we check that the new term
            // is equal to the existing term
            return term.equal(existing_term);
        } else {
            // The variable is unset. Bind term to the variable
            // and return true.
            try self.variables.put(variable, term);
            return true;
        }
    }
};