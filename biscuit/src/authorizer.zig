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
    /// The following high-level steps take place during authorization:
    /// 1. _biscuit_ (where it exists): load _all_ of the facts and rules
    ///   in the biscuit. We can add all the facts and rules as this time because
    ///   the facts and rules are scoped, i.e. the facts / rules are added to particular
    ///   scopes within the world.
    /// 2. Run the world to generate new facts.
    /// 3. _authorizer_: Run the _authorizer's_ checks
    /// 4. _biscuit_ (where it exists): run the authority block's checks
    /// 5. _authorizer_: Run the _authorizer's_ policies
    /// 6. _biscuit_ (where it exists): run the checks from all the non-authority blocks
    pub fn authorize(authorizer: *Authorizer) !void {
        var errors = std.ArrayList(AuthorizerError).init(authorizer.allocator);
        defer errors.deinit();

        std.debug.print("authorizing biscuit:\n", .{});
        // 1.
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

        // 2. Run the world to generate all facts
        try authorizer.world.run(authorizer.symbols);

        // TODO: 3. Run checks that have been added to this authorizer

        // 4. Run checks in the biscuit's authority block
        if (authorizer.biscuit) |biscuit| {
            for (biscuit.authority.checks.items) |check| {
                std.debug.print("{any}\n", .{check});

                for (check.queries.items) |*query| {
                    const is_match = try authorizer.world.queryMatch(query, authorizer.symbols);

                    if (!is_match) try errors.append(.{ .failed_check = 0 });
                    std.debug.print("match {any} = {}\n", .{ query, is_match });
                }
            }
        }

        // TODO: 5. run policies from the authorizer

        // TODO: 6. Run checks in the biscuit's authority block
        if (authorizer.biscuit) |biscuit| {
            for (biscuit.blocks.items) |block| {
                std.debug.print("block = {any}\n", .{block});
                for (block.checks.items) |check| {
                    std.debug.print("check = {any}\n", .{check});
                    for (check.queries.items) |*query| {
                        const is_match = try authorizer.world.queryMatch(query, authorizer.symbols);

                        if (!is_match) try errors.append(.{ .failed_check = 0 });
                        std.debug.print("match {any} = {}\n", .{ query, is_match });
                    }
                }
            }
        }

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
