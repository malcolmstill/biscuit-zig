const std = @import("std");
const datalog = @import("biscuit-datalog");
const Term = @import("term.zig").Term;

pub const Predicate = struct {
    name: []const u8,
    terms: std.ArrayList(Term),

    pub fn deinit(predicate: Predicate) void {
        for (predicate.terms.items) |term| {
            term.deinit();
        }

        predicate.terms.deinit();
    }

    /// convert to datalog predicate
    pub fn convert(predicate: Predicate, allocator: std.mem.Allocator, symbols: *datalog.SymbolTable) !datalog.Predicate {
        const name = try symbols.insert(predicate.name);

        var terms = std.ArrayList(datalog.Term).init(allocator);

        for (predicate.terms.items) |term| {
            try terms.append(try term.convert(allocator, symbols));
        }

        return .{ .name = name, .terms = terms };
    }

    pub fn format(predicate: Predicate, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}(", .{predicate.name});
        for (predicate.terms.items, 0..) |*term, i| {
            try writer.print("{any}", .{term.*});
            if (i < predicate.terms.items.len - 1) try writer.print(", ", .{});
        }
        return writer.print(")", .{});
    }
};
