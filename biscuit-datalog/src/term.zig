const std = @import("std");
const mem = std.mem;
const schema = @import("biscuit-schema");
const Predicate = @import("predicate.zig").Predicate;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

const TermKind = enum(u8) {
    variable,
    integer,
    string,
    date,
    bytes,
    bool,
    // set,
};

pub const Term = union(TermKind) {
    variable: u32,
    integer: i64,
    string: u64,
    date: u64,
    bytes: []const u8,
    bool: bool,
    // set: TermSet,

    pub fn fromSchema(term: schema.TermV2) !Term {
        const content = term.Content orelse return error.TermExpectedContent;

        return switch (content) {
            .variable => |v| .{ .variable = v },
            .integer => |v| .{ .integer = v },
            .string => |v| .{ .string = v },
            .bool => |v| .{ .bool = v },
            .bytes => |v| .{ .bytes = v.getSlice() },
            .date => |v| .{ .date = v },
            // .set => |_| @panic("Unimplemented"),
        };
    }

    pub fn convert(term: Term, old_symbols: *const SymbolTable, new_symbols: *SymbolTable) !Term {
        return switch (term) {
            .variable => |id| .{ .variable = std.math.cast(u32, try new_symbols.insert(try old_symbols.getString(id))) orelse return error.VariableIdTooLarge },
            .string => |id| .{ .string = try new_symbols.insert(try old_symbols.getString(id)) },
            .integer, .bool, .bytes, .date => term,
        };
    }

    pub fn eql(self: Term, term: Term) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(term)) return false;

        return switch (self) {
            .variable => |v| v == term.variable, // are variables always eql? eql if the symbol is the same? not eql?
            .integer => |v| v == term.integer,
            .string => |v| v == term.string,
            .bool => |v| v == term.bool,
            .date => |v| v == term.date,
            .bytes => |v| mem.eql(u8, v, term.bytes),
        };
    }

    /// Match terms
    ///
    /// Note that this function isn't called `match` because it isn't a pure test.
    /// We test for equality for most term types, but for variable terms we
    /// _always_ match.
    pub fn match(self: Term, term: Term) bool {
        // If either term is a variable, we match
        if (std.meta.activeTag(self) == .variable) return true;
        if (std.meta.activeTag(term) == .variable) return true;

        // Otherwise we need variables of the same type
        if (std.meta.activeTag(self) != std.meta.activeTag(term)) return false;

        // ...and the values need to match
        return switch (self) {
            .variable => true,
            .integer => |v| v == term.integer,
            .string => |v| v == term.string,
            .bool => |v| v == term.bool,
            .date => |v| v == term.date,
            .bytes => |v| mem.eql(u8, v, term.bytes),
        };
    }

    pub fn format(self: Term, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) std.os.WriteError!void {
        return switch (self) {
            .variable => |v| writer.print("$sym:{any}", .{v}),
            .integer => |v| writer.print("{any}", .{v}),
            .string => |v| writer.print("\"sym:{any}\"", .{v}),
            .bool => |v| writer.print("{}", .{v}),
            .date => |v| writer.print("{}", .{v}), // FIXME: render a date
            .bytes => |v| writer.print("{x}", .{v}),
        };
    }

    pub fn deinit(self: *Term) void {
        _ = self;
    }
};

pub fn hash(hasher: anytype, term: Term) void {
    std.hash.autoHash(hasher, term);
}

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
