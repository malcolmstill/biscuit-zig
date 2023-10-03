const std = @import("std");
const meta = std.meta;
const mem = std.mem;
const Fact = @import("fact.zig").Fact;
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;
const Set = @import("set.zig").Set;
const MatchedVariables = @import("matched_variables.zig").MatchedVariables;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

/// Combinator is an iterator that will generate MatchedVariables from
/// the body of a rule.
///
/// What we'll end up with is actually a series of Combinators chained
/// together. Let's look at an example rule to set the scene.
///
/// ```
/// right($0, "read") <- resource($0), owner($1, $0);
/// ```
///
/// The rule body is then:
///
/// ```
/// resource($0), owner($1, $0)
/// ```
///
/// i.e. we have two predicates.
///
/// We want to try all the matching facts in both predicates. Basically
/// we want to a nested loop looking like:
///
/// ```
/// for (matchedFacts(resource)) |resource_fact| {
///     for (matchedFacts(owner)) |owner_fact| {
///         return matchedVariables(resource_fact + owner_fact)
///     }
/// }
/// ```
///
/// But of course, we can't do this loop statically (we don't know
/// the rule body at compile time), and so instead we arrange to
/// have a series of nested Combinators (iterators). At any given moment
/// in the calculation we'll have one Combinator for each predicate, but
/// we'll create a new Combinator when the Combinator to our left iterates
/// to its next fact.
///
/// For the left-most predicate, we'll only allocate a single Combinator.
/// For each matched fact for that predicate, we'll create a fresh Combinator
/// for the next predicate, and so forth.
pub const Combinator = struct {
    allocator: mem.Allocator,
    variables: MatchedVariables,
    next_combinator: ?*Combinator, // Current combinator for the next predicate
    predicates: []Predicate, // List of the predicates so we can generate new Combinators
    current_bindings: ?std.AutoHashMap(u64, Term) = null,
    facts: *const Set(Fact),

    pub fn init(allocator: mem.Allocator, variables: MatchedVariables, rule_body: []Predicate, all_facts: *const Set(Fact), symbols: SymbolTable) Combinator {
        _ = symbols;

        return .{
            .allocator = allocator,
            .next_combinator = null,
            .facts = all_facts,
            .predicates = rule_body,
            .variables = variables,
        };
    }

    pub fn next(self: *Combinator) !?std.AutoHashMap(u64, Term) {
        blk: while (true) {
            if (self.current_bindings) |*current_bindings| {
                current_bindings.deinit();
            }

            if (self.next_combinator) |next_combinator| {
                _ = next_combinator;
                // todo
            }

            // FIXME: var it = self.facts.matchedIterator(self.predicates[0]); ?
            var it = self.facts.iterator();
            while (it.next()) |fact| {
                // Only consider facts that match the current predicate
                if (!fact.matchPredicate(self.predicates[0])) continue;

                // FIXME: clone variables?

                // Set variables from predicate to match values
                for (self.predicates[0].terms.items, 0..) |term, i| {
                    const id = if (meta.activeTag(term) == .variable) term.variable else continue;

                    // Since we are pulling terms out of a fact, we know
                    // ahead of time that none of the terms will be variables.
                    const fact_term = fact.predicate.terms.items[i];
                    if (!(try self.variables.insert(id, fact_term))) {
                        // We have already bound this variable to a different
                        // term, the current fact does work with previous
                        // predicates and we move onto the next fact.
                        continue :blk;
                    }
                }
            }

            return null;
        }
    }
};
