const std = @import("std");
const Ed25519 = std.crypto.sign.Ed25519;
const SignedBlock = @import("biscuit-format").SignedBlock;
const MIN_SCHEMA_VERSION = @import("biscuit-format").MIN_SCHEMA_VERSION;
const MAX_SCHEMA_VERSION = @import("biscuit-format").MAX_SCHEMA_VERSION;
const schema = @import("biscuit-schema");
const Fact = @import("biscuit-datalog").fact.Fact;
const Rule = @import("biscuit-datalog").rule.Rule;
const Check = @import("biscuit-datalog").check.Check;
const Scope = @import("biscuit-datalog").Scope;
const SymbolTable = @import("biscuit-datalog").symbol_table.SymbolTable;

const log = std.log.scoped(.block);

pub const Block = struct {
    version: u32,
    context: []const u8,
    symbols: SymbolTable, // Do we need symbol table here? When we deserialize a biscuit we build up a complete symbol table for the entire biscuit. So what is the purpose?
    facts: std.ArrayList(Fact),
    rules: std.ArrayList(Rule),
    checks: std.ArrayList(Check),
    scopes: std.ArrayList(Scope),
    public_keys: std.ArrayList(Ed25519.PublicKey),

    pub fn init(arena: std.mem.Allocator) Block {
        return .{
            .version = 0,
            .context = "",
            .symbols = SymbolTable.init("block", arena), // FIXME: maybe we separately allocate this not in the arena
            .facts = std.ArrayList(Fact).init(arena),
            .rules = std.ArrayList(Rule).init(arena),
            .checks = std.ArrayList(Check).init(arena),
            .scopes = std.ArrayList(Scope).init(arena),
            .public_keys = std.ArrayList(Ed25519.PublicKey).init(arena),
        };
    }

    pub fn deinit(block: *Block) void {
        _ = block;
    }

    /// Given a blocks contents as bytes, derserialize into runtime block
    pub fn fromBytes(arena: std.mem.Allocator, signed_block: SignedBlock, token_symbols: *SymbolTable) !Block {
        const data = signed_block.block;

        const decoded_block = try schema.Block.decode(data, arena);
        defer decoded_block.deinit();

        var block = Block.init(arena);
        errdefer block.deinit();

        const version = decoded_block.version orelse return error.ExpectedVersion;
        if (version < MIN_SCHEMA_VERSION) return error.BlockVersionTooLow;
        if (version > MAX_SCHEMA_VERSION) return error.BlockVersionTooHigh;

        block.version = version;

        for (decoded_block.symbols.items) |symbol| {
            _ = try block.symbols.insert(symbol.getSlice());
        }

        // If we have an external signature we add the external public key that to the parent biscuit's symbols and we don't add the blocks symbols
        // Otherwise add the blocks symbols to the biscuit's symbol table.
        if (signed_block.external_signature) |external_signature| {
            _ = try token_symbols.insertPublicKey(external_signature.public_key);
        } else {
            for (decoded_block.symbols.items) |symbol| {
                _ = try token_symbols.insert(symbol.getSlice());
            }
        }

        for (decoded_block.facts_v2.items) |fact| {
            try block.facts.append(try Fact.fromSchema(arena, fact));
        }

        for (decoded_block.rules_v2.items) |rule| {
            try block.rules.append(try Rule.fromSchema(arena, rule));
        }

        for (decoded_block.checks_v2.items) |check| {
            try block.checks.append(try Check.fromSchema(arena, check));
        }

        for (decoded_block.publicKeys.items) |public_key| {
            var pubkey_buf: [Ed25519.PublicKey.encoded_length]u8 = undefined;
            @memcpy(&pubkey_buf, public_key.key.getSlice());

            const key = try Ed25519.PublicKey.fromBytes(pubkey_buf);

            _ = try token_symbols.insertPublicKey(key);
            try block.public_keys.append(key);
        }

        return block;
    }

    pub fn format(block: Block, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("block:\n", .{});
        try writer.print("  version: {}\n", .{block.version});
        try writer.print("  context: {s}\n", .{block.context});

        try writer.print("  symbols:\n", .{});
        for (block.symbols.symbols.items, 0..) |symbol, i| {
            try writer.print("    [{}]: {s}\n", .{ i, symbol });
        }

        try writer.print("  facts:\n", .{});
        for (block.facts.items, 0..) |fact, i| {
            try writer.print("    [{}]: {any}\n", .{ i, fact });
        }

        try writer.print("  rules:\n", .{});
        for (block.rules.items, 0..) |rule, i| {
            try writer.print("    [{}]: {any}\n", .{ i, rule });
        }

        try writer.print("  checks:\n", .{});
        for (block.checks.items, 0..) |check, i| {
            try writer.print("    [{}]: {any}\n", .{ i, check });
        }

        try writer.print("  public keys:\n", .{});
        for (block.public_keys.items, 0..) |public_key, i| {
            try writer.print("    [{}]: {x}\n", .{ i, public_key.bytes });
        }

        return;
    }
};
