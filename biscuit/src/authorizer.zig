const std = @import("std");
const mem = std.mem;
const Biscuit = @import("biscuit.zig").Biscuit;
const World = @import("biscuit-datalog").world.World;
const Check = @import("biscuit-datalog").check.Check;
const SymbolTable = @import("biscuit-datalog").symbol_table.SymbolTable;
const Parser = @import("biscuit-parser").Parser;
const builder = @import("biscuit-builder");

pub const Authorizer = struct {
    allocator: mem.Allocator,
    checks: std.ArrayList(builder.Check),
    biscuit: ?Biscuit,
    world: World,
    symbols: SymbolTable,

    pub fn init(allocator: std.mem.Allocator, biscuit: Biscuit) Authorizer {
        return .{
            .allocator = allocator,
            .checks = std.ArrayList(builder.Check).init(allocator),
            .biscuit = biscuit,
            .world = World.init(allocator),
            .symbols = SymbolTable.init(allocator),
        };
    }

    pub fn deinit(authorizer: *Authorizer) void {
        authorizer.world.deinit();
        authorizer.symbols.deinit();

        for (authorizer.checks.items) |check| {
            check.deinit();
        }
        authorizer.checks.deinit();
    }

    pub fn addFact(authorizer: *Authorizer, input: []const u8) !void {
        std.debug.print("addFact = \"{s}\"\n", .{input});
        var parser = Parser.init(input);

        const fact = try parser.fact(authorizer.allocator);

        std.debug.print("fact = {any}\n", .{fact});

        try authorizer.world.addFact(try fact.convert(authorizer.allocator, &authorizer.symbols));
    }

    pub fn addCheck(authorizer: *Authorizer, input: []const u8) !void {
        var parser = Parser.init(input);

        const check = try parser.check(authorizer.allocator);

        try authorizer.checks.append(check);
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
    pub fn authorize(authorizer: *Authorizer, errors: *std.ArrayList(AuthorizerError)) !void {
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

        //  3. Run checks that have been added to this authorizer
        for (authorizer.checks.items) |c| {
            const check = try c.convert(authorizer.allocator, &authorizer.symbols);

            for (check.queries.items, 0..) |*query, check_id| {
                const is_match = try authorizer.world.queryMatch(query, authorizer.symbols);

                if (!is_match) try errors.append(.{ .failed_authority_check = .{ .check_id = check_id } });
                std.debug.print("match {any} = {}\n", .{ query, is_match });
            }
        }

        // 4. Run checks in the biscuit's authority block
        if (authorizer.biscuit) |biscuit| {
            for (biscuit.authority.checks.items) |check| {
                std.debug.print("{any}\n", .{check});

                for (check.queries.items, 0..) |*query, check_id| {
                    const is_match = try authorizer.world.queryMatch(query, authorizer.symbols);

                    if (!is_match) try errors.append(.{ .failed_block_check = .{ .block_id = 0, .check_id = check_id } });
                    std.debug.print("match {any} = {}\n", .{ query, is_match });
                }
            }
        }

        // TODO: 5. run policies from the authorizer

        // TODO: 6. Run checks in the biscuit's authority block
        if (authorizer.biscuit) |biscuit| {
            for (biscuit.blocks.items, 1..) |block, block_id| {
                std.debug.print("block = {any}\n", .{block});
                for (block.checks.items, 0..) |check, check_id| {
                    std.debug.print("check = {any}\n", .{check});
                    for (check.queries.items) |*query| {
                        const is_match = try authorizer.world.queryMatch(query, authorizer.symbols);

                        if (!is_match) try errors.append(.{ .failed_block_check = .{ .block_id = block_id, .check_id = check_id } });
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
    failed_authority_check,
    failed_block_check,
};

pub const AuthorizerError = union(AuthorizerErrorKind) {
    failed_authority_check: struct { check_id: usize },
    failed_block_check: struct { block_id: usize, check_id: usize },
};
