const std = @import("std");
const Fact = @import("../datalog/fact.zig").Fact;
const Rule = @import("../datalog/rule.zig").Rule;
const Check = @import("../datalog/check.zig").Check;

// Should we depend on the protobuf stuff here
const pb = @import("protobuf");
const schema = @import("format/schema.pb.zig");
const MIN_SCHEMA_VERSION = @import("format/serialized_biscuit.zig").MIN_SCHEMA_VERSION;
const MAX_SCHEMA_VERSION = @import("format/serialized_biscuit.zig").MAX_SCHEMA_VERSION;

pub const Block = struct {
    decoded_block: ?schema.Block = null,
    version: u32,
    context: []const u8,
    symbols: std.ArrayList([]const u8),
    facts: std.ArrayList(Fact),
    rules: std.ArrayList(Rule),
    checks: std.ArrayList(Check),

    pub fn init(allocator: std.mem.Allocator) !Block {
        return .{
            .version = 0,
            .context = "",
            .symbols = std.ArrayList([]const u8).init(allocator),
            .facts = std.ArrayList(Fact).init(allocator),
            .rules = std.ArrayList(Rule).init(allocator),
            .checks = std.ArrayList(Check).init(allocator),
        };
    }

    pub fn initFromBytes(allocator: std.mem.Allocator, data: []const u8) !Block {
        const decoded_block = try pb.pb_decode(schema.Block, data, allocator);
        errdefer pb.pb_deinit(decoded_block);

        var block = try init(allocator);
        errdefer block.deinit();

        block.decoded_block = decoded_block;

        const version = decoded_block.version orelse return error.ExpectedVersion;
        if (version < MIN_SCHEMA_VERSION) return error.BlockVersionTooLow;
        if (version > MAX_SCHEMA_VERSION) return error.BlockVersionTooHigh;

        block.version = version;

        for (decoded_block.symbols.items) |symbol| {
            try block.symbols.append(symbol.getSlice());
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

    pub fn deinit(self: *Block) void {
        for (self.checks.items) |*check| check.deinit();
        for (self.rules.items) |*rule| rule.deinit();
        for (self.facts.items) |*fact| fact.deinit();

        self.checks.deinit();
        self.rules.deinit();
        self.facts.deinit();
        self.symbols.deinit();

        if (self.decoded_block) |block| {
            pb.pb_deinit(block);
        }
    }
};
