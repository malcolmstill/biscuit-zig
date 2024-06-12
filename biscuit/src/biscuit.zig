const std = @import("std");
const mem = std.mem;
const Ed25519 = std.crypto.sign.Ed25519;
const Authorizer = @import("authorizer.zig").Authorizer;
const AuthorizerError = @import("authorizer.zig").AuthorizerError;
const Block = @import("block.zig").Block;
const SymbolTable = @import("biscuit-datalog").SymbolTable;
const World = @import("biscuit-datalog").world.World;
const SerializedBiscuit = @import("biscuit-format").SerializedBiscuit;
const builder = @import("biscuit-builder");

const ArenaAllocator = std.heap.ArenaAllocator;

const log = std.log.scoped(.biscuit);

pub const Biscuit = struct {
    allocator: mem.Allocator,
    arena_state: *ArenaAllocator,
    serialized: SerializedBiscuit,
    authority: Block,
    blocks: std.ArrayList(Block),
    symbols: SymbolTable,
    public_key_to_block_id: std.AutoHashMap(usize, std.ArrayList(usize)),

    pub fn new(allocator: mem.Allocator, root_secret_key: Ed25519.SecretKey) !Biscuit {
        _ = root_secret_key;
        _ = allocator;
        unreachable;
    }

    /// Deserialize a token from byte array into a Biscuit.
    pub fn fromBytes(allocator: mem.Allocator, token_bytes: []const u8, root_public_key: Ed25519.PublicKey) !Biscuit {
        var serialized = try SerializedBiscuit.deserialize(allocator, token_bytes, root_public_key);
        errdefer serialized.deinit();

        // The calls to Block.fromBytes further down allocate into this arena. After this function (Biscuit.fromBytes)
        // returns, we create new rules, facts, terms etc. from those generated in Block.fromBytes. If those, use
        // e.g. clone, that clone will be using the allocator used here which would have a reference to the ArenaAllocator
        // stack as it was on the stack which would now be invalid.
        //
        // What we do here instead is create the ArenaAllocator on the heap such that is has a stable address.
        //
        // TODO: alternatively we could require this function takes a *ArenaAllocator (in place or in addition to
        //       allocator: mem.Allocator) and not deal with this allocation.
        var arena_state = try allocator.create(ArenaAllocator);
        arena_state.* = ArenaAllocator.init(allocator);
        errdefer {
            arena_state.deinit();
            allocator.destroy(arena_state);
        }

        const arena = arena_state.allocator();

        // For each block we will temporarily store the external public key (where it exists).
        var block_external_keys = try std.ArrayList(?Ed25519.PublicKey).initCapacity(allocator, 1 + serialized.blocks.items.len);
        defer block_external_keys.deinit();
        defer std.debug.assert(block_external_keys.items.len == 1 + serialized.blocks.items.len);

        var token_symbols = SymbolTable.init("biscuit", allocator);

        const authority = try Block.fromBytes(arena, serialized.authority, &token_symbols);
        try block_external_keys.append(null);
        log.debug("authority {any}", .{authority});

        var blocks = try std.ArrayList(Block).initCapacity(arena, serialized.blocks.items.len);
        for (serialized.blocks.items) |signed_block| {
            const block = try Block.fromBytes(arena, signed_block, &token_symbols);
            log.debug("{any}", .{block});

            const external_key = if (signed_block.external_signature) |external_signature| external_signature.public_key else null;
            try block_external_keys.append(external_key);

            try blocks.append(block);
        }

        // Build map from public key (rather the symbol index associated with the public key) to block id.
        // Multiple blocks may be signed by the same external key and so the mapping is from the public
        // key to a list of block ids.
        var public_key_to_block_id = std.AutoHashMap(usize, std.ArrayList(usize)).init(allocator);
        for (block_external_keys.items, 0..) |block_external_key, block_id| {
            const key = block_external_key orelse continue;

            const key_index = try token_symbols.insertPublicKey(key);
            if (public_key_to_block_id.getPtr(key_index)) |list_ptr| {
                try list_ptr.append(block_id);
            } else {
                var list = std.ArrayList(usize).init(allocator);
                try list.append(block_id);
                try public_key_to_block_id.put(key_index, list);
            }
        }

        {
            var it = public_key_to_block_id.iterator();
            while (it.next()) |entry| {
                log.debug("public_key_to_block_id: public key id = {}, block_ids = {any}", .{ entry.key_ptr.*, entry.value_ptr.items });
            }
        }

        return .{
            .allocator = allocator,
            .arena_state = arena_state,
            .serialized = serialized,
            .authority = authority,
            .blocks = blocks,
            .symbols = token_symbols,
            .public_key_to_block_id = public_key_to_block_id,
        };
    }

    /// Deinitialize the biscuit
    pub fn deinit(biscuit: *Biscuit) void {
        biscuit.arena_state.deinit(); // Free all the facts, predicates, etc.

        var it = biscuit.public_key_to_block_id.valueIterator();
        while (it.next()) |block_ids| {
            block_ids.deinit();
        }
        biscuit.public_key_to_block_id.deinit();

        biscuit.symbols.deinit();
        biscuit.serialized.deinit();

        biscuit.allocator.destroy(biscuit.arena_state);
    }

    pub fn authorizer(biscuit: *Biscuit) !Authorizer {
        return try Authorizer.init(biscuit.allocator, biscuit.arena_state.allocator(), biscuit);
    }

    /// Append block to biscuit
    ///
    /// This will be the auhtority block in the case the biscuit is empty otherwise
    /// will append a non-authority block.
    pub fn append(biscuit: *Biscuit, block: builder.Block) !void {
        _ = block;
        _ = biscuit;
        unreachable;
    }

    /// Seal biscuit
    pub fn seal(biscuit: *Biscuit) !Biscuit {
        return .{
            .allocator = biscuit.allocator,
            .arena_state = biscuit.arena_state,
            .serialized = try biscuit.serialized.seal(),
            .authority = biscuit.authority,
            .blocks = biscuit.blocks,
            .symbols = biscuit.symbols,
            .public_key_to_block_id = biscuit.public_key_to_block_id,
        };
    }

    /// Serialize biscuit to byte array
    pub fn serialize(biscuit: *Biscuit) ![]const u8 {
        _ = biscuit;
        unreachable;
    }
};

