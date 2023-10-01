const std = @import("std");
const schema = @import("biscuit-schema");
const SignedBlock = @import("signed_block.zig").SignedBlock;
const Proof = @import("proof.zig").Proof;

pub const MIN_SCHEMA_VERSION = 3;
pub const MAX_SCHEMA_VERSION = 3;

pub const SerializedBiscuit = struct {
    decoded_biscuit: schema.Biscuit,
    authority: SignedBlock,
    blocks: std.ArrayList(SignedBlock),
    proof: Proof,
    // root_key_id: ?u64,

    /// Initialise a SerializedBiscuit from the token's bytes and root public key.
    ///
    /// This decodes the toplevel-level biscuit format from protobuf and verifies
    /// the token.
    pub fn initFromBytes(allocator: std.mem.Allocator, bytes: []const u8, public_key: std.crypto.sign.Ed25519.PublicKey) !SerializedBiscuit {
        const b = try schema.decodeBiscuit(allocator, bytes);
        errdefer b.deinit();

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

    pub fn deinit(self: *SerializedBiscuit) void {
        self.blocks.deinit();
        self.decoded_biscuit.deinit();
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
    fn verify(self: *SerializedBiscuit, root_public_key: std.crypto.sign.Ed25519.PublicKey) !void {
        var pk = root_public_key;

        // Verify the authority block's signature
        {
            var verifier = try self.authority.signature.verifier(pk);

            verifier.update(self.authority.block);
            verifier.update(&self.authority.algorithmBuf());
            verifier.update(&self.authority.public_key.bytes);

            try verifier.verify();

            pk = self.authority.public_key;
        }

        // Verify the other blocks' signatures
        for (self.blocks.items) |*block| {
            var verifier = try block.signature.verifier(pk);

            verifier.update(block.block);
            verifier.update(&block.algorithmBuf());
            verifier.update(&block.public_key.bytes);

            try verifier.verify();

            pk = block.public_key;
        }

        // Check the proof
        switch (self.proof) {
            .next_secret => |next_secret| {
                if (!std.mem.eql(u8, &pk.bytes, &next_secret.publicKeyBytes())) {
                    return error.SecretKeyProofFailedMismatchedPublicKeys;
                }
            },
            .final_signature => |final_signature| {
                var last_block = if (self.blocks.items.len == 0) self.authority else self.blocks.items[self.blocks.items.len - 1];
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
    const public_key = try std.crypto.sign.Ed25519.PublicKey.fromBytes(public_key_mem);

    for (tokens) |token| {
        const bytes = try decode.urlSafeBase64ToBytes(allocator, token);
        defer allocator.free(bytes);

        var b = try SerializedBiscuit.initFromBytes(allocator, bytes, public_key);
        defer b.deinit();
    }
}
