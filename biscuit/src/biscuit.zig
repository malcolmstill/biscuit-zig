const std = @import("std");
const mem = std.mem;
const Ed25519 = std.crypto.sign.Ed25519;
const Authorizer = @import("authorizer.zig").Authorizer;
const Block = @import("block.zig").Block;
const SymbolTable = @import("biscuit-datalog").SymbolTable;
const World = @import("biscuit-datalog").world.World;
const SerializedBiscuit = @import("biscuit-format").SerializedBiscuit;

pub const Biscuit = struct {
    serialized: SerializedBiscuit,
    authority: Block,
    blocks: std.ArrayList(Block),
    symbols: SymbolTable,
    public_key_to_block_id: std.AutoHashMap(usize, std.ArrayList(usize)),

    pub fn fromBytes(allocator: mem.Allocator, token_bytes: []const u8, root_public_key: Ed25519.PublicKey) !Biscuit {
        var serialized = try SerializedBiscuit.fromBytes(allocator, token_bytes, root_public_key);
        errdefer serialized.deinit();

        // For each block we will temporarily store the external public key (where it exists).
        var block_external_keys = try std.ArrayList(?Ed25519.PublicKey).initCapacity(allocator, 1 + serialized.blocks.items.len);
        defer block_external_keys.deinit();
        defer std.debug.assert(block_external_keys.items.len == 1 + serialized.blocks.items.len);

        var token_symbols = SymbolTable.init("biscuit", allocator);

        const authority = try Block.fromBytes(allocator, serialized.authority, &token_symbols);
        try block_external_keys.append(null);
        std.debug.print("authority block =\n{any}\n", .{authority});

        var blocks = std.ArrayList(Block).init(allocator);
        for (serialized.blocks.items) |signed_block| {
            const block = try Block.fromBytes(allocator, signed_block, &token_symbols);
            std.debug.print("non-authority block =\n{any}\n", .{block});

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
                std.debug.print("public_key_to_block_id: public key id = {}, block_ids = {any}\n", .{ entry.key_ptr.*, entry.value_ptr.items });
            }
        }

        return .{
            .serialized = serialized,
            .authority = authority,
            .blocks = blocks,
            .symbols = token_symbols,
            .public_key_to_block_id = public_key_to_block_id,
        };
    }

    pub fn deinit(biscuit: *Biscuit) void {
        for (biscuit.blocks.items) |*block| {
            block.deinit();
        }
        biscuit.blocks.deinit();
        biscuit.authority.deinit();

        // FIXME: think about lifetimes for public_key_to_block_id
        var it = biscuit.public_key_to_block_id.valueIterator();
        while (it.next()) |block_ids| {
            block_ids.deinit();
        }
        biscuit.public_key_to_block_id.deinit();

        biscuit.serialized.deinit();
    }

    pub fn authorizer(biscuit: *Biscuit, allocator: std.mem.Allocator) !Authorizer {
        return try Authorizer.init(allocator, biscuit.*);
    }
};

