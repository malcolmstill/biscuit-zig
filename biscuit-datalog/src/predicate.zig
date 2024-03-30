const std = @import("std");
const mem = std.mem;
const schema = @import("biscuit-schema");
const Term = @import("term.zig").Term;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

pub const Predicate = struct {
    name: u64,
    terms: std.ArrayList(Term),

    pub fn fromSchema(allocator: mem.Allocator, schema_predicate: schema.PredicateV2) !Predicate {
        var terms = std.ArrayList(Term).init(allocator);
        for (schema_predicate.terms.items) |term| {
            try terms.append(try Term.fromSchema(allocator, term));
        }

        return .{ .name = schema_predicate.name, .terms = terms };
    }

    pub fn format(predicate: Predicate, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("sym:{any}(", .{predicate.name});
        for (predicate.terms.items, 0..) |*term, i| {
            try writer.print("{any}", .{term.*});
            if (i < predicate.terms.items.len - 1) try writer.print(", ", .{});
        }
        return writer.print(")", .{});
    }

    pub fn deinit(predicate: *Predicate) void {
        for (predicate.terms.items) |*term| {
            term.deinit();
        }
        predicate.terms.deinit();
    }

    pub fn eql(predicate: Predicate, other_predicate: Predicate) bool {
        if (predicate.name != other_predicate.name) return false;
        if (predicate.terms.items.len != other_predicate.terms.items.len) return false;

        for (predicate.terms.items, other_predicate.terms.items) |term_a, term_b| {
            if (!term_a.eql(term_b)) return false;
        }

        return true;
    }

    /// Check if two predicates match
    ///
    /// The predicates must have the same name and each term in the
    /// predicates must match.
    ///
    /// Note: whilst "match" is very close to equality, it's not
    /// exactly equality, because variable terms can match any
    /// other term. See also the definition of `fn match` in
    /// `term.zig`.
    pub fn match(predicate: Predicate, other_predicate: Predicate) bool {
        if (predicate.name != other_predicate.name) return false;
        if (predicate.terms.items.len != other_predicate.terms.items.len) return false;

        for (predicate.terms.items, other_predicate.terms.items) |term_a, term_b| {
            if (!term_a.match(term_b)) return false;
        }

        return true;
    }

    /// Convert predicate to new symbol space
    ///
    /// Equivalent to clone but with the symbol rewriting
    pub fn remap(predicate: Predicate, old_symbols: *const SymbolTable, new_symbols: *SymbolTable) !Predicate {
        const name = try old_symbols.getString(predicate.name);

        var terms = try predicate.terms.clone();
        for (terms.items, 0..) |term, i| {
            terms.items[i] = try term.remap(old_symbols, new_symbols);
        }

        return .{
            .name = try new_symbols.insert(name),
            .terms = terms,
        };
    }

    /// Clone the predicate
    ///
    /// Reuses the allocator that allocated the original predicate's
    /// terms.
    pub fn clone(predicate: *const Predicate) !Predicate {
        return .{
            .name = predicate.name,
            .terms = try predicate.terms.clone(),
        };
    }

    /// Clone the predicate (using supplied allocator)
    ///
    /// Reuses the allocator that allocated the original predicate's
    /// terms.
    pub fn cloneWithAllocator(predicate: *const Predicate, allocator: mem.Allocator) !Predicate {
        var terms = std.ArrayList(Term).init(allocator);
        for (predicate.terms.items) |term| {
            try terms.append(term);
        }

        return .{
            .name = predicate.name,
            .terms = terms,
        };
    }

    pub fn hash(predicate: Predicate, hasher: anytype) void {
        std.hash.autoHash(hasher, predicate.name);
        for (predicate.terms.items) |term| {
            term.hash(hasher);
        }
    }
};

test {
    const testing = std.testing;
    const allocator = testing.allocator;

    var terms_1 = std.ArrayList(Term).init(allocator);
    defer terms_1.deinit();
    try terms_1.insertSlice(0, &.{ .{ .string = 10 }, .{ .integer = 20 } });

    var terms_2 = std.ArrayList(Term).init(allocator);
    defer terms_2.deinit();
    try terms_2.insertSlice(0, &.{ .{ .string = 10 }, .{ .integer = 20 } });

    var terms_3 = std.ArrayList(Term).init(allocator);
    defer terms_3.deinit();
    try terms_3.insertSlice(0, &.{ .{ .string = 10 }, .{ .integer = 21 } });

    var terms_4 = std.ArrayList(Term).init(allocator);
    defer terms_4.deinit();
    try terms_4.insertSlice(0, &.{ .{ .string = 10 }, .{ .integer = 20 } });

    var terms_5 = std.ArrayList(Term).init(allocator);
    defer terms_5.deinit();
    try terms_5.insertSlice(0, &.{ .{ .variable = 105 }, .{ .integer = 20 } });

    const p1: Predicate = .{ .name = 99, .terms = terms_1 };
    const p2: Predicate = .{ .name = 99, .terms = terms_2 };
    const p3: Predicate = .{ .name = 99, .terms = terms_3 };
    const p4: Predicate = .{ .name = 98, .terms = terms_4 };
    const p5: Predicate = .{ .name = 99, .terms = terms_5 };

    try testing.expect(p1.match(p2));
    try testing.expect(!p1.match(p3));
    try testing.expect(!p1.match(p4));
    try testing.expect(p1.match(p5));

    std.debug.print("predicate = {any}\n", .{p1});
}
