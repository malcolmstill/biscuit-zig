const std = @import("std");
const mem = std.mem;

const Ed25519 = std.crypto.sign.Ed25519;

const log = std.log.scoped(.symbol_table);

pub const SymbolTable = struct {
    name: []const u8,
    allocator: mem.Allocator,
    symbols: std.ArrayList([]const u8),
    public_keys: std.ArrayList(Ed25519.PublicKey),

    pub fn init(name: []const u8, allocator: mem.Allocator) SymbolTable {
        return .{
            .name = name,
            .allocator = allocator,
            .symbols = std.ArrayList([]const u8).init(allocator),
            .public_keys = std.ArrayList(Ed25519.PublicKey).init(allocator),
        };
    }

    pub fn deinit(symbol_table: *SymbolTable) void {
        for (symbol_table.symbols.items) |symbol| {
            symbol_table.allocator.free(symbol);
        }
        symbol_table.symbols.deinit();

        symbol_table.public_keys.deinit();
    }

    pub fn insert(symbol_table: *SymbolTable, symbol: []const u8) !u64 {
        // If we find the symbol already in the table we can just return the index
        if (symbol_table.get(symbol)) |sym| {
            return sym;
        }

        const string = try symbol_table.allocator.alloc(u8, symbol.len);
        @memcpy(string, symbol);

        // Otherwise we need to insert the new symbol
        try symbol_table.symbols.append(string);

        const index = symbol_table.symbols.items.len - 1 + NON_DEFAULT_SYMBOLS_OFFSET;

        log.debug("inserting \"{s}\" at {} [{s}]", .{ symbol, index, symbol_table.name });

        return index;
    }

    pub fn get(symbol_table: *SymbolTable, symbol: []const u8) ?u64 {
        if (default_symbols.get(symbol)) |index| {
            return index;
        }

        for (symbol_table.symbols.items, 0..) |sym, i| {
            if (!mem.eql(u8, symbol, sym)) continue;

            return i + NON_DEFAULT_SYMBOLS_OFFSET;
        }

        return null;
    }

    pub fn insertPublicKey(symbol_table: *SymbolTable, public_key: Ed25519.PublicKey) !u64 {
        for (symbol_table.public_keys.items, 0..) |k, i| {
            if (std.mem.eql(u8, &k.bytes, &public_key.bytes)) return i;
        }

        try symbol_table.public_keys.append(public_key);
        return symbol_table.public_keys.items.len - 1;
    }

    pub fn getPublicKey(symbol_table: *const SymbolTable, index: usize) !Ed25519.PublicKey {
        if (index >= symbol_table.public_keys.items.len) return error.NoSuchPublicKey;

        return symbol_table.public_keys.items[index];
    }

    pub fn getString(symbol_table: *const SymbolTable, sym_index: u64) ![]const u8 {
        if (indexToDefault(sym_index)) |sym| {
            return sym;
        }

        if (sym_index >= NON_DEFAULT_SYMBOLS_OFFSET and sym_index < NON_DEFAULT_SYMBOLS_OFFSET + symbol_table.symbols.items.len) {
            const sym = symbol_table.symbols.items[sym_index - NON_DEFAULT_SYMBOLS_OFFSET];
            return sym;
        }

        return error.SymbolNotFound;
    }

    fn indexToDefault(sym_index: u64) ?[]const u8 {
        return switch (sym_index) {
            0 => "read",
            1 => "write",
            2 => "resource",
            3 => "operation",
            4 => "right",
            5 => "time",
            6 => "role",
            7 => "owner",
            8 => "tenant",
            9 => "namespace",
            10 => "user",
            11 => "team",
            12 => "service",
            13 => "admin",
            14 => "email",
            15 => "group",
            16 => "member",
            17 => "ip_address",
            18 => "client",
            19 => "client_ip",
            20 => "domain",
            21 => "path",
            22 => "version",
            23 => "cluster",
            24 => "node",
            25 => "hostname",
            26 => "nonce",
            27 => "query",
            else => null,
        };
    }
};

const NON_DEFAULT_SYMBOLS_OFFSET = 1024;

const default_symbols = std.ComptimeStringMap(u64, .{
    .{ "read", 0 },
    .{ "write", 1 },
    .{ "resource", 2 },
    .{ "operation", 3 },
    .{ "right", 4 },
    .{ "time", 5 },
    .{ "role", 6 },
    .{ "owner", 7 },
    .{ "tenant", 8 },
    .{ "namespace", 9 },
    .{ "user", 10 },
    .{ "team", 11 },
    .{ "service", 12 },
    .{ "admin", 13 },
    .{ "email", 14 },
    .{ "group", 15 },
    .{ "member", 16 },
    .{ "ip_address", 17 },
    .{ "client", 18 },
    .{ "client_ip", 19 },
    .{ "domain", 20 },
    .{ "path", 21 },
    .{ "version", 22 },
    .{ "cluster", 23 },
    .{ "node", 24 },
    .{ "hostname", 25 },
    .{ "nonce", 26 },
    .{ "query", 27 },
});

test {
    const testing = std.testing;

    var st = SymbolTable.init("test", testing.allocator);
    defer st.deinit();

    try testing.expectEqual(@as(?u64, 0), st.get("read"));
    try testing.expectEqual(@as(?u64, 27), st.get("query"));
    try testing.expectEqual(@as(?u64, null), st.get("shibboleth"));

    const index = try st.insert("shibboleth");
    try testing.expectEqual(@as(?u64, 1024), index);

    try testing.expectEqualStrings("read", try st.getString(0));
    try testing.expectEqualStrings("query", try st.getString(27));
    try testing.expectEqualStrings("shibboleth", try st.getString(1024));
    try testing.expectError(error.SymbolNotFound, st.getString(1025));
}