test {
    const decode = @import("biscuit-format").decode;
    const testing = std.testing;
    var allocator = testing.allocator;

    // Key
    // private: 83e03c958f83085923f3cd091bab3c3b33a0c7f93f44889739fdb6c6fdb26f5b
    // public:  49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da
    const tokens: [6][]const u8 = .{
        "EpACCqUBCgFhCgFiCgFjCgFkCgdtYWxjb2xtCgRqb2huCgEwCgExGAMiCQoHCAISAxiACCIJCgcIAhIDGIEIIgkKBwgCEgMYgggiCQoHCAISAxiDCCIOCgwIBxIDGIQIEgMYgAgiDgoMCAcSAxiECBIDGIIIIg4KDAgHEgMYhQgSAxiBCCokCgsIBBIDCIYIEgIYABIHCAISAwiGCBIMCAcSAwiHCBIDCIYIEiQIABIgnSmYbzjEQ2n09JhlmGs6j_ZhKYgj3nRkEMdGJJqQimwaQD4UTmEDtu5G8kRJZbNTcNuGg8Izb5ja2BSV3Rlkv1Y6IV_Nd00sIstiEq1RPH-M8xfFdWaW1gixH54Y5deHzwYiIgogFmxoQyXPm8ccNBKKh0hv8eRwrYjS56s0OTQWZShHoVw=",
        "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCyIiCiCyJCJ0e-e00kyM_3O6IbbftDeYAnkoI8-G1x06NK283w==",
        "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCxp9ChMKBGFiY2QYAyIJCgcIAhIDGIEIEiQIABIgkJwspMgTz4pW4hQ_Tkua7EdZ5AajdxV35q42IyXzAt0aQBH3kiLfP06W0dPlQeuxgLU26ssrjoK-v1vvw0dzQ2BtaQjPs8eKhsowhFCjQ6nnhSP0p7v4TaJHWeO2fPsbUQwiIgogeuDcbq6waTZ1HpYt_zYNtAy02gbnjV-5-juc9sdXNJg=",
        "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCxp9ChMKBGFiY2QYAyIJCgcIAhIDGIEIEiQIABIgkJwspMgTz4pW4hQ_Tkua7EdZ5AajdxV35q42IyXzAt0aQBH3kiLfP06W0dPlQeuxgLU26ssrjoK-v1vvw0dzQ2BtaQjPs8eKhsowhFCjQ6nnhSP0p7v4TaJHWeO2fPsbUQwiQhJAfNph7vZIL6WSLwOCmMHkwb4OmCc5s7EByizwq6HZOF04SRwCF8THWcNImPj-5xWOuI3zVdxg11Qr6d0c5yxuCw==",
        "Eq4BCkQKBDEyMzQKBmRvdWJsZQoBeAoBeRgDIgkKBwgKEgMYgAgqIQoNCIEIEgMIgggSAwiDCBIHCAoSAwiCCBIHCAoSAwiDCBIkCAASIHJpGIZ74pbiyybTMn2zrCqHf5t7ZUV9tMnT5xkLq5rsGkCnAznWzInI1-kJGuRUgluqmr96bJwKG3RT3iceJ3kzzzBWGT5dEFXYyIqWxpLDk9Qoy-AWpwS49SA5ynGKb5UGIiIKIESr7u80iDgTstDzVk6obTp6zJmVfBqNcBNtwjOQyVOr",
        // Token with check in authority block (that should pass):
        "Eq8CCsQBCgFhCgFiCgFjCgFkCgdtYWxjb2xtCgRqb2huCgExCgEwGAMiCQoHCAISAxiACCIJCgcIAhIDGIEIIgkKBwgCEgMYgggiCQoHCAISAxiDCCIOCgwIBxIDGIQIEgMYgAgiDgoMCAcSAxiECBIDGIIIIg4KDAgHEgMYhQgSAxiBCCopChAIBBIDCIYIEgMIhwgSAhgAEgcIAhIDCIcIEgwIBxIDCIYIEgMIhwgyGAoWCgIIGxIQCAQSAxiECBIDGIAIEgIYABIkCAASIGMjO8ucGcxZst9FINaf7EmOsWh8kW039G8TeV9BYIhTGkCrqL87m-bqFGxmNUobqmw7iWHViQN6DRDksNCJMfkC1zvwVdSZwZwtgQmr90amKCPjdXCD0bev53dNyIanRPoPIiIKIMAzV_GYyKdq9NeJ80-E-bGqGYD4nLXCDRnGpzThEglb",
    };

    var public_key_mem: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&public_key_mem, "49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da");
    const public_key = try Ed25519.PublicKey.fromBytes(public_key_mem);

    for (tokens) |token| {
        const bytes = try decode.urlSafeBase64ToBytes(allocator, token);
        defer allocator.free(bytes);

        var b = try Biscuit.fromBytes(allocator, bytes, public_key);
        defer b.deinit();

        var a = b.authorizer(allocator);
        defer a.deinit();

        try a.authorize();
    }
}

test "Tokens that should fail to validate" {
    const decode = @import("biscuit-format").decode;
    const testing = std.testing;
    var allocator = testing.allocator;

    // Key
    // private: 83e03c958f83085923f3cd091bab3c3b33a0c7f93f44889739fdb6c6fdb26f5b
    // public:  49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da
    const tokens: [1][]const u8 = .{
        // Token with check (in authority block) that should pass and a check (in the authority block) that should fail
        "Es8CCuQBCgFhCgFiCgFjCgFkCgdtYWxjb2xtCgRqb2huCgExCgEwCgRlcmljGAMiCQoHCAISAxiACCIJCgcIAhIDGIEIIgkKBwgCEgMYgggiCQoHCAISAxiDCCIOCgwIBxIDGIQIEgMYgAgiDgoMCAcSAxiECBIDGIIIIg4KDAgHEgMYhQgSAxiBCCopChAIBBIDCIYIEgMIhwgSAhgAEgcIAhIDCIcIEgwIBxIDCIYIEgMIhwgyGAoWCgIIGxIQCAQSAxiECBIDGIAIEgIYADIYChYKAggbEhAIBBIDGIgIEgMYgwgSAhgBEiQIABIgbACOx_sohlqZpzEwG23cKbN5wsUseLHHPt1tM8zVilIaQHMBawtn2NIa0jkJ38FR-uw7ncEAP1Qp_g6zctajVDLo1eMhBzjBO6lCddBHyEgvwZ9bufXYClHAwEZQyGKeEgwiIgogCfqPElEy9fyO6r-E5GT9-io3bhhSSe9wVAn6x6fsM7k=",
    };

    var public_key_mem: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&public_key_mem, "49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da");
    const public_key = try Ed25519.PublicKey.fromBytes(public_key_mem);

    for (tokens) |token| {
        const bytes = try decode.urlSafeBase64ToBytes(allocator, token);
        defer allocator.free(bytes);

        var b = try Biscuit.fromBytes(allocator, bytes, public_key);
        defer b.deinit();

        var a = b.authorizer(allocator);
        defer a.deinit();

        try testing.expectError(error.AuthorizationFailed, a.authorize());
    }
}
