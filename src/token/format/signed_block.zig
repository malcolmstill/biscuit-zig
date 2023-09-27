const std = @import("std");
const pb = @import("protobuf");
const schema = @import("schema.pb.zig");

pub const SignedBlock = struct {
    block: []const u8,
    public_key: std.crypto.sign.Ed25519.PublicKey,
    signature: []const u8,

    pub fn init(
        block: []const u8,
        public_key: std.crypto.sign.Ed25519.PublicKey,
        signature: []const u8,
    ) SignedBlock {
        return .{
            .block = block,
            .public_key = public_key,
            .signature = signature,
        };
    }
};
