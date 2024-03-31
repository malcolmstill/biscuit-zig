const std = @import("std");
const meta = std.meta;
const mem = std.mem;
const Fact = @import("fact.zig").Fact;
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;
const FactSet = @import("fact_set.zig").FactSet;
const Origin = @import("origin.zig").Origin;
const TrustedOrigins = @import("trusted_origins.zig").TrustedOrigins;
const Expression = @import("expression.zig").Expression;
const MatchedVariables = @import("matched_variables.zig").MatchedVariables;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

const log = std.log.scoped(.combinator);

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
    id: usize,
    allocator: mem.Allocator,
    variables: MatchedVariables,
    next_combinator: ?*Combinator, // Current combinator for the next predicate
    predicates: []Predicate, // List of the predicates so we can generate new Combinators
    expressions: []Expression,
    current_bindings: ?std.AutoHashMap(u64, Term) = null,
    facts: *const FactSet,
    trusted_fact_iterator: FactSet.TrustedIterator,
    symbols: *SymbolTable,
    trusted_origins: TrustedOrigins,

    pub fn init(id: usize, allocator: mem.Allocator, variables: MatchedVariables, predicates: []Predicate, expressions: []Expression, all_facts: *const FactSet, symbols: *SymbolTable, trusted_origins: TrustedOrigins) Combinator {
        return .{
            .id = id,
            .allocator = allocator,
            .next_combinator = null,
            .facts = all_facts,
            .predicates = predicates,
            .expressions = expressions,
            .variables = variables,
            .symbols = symbols,
            .trusted_fact_iterator = all_facts.trustedIterator(trusted_origins),
            .trusted_origins = trusted_origins,
        };
    }

    pub fn deinit(combinator: *Combinator) void {
        combinator.variables.deinit();
        // combinator.allocator.destroy(combinator);
    }

    // QUESTION: is the return value guaranteed to be complete? I.e. each variable has been matched with some non-variable term?
    /// next returns the next _valid_ combination of variable bindings
    pub fn next(combinator: *Combinator) !?struct { Origin, MatchedVariables } {
        blk: while (true) {
            // Return from next combinator until expended
            if (combinator.next_combinator) |c| {
                if (try c.next()) |origin_vars| {
                    return origin_vars;
                } else {
                    // Deinit the existing combinator and free its memory
                    c.deinit();
                    combinator.allocator.destroy(c);
                    combinator.next_combinator = null;
                    continue;
                }
            }

            // Lookup the next (trusted) fact
            const origin_fact = combinator.trusted_fact_iterator.next() orelse return null;

            log.debug("[{}] next trusted fact: {any}", .{ combinator.id, origin_fact.fact });

            const origin = origin_fact.origin.*;
            const fact = origin_fact.fact.*;

            // Only consider facts that match the current predicate
            if (!fact.matchPredicate(combinator.predicates[0])) continue;

            var vars: MatchedVariables = try combinator.variables.clone();

            // Set variables from predicate to match values
            for (combinator.predicates[0].terms.items, 0..) |term, i| {
                const sym = if (term == .variable) term.variable else continue;

                // Since we are pulling terms out of a fact, we know
                // ahead of time that none of the terms will be variables.
                const fact_term = fact.predicate.terms.items[i];
                std.debug.assert(fact_term != .variable);

                if (!(try vars.insert(sym, fact_term))) {
                    // We have already bound this variable to a different
                    // term, the current fact does work with previous
                    // predicates and we move onto the next fact.
                    continue :blk;
                }
            }

            const next_predicates = combinator.predicates[1..];

            if (next_predicates.len == 0) {
                return .{ origin, vars };
            } else {
                std.debug.assert(combinator.next_combinator == null);
                if (combinator.next_combinator) |c| c.deinit();

                const combinator_ptr = try combinator.allocator.create(Combinator);

                combinator_ptr.* = Combinator.init(
                    combinator.id + 1,
                    combinator.allocator,
                    vars,
                    next_predicates,
                    combinator.expressions,
                    combinator.facts,
                    combinator.symbols,
                    combinator.trusted_origins,
                );

                combinator.next_combinator = combinator_ptr;
            }
        }

        return null;
    }
};
