const std = @import("std");
const mem = std.mem;
const Biscuit = @import("biscuit.zig").Biscuit;
const World = @import("biscuit-datalog").world.World;
const Origin = @import("biscuit-datalog").Origin;
const TrustedOrigins = @import("biscuit-datalog").TrustedOrigins;
const Check = @import("biscuit-datalog").check.Check;
const SymbolTable = @import("biscuit-datalog").symbol_table.SymbolTable;
const Scope = @import("biscuit-datalog").Scope;
const Parser = @import("biscuit-builder").Parser;
const builder = @import("biscuit-builder");
const PolicyResult = @import("biscuit-builder").PolicyResult;

const log = std.log.scoped(.authorizer);

pub const Authorizer = struct {
    allocator: mem.Allocator,
    arena: mem.Allocator,
    checks: std.ArrayList(builder.Check),
    policies: std.ArrayList(builder.Policy),
    biscuit: ?*Biscuit,
    world: World,
    symbols: SymbolTable,
    public_key_to_block_id: std.AutoHashMap(usize, std.ArrayList(usize)),
    scopes: std.ArrayList(Scope),

    pub fn init(allocator: mem.Allocator, arena: std.mem.Allocator, biscuit: *Biscuit) !Authorizer {
        var symbols = SymbolTable.init("authorizer", allocator);
        var public_key_to_block_id = std.AutoHashMap(usize, std.ArrayList(usize)).init(arena);

        // Map public key symbols into authorizer symbols and public_key_to_block_id map
        var it = biscuit.public_key_to_block_id.iterator();
        while (it.next()) |entry| {
            const biscuit_public_key_index = entry.key_ptr.*;
            const block_ids = entry.value_ptr.*;

            const public_key = try biscuit.symbols.getPublicKey(biscuit_public_key_index);

            const authorizer_public_key_index = try symbols.insertPublicKey(public_key);

            var list = try std.ArrayList(usize).initCapacity(allocator, block_ids.items.len);

            for (block_ids.items) |id| try list.append(id);

            try public_key_to_block_id.put(authorizer_public_key_index, list);
        }

        return .{
            .allocator = allocator,
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

    pub fn deinit(authorizer: *Authorizer) void {
        authorizer.symbols.deinit();

        {
            var it = authorizer.public_key_to_block_id.valueIterator();
            while (it.next()) |block_ids| {
                block_ids.deinit();
            }
            authorizer.public_key_to_block_id.deinit();
        }
    }

    /// Authorize token with authorizer
    ///
    /// Will return without error if there is a matching `allow` policy id and the `errors`
    /// list is empty.
    ///
    /// Otherwise will return error.AuthorizationFailed with the reason(s) in `errors`
    pub fn authorize(authorizer: *Authorizer, errors: *std.ArrayList(AuthorizerError)) !usize {
        log.debug("Starting authorize()", .{});
        defer log.debug("Finished authorize()", .{});

        try authorizer.addTokenFactsAndRules(errors); // Step 1
        try authorizer.generateFacts(); // Step 2
        try authorizer.authorizerChecks(errors); // Step 3
        try authorizer.authorityChecks(errors); // Step 4
        const allowed_policy_id: ?usize = try authorizer.authorizerPolicies(errors); // Step 5
        try authorizer.blockChecks(errors); // Step 6

        if (allowed_policy_id) |policy_id| {
            if (errors.items.len == 0) return policy_id;
        }

        return error.AuthorizationFailed;
    }

    /// Step 1 in authorize()
    ///
    /// Adds all the facts and rules from the token to the authorizer's world.
    ///
    /// Note: this should only be called from authorize()
    fn addTokenFactsAndRules(authorizer: *Authorizer, errors: *std.ArrayList(AuthorizerError)) !void {
        // Load facts and rules from authority block into world. Our block's facts
        // will have a particular symbol table that we map into the symbol table
        // of the world.
        //
        // For example, the token may have a string "user123" which has id 12. But
        // when mapped into the world it may have id 5.
        const biscuit = authorizer.biscuit orelse return;

        // Add authority block's facts
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

        // Add authority block's rules
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
            // Add block facts
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

            // Add block rules
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

    /// Step 2 in authorize()
    ///
    /// Generate all new facts by running world.
    fn generateFacts(authorizer: *Authorizer) !void {
        log.debug("Run world", .{});
        defer log.debug("Finished running world", .{});

        try authorizer.world.run(&authorizer.symbols);
    }

    /// Step 3 in authorize()
    ///
    /// Runs the authorizer's checks
    ///
    /// Note: should only be called from authorize()
    fn authorizerChecks(authorizer: *Authorizer, errors: *std.ArrayList(AuthorizerError)) !void {
        log.debug("Start authorizerChecks()", .{});
        defer log.debug("End authorizerChecks()", .{});

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
    }

    /// Step 4 in authorize()
    ///
    /// Run checks from token's authority block
    ///
    /// Note: should only be called from authorizer()
    fn authorityChecks(authorizer: *Authorizer, errors: *std.ArrayList(AuthorizerError)) !void {
        const biscuit = authorizer.biscuit orelse return;

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

    /// Step 5 in authorize()
    ///
    /// Run authorizer's policies.
    ///
    /// Note: should only be called from authorizer()
    fn authorizerPolicies(authorizer: *Authorizer, errors: *std.ArrayList(AuthorizerError)) !?usize {
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
                        .allow => return policy_id,
                        .deny => {
                            try errors.append(.{ .denied_by_policy = .{ .deny_policy_id = policy_id } });
                            return null;
                        },
                    }
                }
            }
        }

        try errors.append(.{ .no_matching_policy = {} });

        return null;
    }

    /// Step 6 in authorize()
    ///
    /// Run checks in all other blocks.
    ///
    /// Note: should only be called from authorizer()
    fn blockChecks(authorizer: *Authorizer, errors: *std.ArrayList(AuthorizerError)) !void {
        const biscuit = authorizer.biscuit orelse return;

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
