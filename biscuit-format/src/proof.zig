const std = @import("std");
const schema = @import("biscuit-schema");
const l = @import("lengths.zig");

const ProofKind = enum(u8) {
    next_secret,
    final_signature,
};

pub const Proof = union(ProofKind) {
    next_secret: std.crypto.sign.Ed25519.SecretKey,
    final_signature: std.crypto.sign.Ed25519.Signature,

    pub fn fromDecodedProof(proof: schema.Proof) !Proof {
        const content = proof.Content orelse return error.ExpectedProofContent;

        switch (content) {
            .nextSecret => |s| {
                const secret = s.getSlice();
                if (secret.len != l.SECRET_KEY_LENGTH) return error.IncorrectProofSecretLength;

                var buf: [l.SECRET_KEY_LENGTH]u8 = undefined;
                @memcpy(&buf, secret);

                const keypair = try std.crypto.sign.Ed25519.KeyPair.create(buf);

                return .{ .next_secret = keypair.secret_key };
            },
            .finalSignature => |s| {
                const signature = s.getSlice();

                if (signature.len != l.SIGNATURE_LENGTH) return error.IncorrectProofSignatureLength;

                var buf: [l.SIGNATURE_LENGTH]u8 = undefined;
                @memcpy(&buf, signature);

                return .{ .final_signature = std.crypto.sign.Ed25519.Signature.fromBytes(buf) };
            },
        }
    }
};
