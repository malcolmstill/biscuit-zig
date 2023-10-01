const std = @import("std");
const schema = @import("biscuit-schema");
const trm = @import("term.zig");
const Term = trm.Term;

pub const Predicate = struct {
    name: u64,
    terms: std.ArrayList(Term),

    pub fn fromSchema(allocator: std.mem.Allocator, predicate: schema.PredicateV2) !Predicate {
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
};

pub fn hash(hasher: anytype, predicate: Predicate) void {
    std.hash.autoHash(hasher, predicate.name);
    for (predicate.terms.items) |term| {
        trm.hash(hasher, term);
    }
}