// test {
//     const decode = @import("biscuit-format").decode;
//     const testing = std.testing;
//     var allocator = testing.allocator;

//     // Key
//     // private: 83e03c958f83085923f3cd091bab3c3b33a0c7f93f44889739fdb6c6fdb26f5b
//     // public:  49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da
//     const tokens: [6][]const u8 = .{
//         "EpACCqUBCgFhCgFiCgFjCgFkCgdtYWxjb2xtCgRqb2huCgEwCgExGAMiCQoHCAISAxiACCIJCgcIAhIDGIEIIgkKBwgCEgMYgggiCQoHCAISAxiDCCIOCgwIBxIDGIQIEgMYgAgiDgoMCAcSAxiECBIDGIIIIg4KDAgHEgMYhQgSAxiBCCokCgsIBBIDCIYIEgIYABIHCAISAwiGCBIMCAcSAwiHCBIDCIYIEiQIABIgnSmYbzjEQ2n09JhlmGs6j_ZhKYgj3nRkEMdGJJqQimwaQD4UTmEDtu5G8kRJZbNTcNuGg8Izb5ja2BSV3Rlkv1Y6IV_Nd00sIstiEq1RPH-M8xfFdWaW1gixH54Y5deHzwYiIgogFmxoQyXPm8ccNBKKh0hv8eRwrYjS56s0OTQWZShHoVw=",
//         "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCyIiCiCyJCJ0e-e00kyM_3O6IbbftDeYAnkoI8-G1x06NK283w==",
//         "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCxp9ChMKBGFiY2QYAyIJCgcIAhIDGIEIEiQIABIgkJwspMgTz4pW4hQ_Tkua7EdZ5AajdxV35q42IyXzAt0aQBH3kiLfP06W0dPlQeuxgLU26ssrjoK-v1vvw0dzQ2BtaQjPs8eKhsowhFCjQ6nnhSP0p7v4TaJHWeO2fPsbUQwiIgogeuDcbq6waTZ1HpYt_zYNtAy02gbnjV-5-juc9sdXNJg=",
//         "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCxp9ChMKBGFiY2QYAyIJCgcIAhIDGIEIEiQIABIgkJwspMgTz4pW4hQ_Tkua7EdZ5AajdxV35q42IyXzAt0aQBH3kiLfP06W0dPlQeuxgLU26ssrjoK-v1vvw0dzQ2BtaQjPs8eKhsowhFCjQ6nnhSP0p7v4TaJHWeO2fPsbUQwiQhJAfNph7vZIL6WSLwOCmMHkwb4OmCc5s7EByizwq6HZOF04SRwCF8THWcNImPj-5xWOuI3zVdxg11Qr6d0c5yxuCw==",
//         "Eq4BCkQKBDEyMzQKBmRvdWJsZQoBeAoBeRgDIgkKBwgKEgMYgAgqIQoNCIEIEgMIgggSAwiDCBIHCAoSAwiCCBIHCAoSAwiDCBIkCAASIHJpGIZ74pbiyybTMn2zrCqHf5t7ZUV9tMnT5xkLq5rsGkCnAznWzInI1-kJGuRUgluqmr96bJwKG3RT3iceJ3kzzzBWGT5dEFXYyIqWxpLDk9Qoy-AWpwS49SA5ynGKb5UGIiIKIESr7u80iDgTstDzVk6obTp6zJmVfBqNcBNtwjOQyVOr",
//         // Token with check in authority block (that should pass):
//         "Eq8CCsQBCgFhCgFiCgFjCgFkCgdtYWxjb2xtCgRqb2huCgExCgEwGAMiCQoHCAISAxiACCIJCgcIAhIDGIEIIgkKBwgCEgMYgggiCQoHCAISAxiDCCIOCgwIBxIDGIQIEgMYgAgiDgoMCAcSAxiECBIDGIIIIg4KDAgHEgMYhQgSAxiBCCopChAIBBIDCIYIEgMIhwgSAhgAEgcIAhIDCIcIEgwIBxIDCIYIEgMIhwgyGAoWCgIIGxIQCAQSAxiECBIDGIAIEgIYABIkCAASIGMjO8ucGcxZst9FINaf7EmOsWh8kW039G8TeV9BYIhTGkCrqL87m-bqFGxmNUobqmw7iWHViQN6DRDksNCJMfkC1zvwVdSZwZwtgQmr90amKCPjdXCD0bev53dNyIanRPoPIiIKIMAzV_GYyKdq9NeJ80-E-bGqGYD4nLXCDRnGpzThEglb",
//     };

