const std = @import("std");
const pb = @import("protobuf");
const schema = @import("schema.pb.zig");
const SignedBlock = @import("signed_block.zig").SignedBlock;

pub const SerializedBiscuit = struct {
    biscuit: schema.Biscuit,
    allocator: std.mem.Allocator,
    authority: SignedBlock,
    blocks: std.ArrayList(SignedBlock),
    // proof: Proof,
    // root_key_id: ?u64,

    const expected_signature_length = 64;

    pub fn from_bytes(allocator: std.mem.Allocator, bytes: []const u8, public_key: std.crypto.sign.Ed25519.PublicKey) !SerializedBiscuit {
        const ds_biscuit = try pb.pb_decode(schema.Biscuit, bytes, allocator);

        const authority = try SignedBlock.fromDeserializedBlock(ds_biscuit.authority orelse return error.ExpectedAuthorityBlock);

        var blocks = std.ArrayList(SignedBlock).init(allocator);
        for (ds_biscuit.blocks.items) |blk| {
            const sb = try SignedBlock.fromDeserializedBlock(blk);
            try blocks.append(sb);
        }

        var biscuit = SerializedBiscuit{
            .biscuit = ds_biscuit,
            .allocator = allocator,
            .authority = authority,
            .blocks = blocks,
        };

        try biscuit.verify(public_key);

        return biscuit;
    }

    pub fn deinit(self: *SerializedBiscuit) void {
        self.blocks.deinit();
        self.biscuit.deinit();
    }

    fn verify(self: *SerializedBiscuit, public_key: std.crypto.sign.Ed25519.PublicKey) !void {
        // Verify the authority block's signature
        var algo: [4]u8 = undefined;
        std.mem.writeIntNative(u32, algo[0..], @as(u32, @bitCast(@intFromEnum(self.authority.algorithm))));

        var verifier = try self.authority.signature.verifier(public_key);
        verifier.update(self.authority.block);
        verifier.update(&algo);
        verifier.update(&self.authority.public_key.bytes);

        try verifier.verify();
    }
};

test {
    const testing = std.testing;
    var allocator = testing.allocator;

    const token = "EoEBChcKCHVzZXIxMjM0GAMiCQoHCAoSAxiACBIkCAASIL_PJGBY0LdTn-dXVg_kCaaKKu33fWwdCh3ZKxQQkvJ9GkDLD3Uvo2F_1cAhVVQPp1o0YjRcgyaXoDctLHgr1qZeMl3tOYLOIMXNd3FxLEQFoN3AQNmv055hcf36r4djQLIMIiIKIHz5whoJ6TXF0N1IITtslWw5QS-7Wzkvy6xQ_ifUVGLT";

    // Public key
    var public_key_mem: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&public_key_mem, "1b3d3aac1055040f0320a2c2563234bfcf216df0983e439becf0f268fcdb303f");
    const public_key = try std.crypto.sign.Ed25519.PublicKey.fromBytes(public_key_mem);

    // Base64 decode token
    const size = try std.base64.url_safe.Decoder.calcSizeForSlice(token);
    var bytes = try allocator.alloc(u8, size);
    defer allocator.free(bytes);
    try std.base64.url_safe.Decoder.decode(bytes, token);

    var ser_biscuit = try SerializedBiscuit.from_bytes(testing.allocator, bytes, public_key);
    defer ser_biscuit.deinit();
}
