const std = @import("std");
const mem = std.mem;
const schema = @import("biscuit-schema");
const Predicate = @import("predicate.zig").Predicate;
const SymbolTable = @import("symbol_table.zig").SymbolTable;
const Set = @import("set.zig").Set;

const TermKind = enum(u8) {
    variable,
    integer,
    string,
    date,
    bool,
    bytes,
    set,
};

pub const Term = union(TermKind) {
    variable: u32,
    integer: i64,
    string: u64,
    date: u64,
    bool: bool,
    bytes: []const u8,
    set: Set(Term),

    pub fn fromSchema(allocator: mem.Allocator, schema_term: schema.TermV2) !Term {
        const content = schema_term.Content orelse return error.TermExpectedContent;

        return switch (content) {
            .variable => |v| .{ .variable = v },
            .integer => |v| .{ .integer = v },
            .string => |v| .{ .string = v },
            .bool => |v| .{ .bool = v },
            .date => |v| .{ .date = v },
            .bytes => |v| .{ .bytes = v.getSlice() },
            .set => |v| {
                var set = Set(Term).init(allocator);
                for (v.set.items) |term| {
                    try set.add(try Term.fromSchema(allocator, term));
                }
                return .{ .set = set };
            },
        };
    }

    pub fn remap(term: Term, old_symbols: *const SymbolTable, new_symbols: *SymbolTable) !Term {
        return switch (term) {
            .variable => |id| .{ .variable = std.math.cast(u32, try new_symbols.insert(try old_symbols.getString(id))) orelse return error.VariableIdTooLarge },
            .string => |id| .{ .string = try new_symbols.insert(try old_symbols.getString(id)) },
            .integer, .bool, .date, .bytes => term,
            .set => |s| blk: {
                var set = Set(Term).init(s.alloc);

                var it = s.iterator();
                while (it.next()) |term_ptr| {
                    try set.add(try term_ptr.remap(old_symbols, new_symbols));
                }

                break :blk .{ .set = set };
            },
        };
    }

    pub fn eql(term: Term, other_term: Term) bool {
        if (std.meta.activeTag(term) != std.meta.activeTag(other_term)) return false;

        return switch (term) {
            .variable => |v| v == other_term.variable, // are variables always eql? eql if the symbol is the same? not eql?
            .integer => |v| v == other_term.integer,
            .string => |v| v == other_term.string,
            .bool => |v| v == other_term.bool,
            .date => |v| v == other_term.date,
            .bytes => |v| mem.eql(u8, v, other_term.bytes),
            .set => |v| v.eql(other_term.set),
        };
    }

    /// Match terms
    ///
    /// Note that this function isn't called `eql` because it isn't a pure equality test.
    /// We test for equality for most term types, but for variable terms we _always_ match.
    pub fn match(term: Term, other_term: Term) bool {
        // If either term is a variable, we match
        if (term == .variable) return true;
        if (other_term == .variable) return true;

        // Otherwise we need variables of the same type
        if (std.meta.activeTag(term) != std.meta.activeTag(other_term)) return false;

        // ...and the values need to match
        return switch (term) {
            .variable => unreachable,
            .integer => |v| v == other_term.integer,
            .string => |v| v == other_term.string,
            .bool => |v| v == other_term.bool,
            .date => |v| v == other_term.date,
            .bytes => |v| mem.eql(u8, v, other_term.bytes),
            .set => |v| v.eql(other_term.set),
        };
    }

    pub fn format(term: Term, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        return switch (term) {
            .variable => |v| writer.print("$sym:{any}", .{v}),
            .integer => |v| writer.print("{any}", .{v}),
            .string => |v| writer.print("\"sym:{any}\"", .{v}),
            .bool => |v| writer.print("{}", .{v}),
            .date => |v| writer.print("{}", .{v}), // FIXME: render a date
            .bytes => |v| writer.print("{}", .{std.fmt.fmtSliceHexLower(v)}),
            .set => |v| writer.print("{}", .{v}),
        };
    }

    pub fn deinit(term: *Term) void {
        _ = term;
    }

    pub fn hash(term: Term, hasher: anytype) void {
        // Hash the tag type
        std.hash.autoHash(hasher, std.meta.activeTag(term));

        // Hash the value
        switch (term) {
            .variable => |v| std.hash.autoHash(hasher, v),
            .integer => |v| std.hash.autoHash(hasher, v),
            .string => |v| std.hash.autoHash(hasher, v),
            .bool => |v| std.hash.autoHash(hasher, v),
            .date => |v| std.hash.autoHash(hasher, v),
            .bytes => |bytes| {
                // We hash the individual bytes because just calling
                // autoHash on the `bytes` slice will include the slice's pointer in the
                // hashing, which we don't want.
                for (bytes) |b| std.hash.autoHash(hasher, b);
            },
            .set => |v| v.hash(hasher),
        }
    }
};

pub const TermSet = struct {
    set: std.ArrayList(Term),

    pub fn init(allocator: std.mem.Allocator) TermSet {
        return .{ .set = std.ArrayList(Term).init(allocator) };
    }
};

test {
    const testing = std.testing;

    const t1: Term = .{ .string = 22 };
    const t2: Term = .{ .string = 22 };

    try testing.expect(t1.match(t2));

    const t3: Term = .{ .integer = 22 };
    try testing.expect(!t1.match(t3));

    const t4: Term = .{ .string = 25 };
    try testing.expect(!t1.match(t4));

    // Variables always match
    const t5: Term = .{ .variable = 100 };
    try testing.expect(t1.match(t5));
    try testing.expect(t5.match(t1));
}