//     var public_key_mem: [32]u8 = undefined;
//     _ = try std.fmt.hexToBytes(&public_key_mem, "49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da");
//     const public_key = try Ed25519.PublicKey.fromBytes(public_key_mem);

//     for (tokens) |token| {
//         const bytes = try decode.urlSafeBase64ToBytes(allocator, token);
//         defer allocator.free(bytes);

//         var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
//         defer arena_state.deinit();

//         const arena = arena_state.allocator();

//         var b = try Biscuit.fromBytes(arena, bytes, public_key);
//         defer b.deinit();

//         var a = try b.authorizer(arena);
//         defer a.deinit();

//         var errors = std.ArrayList(AuthorizerError).init(allocator);
//         defer errors.deinit();

//         errdefer std.debug.print("error = {any}\n", .{errors.items});

//         _ = try a.authorize(&errors);
//     }
// }

// test "Tokens that should fail to validate" {
//     const decode = @import("biscuit-format").decode;
//     const testing = std.testing;
//     var allocator = testing.allocator;

//     // Key
//     // private: 83e03c958f83085923f3cd091bab3c3b33a0c7f93f44889739fdb6c6fdb26f5b
//     // public:  49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da
//     const tokens: [1][]const u8 = .{
//         // Token with check (in authority block) that should pass and a check (in the authority block) that should fail
//         "Es8CCuQBCgFhCgFiCgFjCgFkCgdtYWxjb2xtCgRqb2huCgExCgEwCgRlcmljGAMiCQoHCAISAxiACCIJCgcIAhIDGIEIIgkKBwgCEgMYgggiCQoHCAISAxiDCCIOCgwIBxIDGIQIEgMYgAgiDgoMCAcSAxiECBIDGIIIIg4KDAgHEgMYhQgSAxiBCCopChAIBBIDCIYIEgMIhwgSAhgAEgcIAhIDCIcIEgwIBxIDCIYIEgMIhwgyGAoWCgIIGxIQCAQSAxiECBIDGIAIEgIYADIYChYKAggbEhAIBBIDGIgIEgMYgwgSAhgBEiQIABIgbACOx_sohlqZpzEwG23cKbN5wsUseLHHPt1tM8zVilIaQHMBawtn2NIa0jkJ38FR-uw7ncEAP1Qp_g6zctajVDLo1eMhBzjBO6lCddBHyEgvwZ9bufXYClHAwEZQyGKeEgwiIgogCfqPElEy9fyO6r-E5GT9-io3bhhSSe9wVAn6x6fsM7k=",
//     };

