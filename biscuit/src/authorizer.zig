const std = @import("std");
const mem = std.mem;
const Biscuit = @import("biscuit.zig").Biscuit;
const World = @import("biscuit-datalog").world.World;
const SymbolTable = @import("biscuit-datalog").symbol_table.SymbolTable;

pub const Authorizer = struct {
    arena: std.heap.ArenaAllocator,
    biscuit: ?Biscuit,
    world: World,
    symbols: SymbolTable,

    pub fn init(allocator: std.mem.Allocator, biscuit: Biscuit) Authorizer {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .biscuit = biscuit,
            .world = World.init(allocator),
            .symbols = SymbolTable{},
        };
    }

    pub fn deinit(self: *Authorizer) void {
        self.world.deinit();
        self.arena.deinit();
    }

    pub fn authorize(self: *Authorizer) !void {
        var arena = self.arena.allocator();
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
                try self.world.addFact(arena, fact);
            }

            for (b.authority.rules.items) |rule| {
                // FIXME: remap rule
                try self.world.addRule(rule);
            }
        }

        try self.world.run(arena, self.symbols);
    }
};
