const std = @import("std");
const mem = std.mem;
const Biscuit = @import("biscuit.zig").Biscuit;
const World = @import("biscuit-datalog").world.World;
const Origin = @import("biscuit-datalog").Origin;
const TrustedOrigins = @import("biscuit-datalog").TrustedOrigins;
const Check = @import("biscuit-datalog").check.Check;
const SymbolTable = @import("biscuit-datalog").symbol_table.SymbolTable;
const Scope = @import("biscuit-datalog").Scope;
const Parser = @import("biscuit-parser").Parser;
const builder = @import("biscuit-builder");
const PolicyResult = @import("biscuit-builder").PolicyResult;

const log = std.log.scoped(.authorizer);

pub const Authorizer = struct {
    arena: mem.Allocator,
    checks: std.ArrayList(builder.Check),
    policies: std.ArrayList(builder.Policy),
    biscuit: ?Biscuit,
    world: World,
    symbols: SymbolTable,
    public_key_to_block_id: std.AutoHashMap(usize, std.ArrayList(usize)),
    scopes: std.ArrayList(Scope),

    pub fn init(arena: std.mem.Allocator, biscuit: Biscuit) !Authorizer {
        var symbols = SymbolTable.init("authorizer", arena);
        var public_key_to_block_id = std.AutoHashMap(usize, std.ArrayList(usize)).init(arena);

        // Map public key symbols into authorizer symbols and public_key_to_block_id map
        var it = biscuit.public_key_to_block_id.iterator();
        while (it.next()) |entry| {
            const biscuit_public_key_index = entry.key_ptr.*;
            const block_ids = entry.value_ptr.*;

            const public_key = try biscuit.symbols.getPublicKey(biscuit_public_key_index);

            const authorizer_public_key_index = try symbols.insertPublicKey(public_key);

            try public_key_to_block_id.put(authorizer_public_key_index, try block_ids.clone());
        }

        return .{
            .arena = arena,
            .checks = std.ArrayList(builder.Check).init(arena),
            .policies = std.ArrayList(builder.Policy).init(arena),
            .biscuit = biscuit,
            .world = World.init(arena),
            .symbols = symbols,
            .public_key_to_block_id = public_key_to_block_id,
            .scopes = std.ArrayList(Scope).init(arena),
        };
    }

    pub fn deinit(_: *Authorizer) void {
        // authorizer.world.deinit();
        // authorizer.symbols.deinit();
        // authorizer.scopes.deinit();

        // for (authorizer.checks.items) |check| {
        //     check.deinit();
        // }
        // authorizer.checks.deinit();

        // for (authorizer.policies.items) |policy| {
        //     policy.deinit();
        // }
        // authorizer.policies.deinit();

        // {
        //     var it = authorizer.public_key_to_block_id.valueIterator();
        //     while (it.next()) |block_ids| {
        //         block_ids.deinit();
        //     }
        //     authorizer.public_key_to_block_id.deinit();
        // }
    }

    pub fn authorizerTrustedOrigins(authorizer: *Authorizer) !TrustedOrigins {
        return try TrustedOrigins.fromScopes(
            authorizer.arena,
            authorizer.scopes.items,
            try TrustedOrigins.defaultOrigins(authorizer.arena),
            Origin.AUTHORIZER_ID,
            authorizer.public_key_to_block_id,
        );
    }

    /// Add fact from string to authorizer
    pub fn addFact(authorizer: *Authorizer, input: []const u8) !void {
        log.debug("addFact = {s}", .{input});
        var parser = Parser.init(authorizer.arena, input);

        const fact = try parser.fact();

        const origin = try Origin.initWithId(authorizer.arena, Origin.AUTHORIZER_ID);

        try authorizer.world.addFact(origin, try fact.toDatalog(authorizer.arena, &authorizer.symbols));
    }

    /// Add check from string to authorizer
    pub fn addCheck(authorizer: *Authorizer, input: []const u8) !void {
        log.debug("addCheck = {s}", .{input});
        var parser = Parser.init(authorizer.arena, input);

        const check = try parser.check();

        try authorizer.checks.append(check);
    }

    /// Add policy from string to authorizer
    pub fn addPolicy(authorizer: *Authorizer, input: []const u8) !void {
        log.debug("addPolicy = {s}", .{input});
        var parser = Parser.init(authorizer.arena, input);

        const policy = try parser.policy();

        try authorizer.policies.append(policy);
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
    pub fn authorize(authorizer: *Authorizer, errors: *std.ArrayList(AuthorizerError)) !usize {
        log.debug("Starting authorize()", .{});
        defer log.debug("Finished authorize()", .{});

        log.debug("authorizer  public keys:", .{});
        for (authorizer.symbols.public_keys.items, 0..) |pk, i| {
            log.debug("  [{}]: {x}", .{ i, pk.bytes });
        }

        {
            var it = authorizer.public_key_to_block_id.iterator();
            while (it.next()) |entry| {
                log.debug("public_key_to_block_id: public key id = {}, block_ids = {any}", .{ entry.key_ptr.*, entry.value_ptr.items });
            }
        }

        // 1.
        // Load facts and rules from authority block into world. Our block's facts
        // will have a particular symbol table that we map into the symvol table
        // of the world.
        //
        // For example, the token may have a string "user123" which has id 12. But
        // when mapped into the world it may have id 5.
        if (authorizer.biscuit) |biscuit| {
            log.debug("biscuit token public keys:", .{});
            for (biscuit.symbols.public_keys.items, 0..) |pk, i| {
                log.debug("  [{}]: {x}", .{ i, pk.bytes });
            }
            for (biscuit.authority.facts.items) |authority_fact| {
                const fact = try authority_fact.remap(&biscuit.symbols, &authorizer.symbols);
                const origin = try Origin.initWithId(authorizer.arena, 0);

                try authorizer.world.addFact(origin, fact);
            }

            const authority_trusted_origins = try TrustedOrigins.fromScopes(
                authorizer.arena,
                biscuit.authority.scopes.items,
                try TrustedOrigins.defaultOrigins(authorizer.arena),
                0,
                authorizer.public_key_to_block_id,
            );

            for (biscuit.authority.rules.items) |authority_rule| {
                // Map from biscuit symbol space to authorizer symbol space
                const rule = try authority_rule.remap(&biscuit.symbols, &authorizer.symbols);

                if (!rule.validateVariables()) {
                    try errors.append(.unbound_variable);
                }

                // A authority block's rule trusts
                const rule_trusted_origins = try TrustedOrigins.fromScopes(
                    authorizer.arena,
                    rule.scopes.items,
                    authority_trusted_origins,
                    0,
                    authorizer.public_key_to_block_id,
                );

                try authorizer.world.addRule(0, rule_trusted_origins, rule);
            }

            for (biscuit.blocks.items, 1..) |block, block_id| {
                for (block.facts.items) |block_fact| {
                    const fact = try block_fact.remap(&biscuit.symbols, &authorizer.symbols);
                    const origin = try Origin.initWithId(authorizer.arena, block_id);

                    try authorizer.world.addFact(origin, fact);
                }

                const block_trusted_origins = try TrustedOrigins.fromScopes(
                    authorizer.arena,
                    block.scopes.items,
                    try TrustedOrigins.defaultOrigins(authorizer.arena),
                    block_id,
                    authorizer.public_key_to_block_id,
                );

                for (block.rules.items) |block_rule| {
                    const rule = try block_rule.remap(&biscuit.symbols, &authorizer.symbols);
                    log.debug("block rule {any} CONVERTED to rule = {any}", .{ block_rule, rule });

                    if (!rule.validateVariables()) {
                        try errors.append(.unbound_variable);
                    }

                    const block_rule_trusted_origins = try TrustedOrigins.fromScopes(
                        authorizer.arena,
                        rule.scopes.items,
                        block_trusted_origins,
                        block_id,
                        authorizer.public_key_to_block_id,
                    );

                    try authorizer.world.addRule(block_id, block_rule_trusted_origins, rule);
                }
            }
        }

        // 2. Run the world to generate all facts
        log.debug("Run world", .{});
        try authorizer.world.run(&authorizer.symbols);
        log.debug("Finished running world", .{});

        //  3. Run checks that have been added to this authorizer
        log.debug("AUTHORIZER CHECKS", .{});
        for (authorizer.checks.items) |c| {
            log.debug("authorizer check = {any}", .{c});
            const check = try c.toDatalog(authorizer.arena, &authorizer.symbols);

            for (check.queries.items, 0..) |*query, check_id| {
                const rule_trusted_origins = try TrustedOrigins.fromScopes(
                    authorizer.arena,
                    query.scopes.items,
                    try authorizer.authorizerTrustedOrigins(),
                    Origin.AUTHORIZER_ID,
                    authorizer.public_key_to_block_id,
                );

                const is_match = switch (check.kind) {
                    .one => try authorizer.world.queryMatch(query, &authorizer.symbols, rule_trusted_origins),
                    .all => try authorizer.world.queryMatchAll(query, &authorizer.symbols, rule_trusted_origins),
                };

                if (!is_match) try errors.append(.{ .failed_authorizer_check = .{ .check_id = check_id } });
                log.debug("match {any} = {}", .{ query, is_match });
            }
        }
        log.debug("END AUTHORIZER CHECKS", .{});

        // 4. Run checks in the biscuit's authority block
        if (authorizer.biscuit) |biscuit| {
            const authority_trusted_origins = try TrustedOrigins.fromScopes(
                authorizer.arena,
                biscuit.authority.scopes.items,
                try TrustedOrigins.defaultOrigins(authorizer.arena),
                0,
                authorizer.public_key_to_block_id,
            );

            for (biscuit.authority.checks.items, 0..) |c, check_id| {
                const check = try c.remap(&biscuit.symbols, &authorizer.symbols);
                log.debug("{}: {any}", .{ check_id, check });

                for (check.queries.items) |*query| {
                    const rule_trusted_origins = try TrustedOrigins.fromScopes(
                        authorizer.arena,
                        query.scopes.items,
                        authority_trusted_origins,
                        0,
                        authorizer.public_key_to_block_id,
                    );

                    const is_match = switch (check.kind) {
                        .one => try authorizer.world.queryMatch(query, &authorizer.symbols, rule_trusted_origins),
                        .all => try authorizer.world.queryMatchAll(query, &authorizer.symbols, rule_trusted_origins),
                    };

                    if (!is_match) try errors.append(.{ .failed_block_check = .{ .block_id = 0, .check_id = check_id } });
                    log.debug("match {any} = {}", .{ query, is_match });
                }
            }
        }

        // 5. run policies from the authorizer
        const allowed_policy_id: ?usize = policy_blk: {
            for (authorizer.policies.items) |policy| {
                log.debug("testing policy {any}", .{policy});

                for (policy.queries.items, 0..) |*q, policy_id| {
                    var query = try q.toDatalog(authorizer.arena, &authorizer.symbols);

                    const rule_trusted_origins = try TrustedOrigins.fromScopes(
                        authorizer.arena,
                        query.scopes.items,
                        try authorizer.authorizerTrustedOrigins(),
                        Origin.AUTHORIZER_ID,
                        authorizer.public_key_to_block_id,
                    );

                    const is_match = try authorizer.world.queryMatch(&query, &authorizer.symbols, rule_trusted_origins);
                    log.debug("match {any} = {}", .{ query, is_match });

                    if (is_match) {
                        switch (policy.kind) {
                            .allow => break :policy_blk policy_id,
                            .deny => {
                                try errors.append(.{ .denied_by_policy = .{ .deny_policy_id = policy_id } });
                                break :policy_blk null;
                            },
                        }
                    }
                }
            }

            try errors.append(.{ .no_matching_policy = {} });
            break :policy_blk null;
        };

        // 6. Run checks in the biscuit's other blocks
        if (authorizer.biscuit) |biscuit| {
            for (biscuit.blocks.items, 1..) |block, block_id| {
                const block_trusted_origins = try TrustedOrigins.fromScopes(
                    authorizer.arena,
                    block.scopes.items,
                    try TrustedOrigins.defaultOrigins(authorizer.arena),
                    block_id,
                    authorizer.public_key_to_block_id,
                );

                for (block.checks.items, 0..) |c, check_id| {
                    const check = try c.remap(&biscuit.symbols, &authorizer.symbols);

                    log.debug("check = {any}", .{check});

                    for (check.queries.items) |*query| {
                        const rule_trusted_origins = try TrustedOrigins.fromScopes(
                            authorizer.arena,
                            query.scopes.items,
                            block_trusted_origins,
                            block_id,
                            authorizer.public_key_to_block_id,
                        );

                        const is_match = switch (check.kind) {
                            .one => try authorizer.world.queryMatch(query, &authorizer.symbols, rule_trusted_origins),
                            .all => try authorizer.world.queryMatchAll(query, &authorizer.symbols, rule_trusted_origins),
                        };

                        if (!is_match) try errors.append(.{ .failed_block_check = .{ .block_id = block_id, .check_id = check_id } });

                        log.debug("match {any} = {}", .{ query, is_match });
                    }
                }
            }
        }

        if (allowed_policy_id) |policy_id| {
            if (errors.items.len == 0) return policy_id;
        }

        return error.AuthorizationFailed;
    }
};

const AuthorizerErrorKind = enum(u8) {
    no_matching_policy,
    denied_by_policy,
    failed_authorizer_check,
    failed_block_check,
    unbound_variable,
};

pub const AuthorizerError = union(AuthorizerErrorKind) {
    no_matching_policy: void,
    denied_by_policy: struct { deny_policy_id: usize },
    failed_authorizer_check: struct { check_id: usize },
    failed_block_check: struct { block_id: usize, check_id: usize },
    unbound_variable: void,

    pub fn format(authorization_error: AuthorizerError, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (authorization_error) {
            .no_matching_policy => try writer.print("no matching policy", .{}),
            .denied_by_policy => |e| try writer.print("denied by policy {}", .{e.deny_policy_id}),
            .failed_authorizer_check => |e| try writer.print("failed authorizer check {}", .{e.check_id}),
            .failed_block_check => |e| try writer.print("failed check {} on block {}", .{ e.check_id, e.block_id }),
            .unbound_variable => try writer.print("unbound variable", .{}),
        }
    }
};
