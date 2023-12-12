const std = @import("std");
const Ed25519 = std.crypto.sign.Ed25519;
const schema = @import("biscuit-schema");

pub const SignedBlock = struct {
    block: []const u8,
    algorithm: schema.PublicKey.Algorithm,
    signature: Ed25519.Signature,
    public_key: Ed25519.PublicKey,

    pub fn fromDecodedBlock(schema_signed_block: schema.SignedBlock) !SignedBlock {
        const block_signature = schema_signed_block.signature.getSlice();

        const next_key = schema_signed_block.nextKey orelse return error.ExpectedNextKey;
        const algorithm = next_key.algorithm;
        const block_public_key = next_key.key.getSlice();

        if (block_signature.len != Ed25519.Signature.encoded_length) return error.IncorrectBlockSignatureLength;
        if (block_public_key.len != Ed25519.PublicKey.encoded_length) return error.IncorrectBlockNextKeyLength;

        var sign_buf: [Ed25519.Signature.encoded_length]u8 = undefined;
        @memcpy(&sign_buf, block_signature);
        const signature = Ed25519.Signature.fromBytes(sign_buf);

        var pubkey_buf: [Ed25519.PublicKey.encoded_length]u8 = undefined;
        @memcpy(&pubkey_buf, block_public_key);
        const public_key = try Ed25519.PublicKey.fromBytes(pubkey_buf);

        return .{
            .block = schema_signed_block.block.getSlice(),
            .algorithm = algorithm,
            .signature = signature,
            .public_key = public_key,
        };
    }

    pub fn algorithmBuf(signed_block: *SignedBlock) [4]u8 {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, buf[0..], @as(u32, @bitCast(@intFromEnum(signed_block.algorithm))), @import("builtin").cpu.arch.endian());
        return buf;
    }
};
