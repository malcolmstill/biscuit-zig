const std = @import("std");
const datalog = @import("biscuit-datalog");

const TermTag = enum(u8) {
    variable,
    string,
    bool,
};

pub const Term = union(TermTag) {
    variable: []const u8,
    string: []const u8,
    bool: bool,

    pub fn deinit(_: Term) void {}

    pub fn convert(term: Term, _: std.mem.Allocator, symbols: *datalog.SymbolTable) !datalog.Term {
        return switch (term) {
            .variable => |s| .{ .variable = @truncate(try symbols.insert(s)) }, // FIXME: assert symbol fits in u32
            .string => |s| .{ .string = try symbols.insert(s) },
            .bool => |b| .{ .bool = b },
        };
    }

    pub fn format(term: Term, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (term) {
            .variable => |v| try writer.print("${s}", .{v}),
            .string => |s| try writer.print("\"{s}\"", .{s}),
            .bool => |b| if (b) try writer.print("true", .{}) else try writer.print("false", .{}),
        }
    }
};
