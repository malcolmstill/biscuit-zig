const std = @import("std");
const schema = @import("schema.pb.zig");
const l = @import("lengths.zig");

pub const SignedBlock = struct {
    block: []const u8,
    algorithm: schema.PublicKey.Algorithm,
    signature: std.crypto.sign.Ed25519.Signature,
    public_key: std.crypto.sign.Ed25519.PublicKey,

    pub fn fromDecodedBlock(block: schema.SignedBlock) !SignedBlock {
        const block_signature = block.signature.getSlice();

        const next_key = block.nextKey orelse return error.ExpectedNextKey;
        const algorithm = next_key.algorithm;
        const block_public_key = next_key.key.getSlice();

        if (block_signature.len != l.SIGNATURE_LENGTH) return error.IncorrectBlockSignatureLength;
        if (block_public_key.len != l.PUBLIC_KEY_LENGTH) return error.IncorrectBlockNextKeyLength;

        var sign_buf: [l.SIGNATURE_LENGTH]u8 = undefined;
        @memcpy(&sign_buf, block_signature);
        const signature = std.crypto.sign.Ed25519.Signature.fromBytes(sign_buf);

        var pubkey_buf: [l.PUBLIC_KEY_LENGTH]u8 = undefined;
        @memcpy(&pubkey_buf, block_public_key);
        const public_key = try std.crypto.sign.Ed25519.PublicKey.fromBytes(pubkey_buf);

        return .{
            .block = block.block.getSlice(),
            .algorithm = algorithm,
            .signature = signature,
            .public_key = public_key,
        };
    }

    pub fn algorithmBuf(self: *SignedBlock) [4]u8 {
        var buf: [4]u8 = undefined;
        std.mem.writeIntNative(u32, buf[0..], @as(u32, @bitCast(@intFromEnum(self.algorithm))));
        return buf;
    }
};
