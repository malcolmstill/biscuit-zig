const std = @import("std");
const mem = std.mem;
const meta = std.meta;
const schema = @import("biscuit-schema");
const builder = @import("biscuit-builder");
const Set = @import("set.zig").Set;
const Fact = @import("fact.zig").Fact;
const FactSet = @import("fact_set.zig").FactSet;
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;
const Origin = @import("origin.zig").Origin;
const SymbolTable = @import("symbol_table.zig").SymbolTable;
const MatchedVariables = @import("matched_variables.zig").MatchedVariables;
const Combinator = @import("combinator.zig").Combinator;
const Scope = @import("scope.zig").Scope;
const Expression = @import("expression.zig").Expression;
const TrustedOrigins = @import("trusted_origins.zig").TrustedOrigins;

const log = std.log.scoped(.rule);

pub const Rule = struct {
    head: Predicate,
    body: std.ArrayList(Predicate),
    expressions: std.ArrayList(Expression),
    scopes: std.ArrayList(Scope),

    /// Make datalog rule from protobuf rule
    pub fn fromSchema(allocator: std.mem.Allocator, schema_rule: schema.RuleV2) !Rule {
        const head = try Predicate.fromSchema(allocator, schema_rule.head orelse return error.NoHeadInRuleSchema);

        var body = std.ArrayList(Predicate).init(allocator);
        var expressions = std.ArrayList(Expression).init(allocator);
        var scopes = std.ArrayList(Scope).init(allocator);

        for (schema_rule.body.items) |predicate| {
            try body.append(try Predicate.fromSchema(allocator, predicate));
        }

        for (schema_rule.expressions.items) |expression| {
            try expressions.append(try Expression.fromSchema(allocator, expression));
        }

        for (schema_rule.scope.items) |scope| {
            try scopes.append(try Scope.fromSchema(scope));
        }

        return .{ .head = head, .body = body, .expressions = expressions, .scopes = scopes };
    }

    pub fn deinit(_: *Rule) void {
        // rule.head.deinit();

        // for (rule.body.items) |*predicate| {
        //     predicate.deinit();
        // }

        // for (rule.expressions.items) |*expression| {
        //     expression.deinit();
        // }

        // rule.body.deinit();
        // rule.expressions.deinit();
        // rule.scopes.deinit();
    }

    /// ### Generate new facts from this rule and the existing facts
    ///
    /// We do this roughly by:
    ///
    /// 1. Generate a map from rule body variables -> initially null terms
    /// 2. Iteratively generate variable bindings from the body definition that match existing facts
    /// 3. Check that the binding defines a complete fact; add it to our set of facts if so.
    ///
    /// #### 1. Generate a map from rule body variables -> initially null terms
    ///
    /// We simply create a new MatchedVariables that builds the map from the rule's body
    ///
    /// #### 2. Iteratively generate variable bindings
    ///
    /// See Combinator for details.
    ///
    /// #### 3. Check that the binding defines a complete fact
    ///
    /// Iterate over the terms in this rule's head (having made a copy as we'll mutate it).
    /// If we have a term bound to each variable that is present in the head we have a complete
    /// fact; we add the fact to the set.
    ///
    /// For example, if we have the following rule:
    ///
    /// ```
    /// right($0, "read") <- resource($0), owner($1, $0);
    /// ```
    ///
    /// And bindings looks like:
    ///
    /// ```json
    /// {
    ///      "$0": null,
    ///      "$1": "abcd"
    /// }
    /// ```
    ///
    /// `"$0"` remains unbound and so we don't have a complete fact.
    ///
    /// Instead, if we had:
    ///
    /// ```json
    /// {
    ///      "$0": "file/1",
    ///      "$1": "abcd"
    /// }
    /// ```
    ///
    /// Then `"$0"` = "file/1" and we'd get the following fact:
    ///
    /// ```
    /// right("file/1", "read")
    /// ```
    ///
    /// ...and we add it to the set of facts (the set will take care of deduplication)
    pub fn apply(rule: *const Rule, arena: mem.Allocator, origin_id: u64, facts: *const FactSet, new_facts: *FactSet, symbols: *SymbolTable, trusted_origins: TrustedOrigins) !void {
        log.debug("\napplying rule {any} (from block {})", .{ rule, origin_id });
        const matched_variables = try MatchedVariables.init(arena, rule);

        // TODO: if body is empty stuff

        var it = Combinator.init(0, arena, matched_variables, rule.body.items, rule.expressions.items, facts, symbols, trusted_origins);
        defer it.deinit();

        blk: while (try it.next()) |*origin_bindings| {
            const origin: Origin = origin_bindings[0];
            const bindings: MatchedVariables = origin_bindings[1];

            if (!try bindings.evaluateExpressions(arena, rule.expressions.items, symbols)) continue;

            // TODO: Describe why clonedWithAllocator? More generally, describe in comment the overall
            // lifetimes / memory allocation approach during evaluation.
            var predicate = try rule.head.clone();
            // defer predicate.deinit();

            // Loop over terms in head predicate. Update all _variable_ terms with their value
            // from the binding.
            for (predicate.terms.items, 0..) |head_term, i| {
                const sym = if (head_term == .variable) head_term.variable else continue;

                const value = bindings.get(sym) orelse continue :blk;

                predicate.terms.items[i] = value;
            }

            const fact = Fact.init(predicate);

            var new_origin = try origin.clone();
            try new_origin.insert(origin_id);

            log.debug("apply: adding new fact {any} with origin {any}", .{ fact, new_origin });
            // Skip adding fact if we already have generated it. Because the
            // Set will clobber duplicate facts we'll lose a reference when
            // inserting a duplicate and then when we loop over the set to
            // deinit the facts we'll miss some. This ensures that the facts
            // can be freed purely from the Set.
            // if (new_facts.contains(new_origin, fact)) {
            //     // new_origin.deinit();
            //     continue;
            // }

            try new_facts.add(new_origin, fact);
        }
    }

    /// Given a rule (e.g. from a query), return true if we can find at least one set of variable bindings that
    /// are consistent.
    ///
    /// Note: whilst the combinator may return multiple valid matches, `findMatch` only requires a single match
    /// so stopping on the first `it.next()` that returns not-null is enough.
    pub fn findMatch(rule: *Rule, arena: mem.Allocator, facts: *const FactSet, symbols: *SymbolTable, trusted_origins: TrustedOrigins) !bool {
        log.debug("findMatch({any}, {any})", .{ rule, trusted_origins });
        // var arena = std.heap.ArenaAllocator.init(allocator);
        // defer arena.deinit();

        // const arena_allocator = arena.allocator();

        if (rule.body.items.len == 0) {
            const variables = std.AutoHashMap(u32, Term).init(arena);
            for (rule.expressions.items) |expr| {
                const result = try expr.evaluate(arena, variables, symbols);

                switch (result) {
                    .bool => |b| if (b) continue else return false,
                    else => return false,
                }
            }

            return true;
        } else {
            const matched_variables = try MatchedVariables.init(arena, rule);

            var it = Combinator.init(0, arena, matched_variables, rule.body.items, rule.expressions.items, facts, symbols, trusted_origins);
            defer it.deinit();

            while (try it.next()) |*origin_bindings| {
                const bindings: MatchedVariables = origin_bindings[1];

                if (try bindings.evaluateExpressions(arena, rule.expressions.items, symbols)) return true;
            }

            return false;
        }
    }

    pub fn checkMatchAll(rule: *Rule, arena: mem.Allocator, facts: *const FactSet, symbols: *SymbolTable, trusted_origins: TrustedOrigins) !bool {
        log.debug("checkMatchAll({any}, {any})", .{ rule, trusted_origins });
        // var arena = std.heap.ArenaAllocator.init(allocator);
        // defer arena.deinit();

        // const arena_allocator = arena.allocator();

        if (rule.body.items.len == 0) {
            const variables = std.AutoHashMap(u32, Term).init(arena);
            for (rule.expressions.items) |expr| {
                const result = try expr.evaluate(arena, variables, symbols);

                switch (result) {
                    .bool => |b| if (b) continue else return false,
                    else => return false,
                }
            }

            return true;
        } else {
            const matched_variables = try MatchedVariables.init(arena, rule);

            var it = Combinator.init(0, arena, matched_variables, rule.body.items, rule.expressions.items, facts, symbols, trusted_origins);
            defer it.deinit();

            while (try it.next()) |*origin_bindings| {
                const bindings: MatchedVariables = origin_bindings[1];

                if (try bindings.evaluateExpressions(arena, rule.expressions.items, symbols)) continue;

                return false;
            }

            return true;
        }
    }

    /// Checks there a no unbound variables in the head (i.e. every head variable must appear in the )
    pub fn validateVariables(rule: Rule) bool {
        blk: for (rule.head.terms.items) |head_term| {
            const head_variable = if (head_term == .variable) head_term.variable else continue;

            for (rule.body.items) |body_predicate| {
                for (body_predicate.terms.items) |body_term| {
                    const body_variable = if (head_term == .variable) body_term.variable else continue;

                    if (head_variable == body_variable) continue :blk;
                }
            }

            // We haven't found this loop's head variable anywhere in the body (i.e. the variable is unbound)
            return false;
        }

        return true;
    }

    pub fn format(rule: Rule, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{any} <- ", .{rule.head});
        for (rule.body.items, 0..) |*predicate, i| {
            try writer.print("{any}", .{predicate.*});
            if (i < rule.body.items.len - 1) try writer.print(", ", .{});
        }

        if (rule.expressions.items.len > 0) {
            try writer.print(", [", .{});

            for (rule.expressions.items, 0..) |*expression, i| {
                try writer.print("{any}", .{expression.*});
                if (i < rule.expressions.items.len - 1) try writer.print(", ", .{});
            }

            try writer.print("]", .{});
        }

        if (rule.scopes.items.len > 0) try writer.print(", ", .{});

        for (rule.scopes.items, 0..) |*scope, i| {
            try writer.print("{any}", .{scope.*});
            if (i < rule.scopes.items.len - 1) try writer.print(", ", .{});
        }
    }

    // Convert datalog fact from old symbol space to new symbol space
    pub fn remap(rule: Rule, old_symbols: *const SymbolTable, new_symbols: *SymbolTable) !Rule {
        var body = try rule.body.clone();
        var expressions = try rule.expressions.clone();
        var scopes = try rule.scopes.clone();

        for (body.items, 0..) |predicate, i| {
            body.items[i] = try predicate.remap(old_symbols, new_symbols);
        }

        for (expressions.items, 0..) |expression, i| {
            expressions.items[i] = try expression.remap(old_symbols, new_symbols);
        }

        for (scopes.items, 0..) |scope, i| {
            scopes.items[i] = try scope.remap(old_symbols, new_symbols);
        }

        return .{
            .head = try rule.head.remap(old_symbols, new_symbols),
            .body = body,
            .expressions = expressions,
            .scopes = scopes,
        };
    }

    /// convert to datalog predicate from builder
    pub fn from(rule: builder.Rule, allocator: std.mem.Allocator, symbols: *SymbolTable) !Rule {
        const head = try Predicate.from(rule.head, allocator, symbols);

        var body = std.ArrayList(Predicate).init(allocator);
        var expressions = std.ArrayList(Expression).init(allocator);
        var scopes = std.ArrayList(Scope).init(allocator);

        for (rule.body.items) |predicate| {
            try body.append(try Predicate.from(predicate, allocator, symbols));
        }

        for (rule.expressions.items) |expression| {
            try expressions.append(try Expression.from(expression, allocator, symbols));
        }

        for (rule.scopes.items) |scope| {
            try scopes.append(try Scope.from(scope, allocator, symbols));
        }

        return .{
            .head = head,
            .body = body,
            .expressions = expressions,
            .scopes = scopes,
        };
    }
};
