const std = @import("std");
const pb = @import("protobuf");
const schema = @import("schema.pb.zig");

const expected_signature_length = 64;

fn verify_authority_block(biscuit: schema.Biscuit, public_key: std.crypto.sign.Ed25519.PublicKey) !void {
    const authority = biscuit.authority orelse return error.ExpectedAuthority;
    const block_signature = authority.signature.getSlice();

    // Error if we don't have a signature of the correct length (e.g. 64 bytes for ed25519)
    if (block_signature.len != expected_signature_length) return error.IncorrectBlockSignatureLength;

    // Copy our signature into a fixed-length buffer and build Ed25519 signature object
    var block_signature_buf: [64]u8 = undefined;
    @memcpy(&block_signature_buf, block_signature);
    const signature = std.crypto.sign.Ed25519.Signature.fromBytes(block_signature_buf);

    // Algorithm buffer
    // FIXME: handle not-null assertion
    var algo: [4]u8 = undefined;
    std.mem.writeIntNative(u32, algo[0..], @as(u32, @bitCast(@intFromEnum(authority.nextKey.?.algorithm))));

    // Next key
    // FIXME: handle not-null assertion
    var next_key = authority.nextKey.?.key.getSlice();

    // Verify the authority block's signature
    var verifier = try signature.verifier(public_key);
    verifier.update(authority.block.getSlice());
    verifier.update(&algo);
    verifier.update(next_key);

    try verifier.verify();
}

test {
    const testing = std.testing;
    var allocator = testing.allocator;

    const token = "EoEBChcKCHVzZXIxMjM0GAMiCQoHCAoSAxiACBIkCAASIL_PJGBY0LdTn-dXVg_kCaaKKu33fWwdCh3ZKxQQkvJ9GkDLD3Uvo2F_1cAhVVQPp1o0YjRcgyaXoDctLHgr1qZeMl3tOYLOIMXNd3FxLEQFoN3AQNmv055hcf36r4djQLIMIiIKIHz5whoJ6TXF0N1IITtslWw5QS-7Wzkvy6xQ_ifUVGLT";
    const private_key = "bac44cb1dd1c5880f92cd1ea15278809d444a0ca17bd8bc32e132c5a0899f6ad";
    _ = private_key;

    // Public key
    var public_key_mem: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&public_key_mem, "1b3d3aac1055040f0320a2c2563234bfcf216df0983e439becf0f268fcdb303f");
    const public_key = try std.crypto.sign.Ed25519.PublicKey.fromBytes(public_key_mem);

    // Base64 decode token
    const size = try std.base64.url_safe.Decoder.calcSizeForSlice(token);
    var token_binary = try allocator.alloc(u8, size);
    defer allocator.free(token_binary);
    try std.base64.url_safe.Decoder.decode(token_binary, token);

    // Deserialize binary token
    const biscuit = try pb.pb_decode(schema.Biscuit, token_binary, testing.allocator);
    defer pb.pb_deinit(biscuit);

    // Verify the authority block
    try verify_authority_block(biscuit, public_key);
}
