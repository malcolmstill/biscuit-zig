const std = @import("std");
const mem = std.mem;
const Ed25519 = std.crypto.sign.Ed25519;
const schema = @import("biscuit-schema");
const SignedBlock = @import("signed_block.zig").SignedBlock;
const Proof = @import("proof.zig").Proof;

const ArenaAllocator = std.heap.ArenaAllocator;

const log = std.log.scoped(.serialized_biscuit);

pub const MIN_SCHEMA_VERSION = 3;
pub const MAX_SCHEMA_VERSION = 4;

pub const SerializedBiscuit = struct {
    allocator: mem.Allocator,
    arena_state: ?*ArenaAllocator,
    authority: SignedBlock,
    blocks: std.ArrayList(SignedBlock),
    proof: Proof,
    // root_key_id: ?u64,

    /// Initialise a SerializedBiscuit from the token's bytes and root public key.
    ///
    /// This decodes the toplevel-level biscuit format from protobuf and verifies the token.
    pub fn deserialize(allocator: mem.Allocator, bytes: []const u8, public_key: Ed25519.PublicKey) !SerializedBiscuit {
        const b = try schema.Biscuit.decode(bytes, allocator);
        defer b.deinit();

        var arena_state = try allocator.create(ArenaAllocator);
        arena_state.* = ArenaAllocator.init(allocator);
        errdefer {
            arena_state.deinit();
            allocator.destroy(arena_state);
        }

        const arena = arena_state.allocator();

        const authority = try SignedBlock.fromDecodedBlock(arena, b.authority orelse return error.ExpectedAuthorityBlock);
        const proof = try Proof.fromDecodedProof(b.proof orelse return error.ExpectedProof);

        var blocks = try std.ArrayList(SignedBlock).initCapacity(arena, b.blocks.items.len);

        for (b.blocks.items) |block| {
            const signed_block = try SignedBlock.fromDecodedBlock(arena, block);

            try blocks.append(signed_block);
        }

        var biscuit = SerializedBiscuit{
            .allocator = allocator,
            .arena_state = arena_state,
            .authority = authority,
            .blocks = blocks,
            .proof = proof,
        };

        try biscuit.verify(public_key);

        return biscuit;
    }

    /// Deinitialize serialized biscuit created from fromBytes.
    ///
    /// Panics if we call deinit on _derived_ SerializedBiscuit, i.e.
    /// a SerializedBiscuit we've called `fn seal` on
    pub fn deinit(serialized_block: *SerializedBiscuit) void {
        var arena_state = serialized_block.arena_state orelse unreachable;

        arena_state.deinit();
        serialized_block.allocator.destroy(arena_state);
    }

    /// Verify the token
    ///
    /// The verification process is:
    /// 1. Use the root public key to verify the data and public key
    ///    in the authority block.
    /// 2. Then loop through the other blocks using the public key
    ///    from the previous block to verify the current block's data
    ///    and public key.
    /// 3. When we run out of blocks we check the proof:
    ///    a) If the token is sealed, we take the signature
    ///       from the proof and verify the last block including
    ///       that block's signature.
    ///    b) If the token is not sealed we check the last block's
    ///       public key is the public key of the private key in the
    ///       the proof.
    fn verify(serialized_biscuit: *SerializedBiscuit, root_public_key: Ed25519.PublicKey) !void {
        log.debug("verify()", .{});
        defer log.debug("end verify()", .{});

        var pk = root_public_key;

        // Verify the authority block's signature
        {
            log.debug("verifying authority block", .{});
            errdefer log.debug("failed to verify authority block", .{});
            if (serialized_biscuit.authority.external_signature != null) return error.AuthorityBlockMustNotHaveExternalSignature;

            var verifier = try serialized_biscuit.authority.signature.verifier(pk);

            verifier.update(serialized_biscuit.authority.block);
            verifier.update(&serialized_biscuit.authority.algorithmBuf());
            verifier.update(&serialized_biscuit.authority.next_key.bytes);

            try verifier.verify();

            pk = serialized_biscuit.authority.next_key;
        }

        // Verify the other blocks' signatures
        for (serialized_biscuit.blocks.items, 1..) |*block, block_id| {
            // Verify the block signature
            {
                log.debug("verifying block {}", .{block_id});
                errdefer log.debug("failed to verify block {}", .{block_id});

                var verifier = try block.signature.verifier(pk);

                verifier.update(block.block);
                if (block.external_signature) |external_signature| {
                    verifier.update(&external_signature.signature.toBytes());
                }
                verifier.update(&block.algorithmBuf());
                verifier.update(&block.next_key.bytes);

                try verifier.verify();
            }

            // Verify the external signature (where one exists)
            if (block.external_signature) |external_signature| {
                log.debug("verifying external signature on block {}", .{block_id});
                errdefer log.debug("failed to verify external signature on block {}", .{block_id});

                var external_verifier = try external_signature.signature.verifier(external_signature.public_key);
                external_verifier.update(block.block);
                external_verifier.update(&block.algorithm2Buf());
                external_verifier.update(&pk.bytes);
                try external_verifier.verify();
            }

            pk = block.next_key;
        }

        // Check the proof

        log.debug("verifying proof", .{});
        switch (serialized_biscuit.proof) {
            .next_secret => |next_secret| {
                if (!std.mem.eql(u8, &pk.bytes, &next_secret.publicKeyBytes())) {
                    log.debug("failed to verify proof (sealed)", .{});
                    return error.SecretKeyProofFailedMismatchedPublicKeys;
                }
            },
            .final_signature => |final_signature| {
                errdefer log.debug("failed to verify proof (attenuated)", .{});

                var last_block = if (serialized_biscuit.blocks.items.len == 0) serialized_biscuit.authority else serialized_biscuit.blocks.items[serialized_biscuit.blocks.items.len - 1];
                var verifier = try final_signature.verifier(pk);

                verifier.update(last_block.block);
                verifier.update(&last_block.algorithmBuf());
                verifier.update(&last_block.next_key.bytes);
                verifier.update(&last_block.signature.toBytes());

                try verifier.verify();
            },
        }
    }

    /// Seal SerializedBiscuit
    ///
    /// Requires that the biscuit we're sealing has not been sealed (returns error.AlreadySealed otherwise).
    ///
    /// Use secret key from the proof to produce signature.
    ///
    /// Does not allocate (reuses memory of parent biscuit). Do not call `deinit` (which will panic).
    pub fn seal(serialized_biscuit: *SerializedBiscuit) !SerializedBiscuit {
        const secret_key = if (serialized_biscuit.proof == .next_secret) serialized_biscuit.proof.next_secret else return error.AlreadySealed;

        const final_block = if (serialized_biscuit.blocks.items.len == 0)
            serialized_biscuit.authority
        else
            serialized_biscuit.blocks.getLast();

        const key_pair = try Ed25519.KeyPair.fromSecretKey(secret_key);

        var signer = try Ed25519.KeyPair.signer(key_pair, null);

        signer.update(final_block.block);
        signer.update(&algorithm());
        signer.update(&final_block.next_key.bytes);
        signer.update(&final_block.signature.toBytes());

        const signature = signer.finalize();

        return .{
            .allocator = serialized_biscuit.allocator,
            .arena_state = null,
            .authority = serialized_biscuit.authority,
            .blocks = serialized_biscuit.blocks,
            .proof = .{ .final_signature = signature },
        };
    }

    pub fn serialize(serialized_biscuit: *SerializedBiscuit, allocator: mem.Allocator) ![]const u8 {
        const authority: schema.SignedBlock = .{
            .block = schema.ManagedString.managed(serialized_biscuit.authority.block),
            .nextKey = .{
                .algorithm = schema.PublicKey.Algorithm.Ed25519,
                .key = schema.ManagedString.managed(&serialized_biscuit.authority.next_key.bytes),
            },
            .signature = schema.ManagedString.managed(&serialized_biscuit.authority.signature.toBytes()),
            .externalSignature = null,
        };

        var blocks = std.ArrayList(schema.SignedBlock).init(serialized_biscuit.allocator);
        defer blocks.deinit();

        for (serialized_biscuit.blocks.items) |b| {
            const block: schema.SignedBlock = .{
                .block = schema.ManagedString.managed(b.block),
                .nextKey = .{
                    .algorithm = schema.PublicKey.Algorithm.Ed25519,
                    .key = schema.ManagedString.managed(&b.next_key.bytes),
                },
                .signature = schema.ManagedString.managed(&b.signature.toBytes()),
            };

            try blocks.append(block);
        }

        return try schema.Biscuit.encode(.{
            .authority = authority,
            .blocks = blocks,
            .proof = .{
                .Content = switch (serialized_biscuit.proof) {
                    .next_secret => .{ .nextSecret = schema.ManagedString.managed(&serialized_biscuit.proof.next_secret.bytes) },
                    .final_signature => .{ .finalSignature = schema.ManagedString.managed(&serialized_biscuit.proof.final_signature.toBytes()) },
                },
            },
        }, allocator);
    }
};

