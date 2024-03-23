const std = @import("std");
const mem = std.mem;
const meta = std.meta;
const schema = @import("biscuit-schema");
const Set = @import("set.zig").Set;
const Fact = @import("fact.zig").Fact;
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;
const SymbolTable = @import("symbol_table.zig").SymbolTable;
const MatchedVariables = @import("matched_variables.zig").MatchedVariables;
const Combinator = @import("combinator.zig").Combinator;
const Scope = @import("scope.zig").Scope;
const Expression = @import("expression.zig").Expression;

pub const Rule = struct {
    head: Predicate,
    body: std.ArrayList(Predicate),
    expressions: std.ArrayList(Expression),
    scopes: std.ArrayList(Scope),

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

    pub fn deinit(rule: *Rule) void {
        rule.head.deinit();

        for (rule.body.items) |*predicate| {
            predicate.deinit();
        }

        for (rule.expressions.items) |*expression| {
            expression.deinit();
        }

        rule.body.deinit();
        rule.expressions.deinit();
        rule.scopes.deinit();
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
    pub fn apply(rule: *Rule, allocator: mem.Allocator, facts: *const Set(Fact), new_facts: *Set(Fact), symbols: SymbolTable) !void {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        std.debug.print("\n\nrule = {any}\n", .{rule});
        const matched_variables = try MatchedVariables.init(arena.allocator(), rule);

        // TODO: if body is empty stuff

        var it = try Combinator.init(0, allocator, matched_variables, rule.body.items, facts, symbols);
        defer it.deinit();

        blk: while (try it.next()) |*bindings| {
            // TODO: Describe why clonedWithAllocator? More generally, describe in comment the overall
            // lifetimes / memory allocation approach during evaluation.
            var predicate = try rule.head.cloneWithAllocator(allocator);
            defer predicate.deinit();

            for (predicate.terms.items, 0..) |head_term, i| {
                const sym = if (head_term == .variable) head_term.variable else continue;

                const value = bindings.get(sym) orelse continue :blk;

                predicate.terms.items[i] = value;
            }

            const fact = Fact.init(predicate);
            std.debug.print("adding new fact = {any}\n", .{fact});

            // Skip adding fact if we already have generated it. Because the
            // Set will clobber duplicate facts we'll lose a reference when
            // inserting a duplicate and then when we loop over the set to
            // deinit the facts we'll miss some. This ensures that the facts
            // can be freed purely from the Set.
            if (new_facts.contains(fact)) continue;

            try new_facts.add(try fact.clone());
        }
    }

    /// Given a rule (e.g. from a query), return true if we can find at least one set of variable bindings that
    /// are consistent.
    ///
    /// Note: whilst the combinator may return multiple valid matches, `findMatch` only requires a single match
    /// so stopping on the first `it.next()` that returns not-null is enough.
    pub fn findMatch(rule: *Rule, allocator: mem.Allocator, facts: *const Set(Fact), symbols: SymbolTable) !bool {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const matched_variables = try MatchedVariables.init(arena.allocator(), rule);

        var it = try Combinator.init(0, allocator, matched_variables, rule.body.items, facts, symbols);
        defer it.deinit();

        return try it.next() != null;
    }

    pub fn format(rule: Rule, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{any} <- ", .{rule.head});
        for (rule.body.items, 0..) |*predicate, i| {
            try writer.print("{any}", .{predicate.*});
            if (i < rule.body.items.len - 1) try writer.print(", ", .{});
        }
    }

    // Convert datalog fact from old symbol space to new symbol space
    pub fn convert(rule: Rule, old_symbols: *const SymbolTable, new_symbols: *SymbolTable) !Rule {
        var body = try rule.body.clone();
        var expressions = try rule.expressions.clone();
        var scopes = try rule.scopes.clone();

        for (body.items, 0..) |predicate, i| {
            body.items[i] = try predicate.convert(old_symbols, new_symbols);
        }

        for (expressions.items, 0..) |expression, i| {
            expressions.items[i] = try expression.convert(old_symbols, new_symbols);
        }

        for (scopes.items, 0..) |scope, i| {
            scopes.items[i] = try scope.convert(old_symbols, new_symbols);
        }

        return .{
            .head = try rule.head.convert(old_symbols, new_symbols),
            .body = body,
            .expressions = expressions,
            .scopes = scopes,
        };
    }
};
