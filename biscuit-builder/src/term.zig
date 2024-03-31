const std = @import("std");
const datalog = @import("biscuit-datalog");
const Date = @import("date.zig").Date;

const TermTag = enum(u8) {
    variable,
    string,
    integer,
    bool,
    date,
    bytes,
    set,
};

pub const Term = union(TermTag) {
    variable: []const u8,
    string: []const u8,
    integer: i64,
    bool: bool,
    date: u64,
    bytes: []const u8,
    set: datalog.Set(Term),

    pub fn deinit(_: Term) void {}

    pub fn toDatalog(term: Term, arena: std.mem.Allocator, symbols: *datalog.SymbolTable) !datalog.Term {
        switch (term) {
            .variable => |s| return .{ .variable = std.math.cast(u32, try symbols.insert(s)) orelse return error.FailedToCastInt },
            .string => |s| return .{ .string = try symbols.insert(s) },
            .integer => |n| return .{ .integer = n },
            .bool => |b| return .{ .bool = b },
            .date => |d| return .{ .date = d },
            .bytes => |b| return .{ .bytes = b },
            .set => |s| {
                var datalog_set = datalog.Set(datalog.Term).init(arena);

                var it = s.iterator();
                while (it.next()) |t| {
                    try datalog_set.add(t);
                }

                return .{ .set = datalog_set };
            },
        }
    }

    pub fn format(term: Term, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (term) {
            .variable => |v| try writer.print("${s}", .{v}),
            .string => |s| try writer.print("\"{s}\"", .{s}),
            .integer => |n| try writer.print("{}", .{n}),
            .bool => |b| if (b) try writer.print("true", .{}) else try writer.print("false", .{}),
            .date => |n| try writer.print("{}", .{n}),
            .bytes => |b| try writer.print("{x}", .{b}),
            .set => |s| {
                try writer.print("[", .{});

                const count = s.count();

                var it = s.iterator();

                var i: usize = 0;
                while (it.next()) |t| {
                    defer i += 1;
                    try writer.print("{any}", .{t});

                    if (i < count - 1) try writer.print(", ", .{});
                }

                try writer.print("]", .{});
            },
        }
    }

    pub fn eql(term: Term, other_term: Term) bool {
        if (std.meta.activeTag(term) != std.meta.activeTag(other_term)) return false;

        return switch (term) {
            .variable => |v| std.mem.eql(u8, v, other_term.variable),
            .integer => |v| v == other_term.integer,
            .string => |v| std.mem.eql(u8, v, other_term.string),
            .bool => |v| v == other_term.bool,
            .date => |v| v == other_term.date,
            .bytes => |v| std.mem.eql(u8, v, other_term.bytes),
            .set => |v| v.eql(other_term.set),
        };
    }

    pub fn hash(term: Term, hasher: anytype) void {
        // Hash the tag type
        std.hash.autoHash(hasher, std.meta.activeTag(term));

        // Hash the value
        switch (term) {
            .variable => |v| for (v) |b| std.hash.autoHash(hasher, b),
            .integer => |v| std.hash.autoHash(hasher, v),
            .string => |v| for (v) |b| std.hash.autoHash(hasher, b),
            .bool => |v| std.hash.autoHash(hasher, v),
            .date => |v| std.hash.autoHash(hasher, v),
            .bytes => |v| for (v) |b| std.hash.autoHash(hasher, b),
            .set => |v| v.hash(hasher),
        }
    }
};
