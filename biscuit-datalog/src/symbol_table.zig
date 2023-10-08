const std = @import("std");
const mem = std.mem;

pub const SymbolTable = struct {
    allocator: mem.Allocator,
    symbols: std.ArrayList([]const u8),

    pub fn init(allocator: mem.Allocator) SymbolTable {
        return .{
            .allocator = allocator,
            .symbols = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *SymbolTable) void {
        for (self.symbols.items) |symbol| {
            self.allocator.free(symbol);
        }
        self.symbols.deinit();
    }

    pub fn insert(self: *SymbolTable, symbol: []const u8) !u64 {
        // If we find the symbol already in the table we can just return the index
        if (self.get(symbol)) |sym| {
            return sym;
        }

        var string = try self.allocator.alloc(u8, symbol.len);
        @memcpy(string, symbol);

        // Otherwise we need to insert the new symbol
        try self.symbols.append(string);

        return self.symbols.items.len - 1 + NON_DEFAULT_SYMBOLS_OFFSET;
    }

    pub fn get(self: *SymbolTable, symbol: []const u8) ?u64 {
        if (default_symbols.get(symbol)) |index| {
            return index;
        }

        for (self.symbols.items, 0..) |sym, i| {
            if (!mem.eql(u8, symbol, sym)) continue;

            return i + NON_DEFAULT_SYMBOLS_OFFSET;
        }

        return null;
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

    var st = SymbolTable.init(testing.allocator);
    defer st.deinit();

    try testing.expectEqual(@as(?u64, 0), st.get("read"));
    try testing.expectEqual(@as(?u64, 27), st.get("query"));
    try testing.expectEqual(@as(?u64, null), st.get("shibboleth"));

    const index = try st.insert("shibboleth");
    try testing.expectEqual(@as(?u64, 1024), index);
}
