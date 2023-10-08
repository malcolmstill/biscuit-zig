const std = @import("std");
const mem = std.mem;

pub const SymbolTable = struct {
    symbols: std.ArrayList([]const u8),

    pub fn init(allocator: mem.Allocator) SymbolTable {
        return .{ .symbols = std.ArrayList([]const u8).init(allocator) };
    }

    pub fn deinit(self: *SymbolTable) void {
        self.symbols.deinit();
    }

    pub fn insert(self: *SymbolTable, symbol: []const u8) !u64 {
        _ = symbol;
        _ = self;
    }

    pub fn get(self: *SymbolTable, symbol: []const u8) ?u64 {
        _ = symbol;
        _ = self;
    }
};

const NON_DEFAULT_SYMBOLS_OFFSET = 1024;

test {
    const testing = std.testing;

    var st = SymbolTable.init(testing.allocator);
    defer st.deinit();
}
