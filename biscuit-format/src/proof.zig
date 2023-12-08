const std = @import("std");
const Ed25519 = std.crypto.sign.Ed25519;
const schema = @import("biscuit-schema");

const ProofKind = enum(u8) {
    next_secret,
    final_signature,
};

pub const Proof = union(ProofKind) {
    next_secret: Ed25519.SecretKey,
    final_signature: Ed25519.Signature,

    pub fn fromDecodedProof(schema_proof: schema.Proof) !Proof {
        const content = schema_proof.Content orelse return error.ExpectedProofContent;

        switch (content) {
            .nextSecret => |s| {
                const secret = s.getSlice();
                if (secret.len != Ed25519.KeyPair.seed_length) return error.IncorrectProofSecretLength;

                var buf: [Ed25519.KeyPair.seed_length]u8 = undefined;
                @memcpy(&buf, secret);

                const keypair = try Ed25519.KeyPair.create(buf);

                return .{ .next_secret = keypair.secret_key };
            },
            .finalSignature => |s| {
                const signature = s.getSlice();

                if (signature.len != Ed25519.Signature.encoded_length) return error.IncorrectProofSignatureLength;

                var buf: [Ed25519.Signature.encoded_length]u8 = undefined;
                @memcpy(&buf, signature);

                return .{ .final_signature = Ed25519.Signature.fromBytes(buf) };
            },
        }
    }
};
