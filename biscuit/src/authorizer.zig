const std = @import("std");
const mem = std.mem;
const Biscuit = @import("biscuit.zig").Biscuit;
const World = @import("biscuit-datalog").world.World;
const Check = @import("biscuit-datalog").check.Check;
const SymbolTable = @import("biscuit-datalog").symbol_table.SymbolTable;

pub const Authorizer = struct {
    allocator: mem.Allocator,
    biscuit: ?Biscuit,
    world: World,
    symbols: SymbolTable,

    pub fn init(allocator: std.mem.Allocator, biscuit: Biscuit) Authorizer {
        return .{
            .allocator = allocator,
            .biscuit = biscuit,
            .world = World.init(allocator),
            .symbols = SymbolTable.init(allocator),
        };
    }

    pub fn deinit(authorizer: *Authorizer) void {
        authorizer.world.deinit();
        authorizer.symbols.deinit();
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
    pub fn authorize(authorizer: *Authorizer) !void {
        var errors = std.ArrayList(AuthorizerError).init(authorizer.allocator);
        defer errors.deinit();

        std.log.debug("authorizing biscuit:\n", .{});
        // Load facts and rules from authority block into world. Our block's facts
        // will have a particular symbol table that we map into the symvol table
        // of the world.
        //
        // For example, the token may have a string "user123" which has id 12. But
        // when mapped into the world it may have id 5.
        if (authorizer.biscuit) |biscuit| {
            for (biscuit.authority.facts.items) |fact| {
                try authorizer.world.addFact(try fact.convert(&biscuit.authority.symbols, &authorizer.symbols));
            }

            for (biscuit.authority.rules.items) |rule| {
                // FIXME: remap rule
                try authorizer.world.addRule(rule);
            }
        }

        try authorizer.world.run(authorizer.symbols);
        // TODO: clear rules

        // TODO: Run checks that have been added to this authorizer

        // Run checks in the biscuit
        if (authorizer.biscuit) |biscuit| {
            for (biscuit.authority.checks.items) |check| {
                std.log.debug("{any}\n", .{check});

                for (check.queries.items) |*query| {
                    const is_match = try authorizer.world.queryMatch(query, authorizer.symbols);

                    if (!is_match) try errors.append(.{ .failed_check = 0 });
                    std.log.debug("match {any} = {}\n", .{ query, is_match });
                }
            }
        }

        // TODO: run policies

        // TODO: run other block checks

        // FIXME: return logic
        if (errors.items.len > 0) return error.AuthorizationFailed;
    }
};

const AuthorizerErrorKind = enum(u8) {
    failed_check,
};

const AuthorizerError = union(AuthorizerErrorKind) {
    failed_check: u32,
};
