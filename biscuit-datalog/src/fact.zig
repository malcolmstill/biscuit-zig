const std = @import("std");
const schema = @import("biscuit-schema");
const prd = @import("predicate.zig");
const Predicate = prd.Predicate;

pub const Fact = struct {
    predicate: Predicate,

    pub fn fromSchema(allocator: std.mem.Allocator, fact: schema.FactV2) !Fact {
        const predicate = fact.predicate orelse return error.NoPredicateInFactSchema;

        return .{ .predicate = try Predicate.fromSchema(allocator, predicate) };
    }

    pub fn init(predicate: Predicate) Fact {
        return .{ .predicate = predicate };
    }

    pub fn deinit(self: *Fact) void {
        self.predicate.deinit();
    }

    pub fn eql(self: Fact, fact: Fact) bool {
        return self.predicate.eql(fact.predicate);
    }

    pub fn matchPredicate(self: Fact, predicate: Predicate) bool {
        return self.predicate.match(predicate);
    }

    pub fn format(self: Fact, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) std.os.WriteError!void {
        return writer.print("{any}", .{self.predicate});
    }

    pub fn hash(self: Fact, hasher: anytype) void {
        prd.hash(hasher, self.predicate);
    }
};