//     var public_key_mem: [32]u8 = undefined;
//     _ = try std.fmt.hexToBytes(&public_key_mem, "49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da");
//     const public_key = try Ed25519.PublicKey.fromBytes(public_key_mem);

//     for (tokens) |token| {
//         const bytes = try decode.urlSafeBase64ToBytes(allocator, token);
//         defer allocator.free(bytes);

//         var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
//         defer arena_state.deinit();

//         const arena = arena_state.allocator();

//         var b = try Biscuit.fromBytes(arena, bytes, public_key);
//         defer b.deinit();

//         var a = try b.authorizer(arena);
//         defer a.deinit();

//         var errors = std.ArrayList(AuthorizerError).init(allocator);
//         defer errors.deinit();

//         try testing.expectError(error.AuthorizationFailed, a.authorize(&errors));
//     }
// }

// test {
//     const decode = @import("biscuit-format").decode;
//     const testing = std.testing;
//     var allocator = testing.allocator;

//     // Key
//     // private: 83e03c958f83085923f3cd091bab3c3b33a0c7f93f44889739fdb6c6fdb26f5b
//     // public:  49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da
//     const token = "EpACCqUBCgFhCgFiCgFjCgFkCgdtYWxjb2xtCgRqb2huCgEwCgExGAMiCQoHCAISAxiACCIJCgcIAhIDGIEIIgkKBwgCEgMYgggiCQoHCAISAxiDCCIOCgwIBxIDGIQIEgMYgAgiDgoMCAcSAxiECBIDGIIIIg4KDAgHEgMYhQgSAxiBCCokCgsIBBIDCIYIEgIYABIHCAISAwiGCBIMCAcSAwiHCBIDCIYIEiQIABIgnSmYbzjEQ2n09JhlmGs6j_ZhKYgj3nRkEMdGJJqQimwaQD4UTmEDtu5G8kRJZbNTcNuGg8Izb5ja2BSV3Rlkv1Y6IV_Nd00sIstiEq1RPH-M8xfFdWaW1gixH54Y5deHzwYiIgogFmxoQyXPm8ccNBKKh0hv8eRwrYjS56s0OTQWZShHoVw=";

//     var public_key_mem: [32]u8 = undefined;
//     _ = try std.fmt.hexToBytes(&public_key_mem, "49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da");
//     const public_key = try Ed25519.PublicKey.fromBytes(public_key_mem);

//     const bytes = try decode.urlSafeBase64ToBytes(allocator, token);
//     defer allocator.free(bytes);

//     var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
//     defer arena_state.deinit();

//     const arena = arena_state.allocator();

//     var b = try Biscuit.fromBytes(arena, bytes, public_key);
//     defer b.deinit();

//     var block = builder.Block.init(arena);
//     try block.addFact("read(\"file1\")");

//     try b.append(block);
//     _ = try b.serialize();
// }
