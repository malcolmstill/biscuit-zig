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

pub const Rule = struct {
    head: Predicate,
    body: std.ArrayList(Predicate),

    pub fn fromSchema(allocator: std.mem.Allocator, rule: schema.RuleV2) !Rule {
        const head = try Predicate.fromSchema(allocator, rule.head orelse return error.NoHeadInRuleSchema);

        var body = std.ArrayList(Predicate).init(allocator);
        for (rule.body.items) |predicate| {
            try body.append(try Predicate.fromSchema(allocator, predicate));
        }

        return .{ .head = head, .body = body };
    }

    pub fn deinit(rule: *Rule) void {
        rule.head.deinit();
        for (rule.body.items) |*predicate| {
            predicate.deinit();
        }
        rule.body.deinit();
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

    pub fn format(rule: Rule, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) std.os.WriteError!void {
        try writer.print("{any} <- ", .{rule.head});
        for (rule.body.items, 0..) |*predicate, i| {
            try writer.print("{any}", .{predicate.*});
            if (i < rule.body.items.len - 1) try writer.print(", ", .{});
        }
    }
};
