const std = @import("std");
const mem = std.mem;
const schema = @import("biscuit-schema");
const trm = @import("term.zig");
const Term = trm.Term;

pub const Predicate = struct {
    name: u64,
    terms: std.ArrayList(Term),

    pub fn fromSchema(allocator: mem.Allocator, predicate: schema.PredicateV2) !Predicate {
        var terms = std.ArrayList(Term).init(allocator);
        for (predicate.terms.items) |term| {
            try terms.append(try Term.fromSchema(term));
        }

        return .{ .name = predicate.name, .terms = terms };
    }

    pub fn format(self: Predicate, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) std.os.WriteError!void {
        try writer.print("sym:{any}(", .{self.name});
        for (self.terms.items, 0..) |*term, i| {
            try writer.print("{any}", .{term.*});
            if (i < self.terms.items.len - 1) try writer.print(", ", .{});
        }
        return writer.print(")", .{});
    }

    pub fn deinit(self: *Predicate) void {
        for (self.terms.items) |*term| {
            term.deinit();
        }
        self.terms.deinit();
    }

    /// Check if two predicates match
    ///
    /// The predicates must have the same name and each term in the
    /// predicates must match.
    ///
    /// Note again that "matching" terms is not exactly equality...
    /// in the case of variable terms they always match.
    pub fn match(self: Predicate, predicate: Predicate) bool {
        if (self.name != predicate.name) return false;
        if (self.terms.items.len != predicate.terms.items.len) return false;

        for (self.terms.items, predicate.terms.items) |term_a, term_b| {
            if (!term_a.match(term_b)) return false;
        }

        return true;
    }

    /// Clone the predicate
    ///
    /// Reuses the allocator that allocated the original predicate's
    /// terms.
    pub fn clone(self: *const Predicate) !Predicate {
        return .{
            .name = self.name,
            .terms = try self.terms.clone(),
        };
    }
};

pub fn hash(hasher: anytype, predicate: Predicate) void {
    std.hash.autoHash(hasher, predicate.name);
    for (predicate.terms.items) |term| {
        trm.hash(hasher, term);
    }
}

test {
    const testing = std.testing;
    var allocator = testing.allocator;

    var terms_1 = std.ArrayList(Term).init(allocator);
    defer terms_1.deinit();
    try terms_1.insertSlice(0, &[_]Term{ .{ .string = 10 }, .{ .variable = 20 } });

    var terms_2 = std.ArrayList(Term).init(allocator);
    defer terms_2.deinit();
    try terms_2.insertSlice(0, &[_]Term{ .{ .string = 10 }, .{ .variable = 20 } });

    var terms_3 = std.ArrayList(Term).init(allocator);
    defer terms_3.deinit();
    try terms_3.insertSlice(0, &[_]Term{ .{ .string = 10 }, .{ .variable = 21 } });

    var terms_4 = std.ArrayList(Term).init(allocator);
    defer terms_4.deinit();
    try terms_4.insertSlice(0, &[_]Term{ .{ .string = 10 }, .{ .variable = 20 } });

    const p1: Predicate = .{ .name = 99, .terms = terms_1 };
    const p2: Predicate = .{ .name = 99, .terms = terms_2 };
    const p3: Predicate = .{ .name = 99, .terms = terms_3 };
    const p4: Predicate = .{ .name = 98, .terms = terms_4 };

    try testing.expect(p1.eql(p2));
    try testing.expect(!p1.eql(p3));
    try testing.expect(!p1.eql(p4));
}
