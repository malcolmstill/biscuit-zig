const std = @import("std");
const datalog = @import("biscuit-datalog");
const Predicate = @import("predicate.zig").Predicate;
const Term = @import("term.zig").Term;

pub const Fact = struct {
    predicate: Predicate,
    variables: ?std.StringHashMap(?Term),

    pub fn deinit(_: Fact) void {
        // fact.predicate.deinit();
    }

    /// convert to datalog fact
    pub fn toDatalog(fact: Fact, allocator: std.mem.Allocator, symbols: *datalog.SymbolTable) !datalog.Fact {
        return .{ .predicate = try fact.predicate.toDatalog(allocator, symbols) };
    }

    pub fn format(fact: Fact, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        return writer.print("{any}", .{fact.predicate});
    }
};
