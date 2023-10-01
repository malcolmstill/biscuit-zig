const std = @import("std");
const mem = std.mem;
const Biscuit = @import("biscuit.zig").Biscuit;
const World = @import("../datalog/world.zig").World;
const SymbolTable = @import("../datalog/symbol_table.zig").SymbolTable;

pub const Authorizer = struct {
    biscuit: ?Biscuit,
    world: World,
    symbols: SymbolTable,

    pub fn init(allocator: std.mem.Allocator, biscuit: Biscuit) Authorizer {
        return .{
            .biscuit = biscuit,
            .world = World.init(allocator),
            .symbols = SymbolTable{},
        };
    }

    pub fn deinit(self: *Authorizer) void {
        self.world.deinit();
    }

    pub fn authorize(self: *Authorizer, allocator: mem.Allocator) !void {
        std.debug.print("authorizing biscuit:\n", .{});
        // Load facts and rules from authority block into world. Our block's facts
        // will have a particular symbol table that we map into the symvol table
        // of the world.
        //
        // For example, the token may have a string "user123" which has id 12. But
        // when mapped into the world it may have id 5.
        if (self.biscuit) |biscuit| {
            var b: Biscuit = biscuit;

            for (b.authority.facts.items) |fact| {
                // FIXME: remap fact
                try self.world.addFact(fact);
            }

            for (b.authority.rules.items) |rule| {
                // FIXME: remap rule
                try self.world.addRule(rule);
            }
        }

        try self.world.run(allocator, self.symbols);
    }
};
