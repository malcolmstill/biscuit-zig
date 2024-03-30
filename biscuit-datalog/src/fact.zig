const std = @import("std");
const mem = std.mem;
const schema = @import("biscuit-schema");
const Predicate = @import("predicate.zig").Predicate;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

pub const Fact = struct {
    predicate: Predicate,

    pub fn fromSchema(allocator: std.mem.Allocator, schema_fact: schema.FactV2) !Fact {
        const predicate = schema_fact.predicate orelse return error.NoPredicateInFactSchema;

        return .{ .predicate = try Predicate.fromSchema(allocator, predicate) };
    }

    pub fn init(predicate: Predicate) Fact {
        return .{ .predicate = predicate };
    }

    pub fn deinit(fact: *Fact) void {
        fact.predicate.deinit();
    }

    /// Convert fact to new symbol space
    pub fn remapSymbols(fact: Fact, old_symbols: *const SymbolTable, new_symbols: *SymbolTable) !Fact {
        return .{ .predicate = try fact.predicate.remapSymbols(old_symbols, new_symbols) };
    }

    pub fn clone(fact: Fact) !Fact {
        return .{ .predicate = try fact.predicate.clone() };
    }

    pub fn cloneWithAllocator(fact: Fact, allocator: mem.Allocator) !Fact {
        return .{ .predicate = try fact.predicate.cloneWithAllocator(allocator) };
    }

    pub fn eql(fact: Fact, other_fact: Fact) bool {
        return fact.predicate.eql(other_fact.predicate);
    }

    pub fn matchPredicate(fact: Fact, predicate: Predicate) bool {
        return fact.predicate.match(predicate);
    }

    pub fn format(fact: Fact, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        return writer.print("{any}", .{fact.predicate});
    }

    pub fn hash(fact: Fact, hasher: anytype) void {
        fact.predicate.hash(hasher);
    }
};
