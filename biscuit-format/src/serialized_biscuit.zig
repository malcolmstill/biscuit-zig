const std = @import("std");
const mem = std.mem;
const Ed25519 = std.crypto.sign.Ed25519;
const schema = @import("biscuit-schema");
const SignedBlock = @import("signed_block.zig").SignedBlock;
const Proof = @import("proof.zig").Proof;

const log = std.log.scoped(.serialized_biscuit);

pub const MIN_SCHEMA_VERSION = 3;
pub const MAX_SCHEMA_VERSION = 4;

pub const SerializedBiscuit = struct {
    decoded_biscuit: schema.Biscuit,
    authority: SignedBlock,
    blocks: std.ArrayList(SignedBlock),
    proof: Proof,
    // root_key_id: ?u64,

    // FIXME: should this take a SymbolTable?
    /// Initialise a SerializedBiscuit from the token's bytes and root public key.
    ///
    /// This decodes the toplevel-level biscuit format from protobuf and verifies
    /// the token.
    pub fn fromBytes(allocator: mem.Allocator, bytes: []const u8, public_key: Ed25519.PublicKey) !SerializedBiscuit {
        const b = try schema.decodeBiscuit(allocator, bytes);
        errdefer b.deinit();

        // FIXME: Add textual public keys to symbols

        const authority = try SignedBlock.fromDecodedBlock(b.authority orelse return error.ExpectedAuthorityBlock);
        const proof = try Proof.fromDecodedProof(b.proof orelse return error.ExpectedProof);

        var blocks = std.ArrayList(SignedBlock).init(allocator);
        errdefer blocks.deinit();

        for (b.blocks.items) |block| {
            const signed_block = try SignedBlock.fromDecodedBlock(block);
            try blocks.append(signed_block);
        }

        var biscuit = SerializedBiscuit{
            .decoded_biscuit = b,
            .authority = authority,
            .blocks = blocks,
            .proof = proof,
        };

        try biscuit.verify(public_key);

        return biscuit;
    }

    pub fn deinit(serialized_block: *SerializedBiscuit) void {
        serialized_block.blocks.deinit();
        serialized_block.decoded_biscuit.deinit();
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
            verifier.update(&serialized_biscuit.authority.public_key.bytes);

            try verifier.verify();

            pk = serialized_biscuit.authority.public_key;
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
                verifier.update(&block.public_key.bytes);

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

            pk = block.public_key;
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
                verifier.update(&last_block.public_key.bytes);
                verifier.update(&last_block.signature.toBytes());

                try verifier.verify();
            },
        }
    }
};

test {
    const decode = @import("decode.zig");
    const testing = std.testing;
    var allocator = testing.allocator;

    // Key
    // private: 83e03c958f83085923f3cd091bab3c3b33a0c7f93f44889739fdb6c6fdb26f5b
    // public:  49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da
    const tokens: [3][]const u8 = .{
        "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCyIiCiCyJCJ0e-e00kyM_3O6IbbftDeYAnkoI8-G1x06NK283w==",
        "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCxp9ChMKBGFiY2QYAyIJCgcIAhIDGIEIEiQIABIgkJwspMgTz4pW4hQ_Tkua7EdZ5AajdxV35q42IyXzAt0aQBH3kiLfP06W0dPlQeuxgLU26ssrjoK-v1vvw0dzQ2BtaQjPs8eKhsowhFCjQ6nnhSP0p7v4TaJHWeO2fPsbUQwiIgogeuDcbq6waTZ1HpYt_zYNtAy02gbnjV-5-juc9sdXNJg=",
        "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCxp9ChMKBGFiY2QYAyIJCgcIAhIDGIEIEiQIABIgkJwspMgTz4pW4hQ_Tkua7EdZ5AajdxV35q42IyXzAt0aQBH3kiLfP06W0dPlQeuxgLU26ssrjoK-v1vvw0dzQ2BtaQjPs8eKhsowhFCjQ6nnhSP0p7v4TaJHWeO2fPsbUQwiQhJAfNph7vZIL6WSLwOCmMHkwb4OmCc5s7EByizwq6HZOF04SRwCF8THWcNImPj-5xWOuI3zVdxg11Qr6d0c5yxuCw==",
    };

    var public_key_mem: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&public_key_mem, "49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da");
    const public_key = try Ed25519.PublicKey.fromBytes(public_key_mem);

    for (tokens) |token| {
        const bytes = try decode.urlSafeBase64ToBytes(allocator, token);
        defer allocator.free(bytes);

        var b = try SerializedBiscuit.fromBytes(allocator, bytes, public_key);
        defer b.deinit();
    }
}
