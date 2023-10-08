const std = @import("std");
const mem = std.mem;
const Biscuit = @import("biscuit.zig").Biscuit;
const World = @import("biscuit-datalog").world.World;
const SymbolTable = @import("biscuit-datalog").symbol_table.SymbolTable;

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

    /// authorize
    ///
    /// authorize the Authorizer
    ///
    /// The following high level steps take place during authorization:
    /// - If we have a biscuit load the biscuit's authority block's facts and
    ///   and rules into the Authorizer's world
    /// - Run the world to generate new facts
    /// - Loop over and apply all of checks _of the authorizer_
    /// - Again, if we have a biscuit, loop over and apply the biscuit's authority block's checks
    /// - Loop over the policies _of the authorizer_ (we won't have policies anywhere else)
    /// - Finally, again if we have a biscuit, loop over all of the biscuits non-authority
    ///   blocks and apply the checks therein.
    pub fn authorize(self: *Authorizer) !void {
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

        try self.world.run(self.symbols);
        // TODO: clear rules

        // TODO: Run checks that have been added to this authorizer

        // Run checks in the biscuit
        if (self.biscuit) |biscuit| {
            var b: Biscuit = biscuit;

            for (b.authority.checks.items) |check| {
                std.debug.print("{any}\n", .{check});
            }
        }
    }
};
