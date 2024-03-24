const std = @import("std");
const mem = std.mem;
const Rule = @import("rule.zig").Rule;
const Term = @import("term.zig").Term;

// Is a better name for this VariableBinding?

/// MatchedVariables provides a map from variable -> (initially null) terms
/// for all the variables in the rule body.
///
/// For example, if we have the following rule:
///
/// ```
/// right($0, "read") <- resource($0), owner($1, $0);
/// ```
///
/// Our body is:
///
/// ```
/// resource($0), owner($1, $0)
/// ```
///
/// Our matched variables will initially look like (rendered as JSON):
///
/// ```json
/// {
///     "$0": null,
///     "$1": null
/// }
/// ```
pub const MatchedVariables = struct {
    variables: std.AutoHashMap(u32, ?Term),

    pub fn init(allocator: mem.Allocator, rule: *Rule) !MatchedVariables {
        var variables = std.AutoHashMap(u32, ?Term).init(allocator);

        // Add all variables in predicates in the rule's body to variable set
        for (rule.body.items) |predicate| {
            for (predicate.terms.items) |term| {
                switch (term) {
                    .variable => |v| try variables.put(v, null), // Should we check the key doesn't exist?
                    else => continue,
                }
            }
        }

        return .{ .variables = variables };
    }

    pub fn deinit(matched_variables: *MatchedVariables) void {
        matched_variables.variables.deinit();
    }

    pub fn clone(matched_variables: *const MatchedVariables) !MatchedVariables {
        const variables = try matched_variables.variables.clone();
        return .{ .variables = variables };
    }

    pub fn get(matched_variables: *const MatchedVariables, key: u32) ?Term {
        return matched_variables.variables.get(key) orelse return null;
    }

    /// Attempt to bind a variable to a term. If we have already bound
    /// the variable, we return true only if the existing and new term
    /// match.
    ///
    /// If the variable is unset we bind to the term unconditionally and
    /// return true.
    pub fn insert(matched_variables: *MatchedVariables, variable: u32, term: Term) !bool {
        const entry = matched_variables.variables.getEntry(variable) orelse return false;

        if (entry.value_ptr.*) |existing_term| {
            // The variable is already set to an existing term.
            // We don't reinsert but we check that the new term
            // is equal to the existing term
            return term.eql(existing_term); // FIXME: we need need to implement equal (or eql)
        } else {
            // The variable is unset. Bind term to the variable
            // and return true.
            try matched_variables.variables.put(variable, term);
            return true;
        }
    }

    /// Are all the variables in our map bound?
    pub fn isComplete(matched_variables: *const MatchedVariables) bool {
        var it = matched_variables.variables.valueIterator();
        while (it.next()) |term| {
            if (term.* == null) return false;
        }

        return true;
    }

    /// If every variable in MatchedVariables has been assigned a term return a map
    /// from variable -> non-null term, otherwise return null.
    pub fn complete(matched_variables: *const MatchedVariables, allocator: mem.Allocator) !?std.AutoHashMap(u32, Term) {
        if (!matched_variables.isComplete()) return null;

        var completed_variables = std.AutoHashMap(u32, Term).init(allocator);
        errdefer completed_variables.deinit();

        var it = matched_variables.variables.iterator();
        while (it.next()) |kv| {
            const key: u32 = kv.key_ptr.*;
            const value: ?Term = kv.value_ptr.*;

            try completed_variables.put(key, value.?);
        }

        return completed_variables;
    }
};
