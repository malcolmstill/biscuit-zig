const std = @import("std");
const datalog = @import("biscuit-datalog");
const Date = @import("date.zig").Date;

const TermTag = enum(u8) {
    variable,
    string,
    integer,
    bool,
    date,
};

pub const Term = union(TermTag) {
    variable: []const u8,
    string: []const u8,
    integer: i64,
    bool: bool,
    date: u64,

    pub fn deinit(_: Term) void {}

    pub fn convert(term: Term, _: std.mem.Allocator, symbols: *datalog.SymbolTable) !datalog.Term {
        return switch (term) {
            .variable => |s| .{ .variable = @truncate(try symbols.insert(s)) }, // FIXME: assert symbol fits in u32
            .string => |s| .{ .string = try symbols.insert(s) },
            .integer => |n| .{ .integer = n },
            .bool => |b| .{ .bool = b },
            .date => |d| .{ .date = d },
        };
    }

    pub fn format(term: Term, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (term) {
            .variable => |v| try writer.print("${s}", .{v}),
            .string => |s| try writer.print("\"{s}\"", .{s}),
            .integer => |n| try writer.print("{}", .{n}),
            .bool => |b| if (b) try writer.print("true", .{}) else try writer.print("false", .{}),
            .date => |n| try writer.print("{}", .{n}),
        }
    }
};
