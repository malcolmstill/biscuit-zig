const std = @import("std");
const format = @import("biscuit-format");
const schema = @import("biscuit-schema");
const Fact = @import("biscuit-datalog").fact.Fact;
const Rule = @import("biscuit-datalog").rule.Rule;
const Check = @import("biscuit-datalog").check.Check;
const SymbolTable = @import("biscuit-datalog").symbol_table.SymbolTable;
const MIN_SCHEMA_VERSION = format.serialized_biscuit.MIN_SCHEMA_VERSION;
const MAX_SCHEMA_VERSION = format.serialized_biscuit.MAX_SCHEMA_VERSION;

pub const Block = struct {
    decoded_block: ?schema.Block = null,
    version: u32,
    context: []const u8,
    symbols: SymbolTable,
    facts: std.ArrayList(Fact),
    rules: std.ArrayList(Rule),
    checks: std.ArrayList(Check),

    pub fn init(allocator: std.mem.Allocator) !Block {
        return .{
            .version = 0,
            .context = "",
            .symbols = SymbolTable.init(allocator),
            .facts = std.ArrayList(Fact).init(allocator),
            .rules = std.ArrayList(Rule).init(allocator),
            .checks = std.ArrayList(Check).init(allocator),
        };
    }

    pub fn initFromBytes(allocator: std.mem.Allocator, data: []const u8) !Block {
        const decoded_block = try schema.decodeBlock(allocator, data);
        errdefer decoded_block.deinit();

        var block = try init(allocator);
        errdefer block.deinit();

        block.decoded_block = decoded_block;

        const version = decoded_block.version orelse return error.ExpectedVersion;
        if (version < MIN_SCHEMA_VERSION) return error.BlockVersionTooLow;
        if (version > MAX_SCHEMA_VERSION) return error.BlockVersionTooHigh;

        block.version = version;

        for (decoded_block.symbols.items) |symbol| {
            _ = try block.symbols.insert(symbol.getSlice());
        }

        for (decoded_block.facts_v2.items) |fact| {
            try block.facts.append(try Fact.fromSchema(allocator, fact));
        }

        for (decoded_block.rules_v2.items) |rule| {
            try block.rules.append(try Rule.fromSchema(allocator, rule));
        }

        for (decoded_block.checks_v2.items) |check| {
            try block.checks.append(try Check.fromSchema(allocator, check));
        }

        return block;
    }

    pub fn deinit(block: *Block) void {
        for (block.checks.items) |*check| check.deinit();
        for (block.rules.items) |*rule| rule.deinit();
        for (block.facts.items) |*fact| fact.deinit();

        block.checks.deinit();
        block.rules.deinit();
        block.facts.deinit();
        block.symbols.deinit();

        if (block.decoded_block) |decoded_block| {
            decoded_block.deinit();
        }
    }
};