// FIXME this is duplicated
pub fn algorithm() [4]u8 {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, buf[0..], @as(u32, @bitCast(@intFromEnum(schema.PublicKey.Algorithm.Ed25519))), .little);
    return buf;
}

test {
    const decode = @import("decode.zig");
    const testing = std.testing;

    // Key
    // private: 83e03c958f83085923f3cd091bab3c3b33a0c7f93f44889739fdb6c6fdb26f5b
    // public:  49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da
    const unsealed_tokens: [2][]const u8 = .{
        "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCyIiCiCyJCJ0e-e00kyM_3O6IbbftDeYAnkoI8-G1x06NK283w==",
        "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCxp9ChMKBGFiY2QYAyIJCgcIAhIDGIEIEiQIABIgkJwspMgTz4pW4hQ_Tkua7EdZ5AajdxV35q42IyXzAt0aQBH3kiLfP06W0dPlQeuxgLU26ssrjoK-v1vvw0dzQ2BtaQjPs8eKhsowhFCjQ6nnhSP0p7v4TaJHWeO2fPsbUQwiIgogeuDcbq6waTZ1HpYt_zYNtAy02gbnjV-5-juc9sdXNJg=",
    };

    const sealed_tokens: [1][]const u8 = .{
        "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCxp9ChMKBGFiY2QYAyIJCgcIAhIDGIEIEiQIABIgkJwspMgTz4pW4hQ_Tkua7EdZ5AajdxV35q42IyXzAt0aQBH3kiLfP06W0dPlQeuxgLU26ssrjoK-v1vvw0dzQ2BtaQjPs8eKhsowhFCjQ6nnhSP0p7v4TaJHWeO2fPsbUQwiQhJAfNph7vZIL6WSLwOCmMHkwb4OmCc5s7EByizwq6HZOF04SRwCF8THWcNImPj-5xWOuI3zVdxg11Qr6d0c5yxuCw==",
    };

    var public_key_mem: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&public_key_mem, "49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da");
    const public_key = try Ed25519.PublicKey.fromBytes(public_key_mem);

    for (unsealed_tokens) |token| {
        const bytes = try decode.urlSafeBase64ToBytes(testing.allocator, token);
        defer testing.allocator.free(bytes);

        var b = try SerializedBiscuit.deserialize(testing.allocator, bytes, public_key);
        defer b.deinit();

        {
            const encoded_token = try b.serialize(testing.allocator);
            defer testing.allocator.free(encoded_token);

            const encoded = try decode.bytesToUrlSafeBase64(testing.allocator, encoded_token);
            defer testing.allocator.free(encoded);

            std.debug.print("before sealing = {s}\n", .{encoded});
        }

        // We should be able to seal the tokens
        var sealed = try b.seal();
        {
            const encoded_token = try sealed.serialize(testing.allocator);
            defer testing.allocator.free(encoded_token);

            const encoded = try decode.bytesToUrlSafeBase64(testing.allocator, encoded_token);
            defer testing.allocator.free(encoded);

            std.debug.print("after sealing = {s}\n", .{encoded});
        }

        // Trying to seal again should fail
        _ = sealed.seal() catch |err| switch (err) {
            error.AlreadySealed => continue,
            else => return err,
        };
    }

    for (sealed_tokens) |token| {
        const bytes = try decode.urlSafeBase64ToBytes(testing.allocator, token);
        defer testing.allocator.free(bytes);

        var b = try SerializedBiscuit.deserialize(testing.allocator, bytes, public_key);
        defer b.deinit();

        // The tokens are already sealed so should fail
        _ = b.seal() catch |err| switch (err) {
            error.AlreadySealed => {},
            else => return err,
        };

        const encoded_token = try b.serialize(testing.allocator);
        defer testing.allocator.free(encoded_token);

        const encoded = try decode.bytesToUrlSafeBase64(testing.allocator, encoded_token);
        defer testing.allocator.free(encoded);

        std.debug.print("was already sealed = {s}", .{encoded});
    }
}
