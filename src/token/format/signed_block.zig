const std = @import("std");
const pb = @import("protobuf");
const schema = @import("schema.pb.zig");

// Expected Ed25519 public key / signature lengths
const expected_public_key_length = 32;
const expected_signature_length = 64;

pub const SignedBlock = struct {
    block: []const u8,
    algorithm: schema.PublicKey.Algorithm,
    signature: std.crypto.sign.Ed25519.Signature,
    public_key: std.crypto.sign.Ed25519.PublicKey,

    pub fn fromDeserializedBlock(block: schema.SignedBlock) !SignedBlock {
        const block_signature = block.signature.getSlice();

        const next_key = block.nextKey orelse return error.ExpectedNextKey;
        const algorithm = next_key.algorithm;
        const block_public_key = next_key.key.getSlice();

        if (block_signature.len != expected_signature_length) return error.IncorrectBlockSignatureLength;
        if (block_public_key.len != expected_public_key_length) return error.IncorrectBlockNextKeyLength;

        var sign_buf: [64]u8 = undefined;
        @memcpy(&sign_buf, block_signature);
        const signature = std.crypto.sign.Ed25519.Signature.fromBytes(sign_buf);

        var pubkey_buf: [32]u8 = undefined;
        @memcpy(&pubkey_buf, block_public_key);
        const public_key = try std.crypto.sign.Ed25519.PublicKey.fromBytes(pubkey_buf);

        return .{
            .block = block.block.getSlice(),
            .algorithm = algorithm,
            .signature = signature,
            .public_key = public_key,
        };
    }
};
