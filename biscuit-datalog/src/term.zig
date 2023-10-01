const std = @import("std");
const schema = @import("biscuit-schema");
const Predicate = @import("predicate.zig").Predicate;

const TermKind = enum(u8) {
    variable,
    integer,
    string,
    // date,
    // bytes,
    // bool,
    // set,
};

pub const Term = union(TermKind) {
    variable: u32,
    integer: i64,
    string: u64,
    // date: u64,
    // bytes: []const u8,
    // bool: bool,
    // set: TermSet,

    pub fn fromSchema(term: schema.TermV2) !Term {
        const content = term.Content orelse return error.TermExpectedContent;

        return switch (content) {
            .variable => |v| .{ .variable = v },
            .integer => |v| .{ .integer = v },
            .string => |v| .{ .string = v },
            else => @panic("Unimplemented"),
            // .date => |v| .{ .date = v },
            // .bytes => |v| .{ .bytes = v.getSlice() },
            // .bool => |v| .{ .bool = v },
            // .set => |_| @panic("Unimplemented"),
        };
    }

    /// Match terms
    ///
    /// Note that this function isn't called `eql` because it isn't a pure test.
    /// We test for equality for most term types, but for variable terms we
    /// _always_ match.
    pub fn match(self: Term, term: Term) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(term)) return false;

        return switch (self) {
            .variable => true,
            .integer => |v| v == term.integer,
            .string => |v| v == term.string,
        };
    }

    pub fn format(self: Term, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) std.os.WriteError!void {
        return switch (self) {
            .variable => |v| writer.print("$sym:{any}", .{v}),
            .integer => |v| writer.print("{any}", .{v}),
            .string => |v| writer.print("\"sym:{any}\"", .{v}),
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

    try testing.expect(t1.eql(t2));

    const t3: Term = .{ .integer = 22 };
    try testing.expect(!t1.eql(t3));

    const t4: Term = .{ .string = 25 };
    try testing.expect(!t1.eql(t4));
}
