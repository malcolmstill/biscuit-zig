const std = @import("std");
const pb = @import("protobuf");
const schema = @import("schema.pb.zig");

test {
    const testing = std.testing;

    const token = "EoEBChcKCHVzZXIxMjM0GAMiCQoHCAoSAxiACBIkCAASIL_PJGBY0LdTn-dXVg_kCaaKKu33fWwdCh3ZKxQQkvJ9GkDLD3Uvo2F_1cAhVVQPp1o0YjRcgyaXoDctLHgr1qZeMl3tOYLOIMXNd3FxLEQFoN3AQNmv055hcf36r4djQLIMIiIKIHz5whoJ6TXF0N1IITtslWw5QS-7Wzkvy6xQ_ifUVGLT";
    const private_key = "bac44cb1dd1c5880f92cd1ea15278809d444a0ca17bd8bc32e132c5a0899f6ad";
    const public_key_hex = "1b3d3aac1055040f0320a2c2563234bfcf216df0983e439becf0f268fcdb303f";
    var public_key_mem: [32]u8 = undefined;
    const public_key_bytes = try std.fmt.hexToBytes(&public_key_mem, "1b3d3aac1055040f0320a2c2563234bfcf216df0983e439becf0f268fcdb303f");
    _ = public_key_bytes;

    std.debug.print("token = {s}\nprivate key = {s}\npublic key = {s}\n", .{ token, private_key, public_key_hex });

    const size = try std.base64.url_safe.Decoder.calcSizeForSlice(token);
    var allocator = testing.allocator;

    var token_binary = try allocator.alloc(u8, size);
    defer allocator.free(token_binary);

    std.debug.print("Decoding...\n", .{});
    try std.base64.url_safe.Decoder.decode(token_binary, token);

    std.debug.print("Decoded = {any}\n", .{token_binary});

    const biscuit = try pb.pb_decode(schema.Biscuit, token_binary, testing.allocator);
    defer pb.pb_deinit(biscuit);

    if (biscuit.authority) |authority| {
        std.debug.print("biscuit.authority = {any}\n", .{authority});
        std.debug.print("biscuit.authority.signature = {any}\n", .{authority.signature.getSlice()});

        const public_key = try std.crypto.sign.Ed25519.PublicKey.fromBytes(public_key_mem);
        switch (authority.signature) {
            .Owned => |o| {
                std.debug.print("signature.len = {}\n", .{o.str.len});
                std.debug.print("block str = \"{any}\"\n", .{authority.block.Owned.str});
                std.debug.print("block str len = {}\n", .{authority.block.Owned.str.len});
                var s: [64]u8 = undefined;
                @memcpy(&s, o.str[0..]);
                var algo: [4]u8 = undefined;
                std.mem.writeIntNative(u32, algo[0..], @as(u32, @bitCast(@intFromEnum(authority.nextKey.?.algorithm))));

                const signature = std.crypto.sign.Ed25519.Signature.fromBytes(s);
                var verifier = try signature.verifier(public_key);
                verifier.update(authority.block.Owned.str);
                verifier.update(&algo);
                verifier.update(authority.nextKey.?.key.Owned.str);
                try verifier.verify();
                std.debug.print("Authority block verified\n", .{});
            },
            .Const => {
                std.debug.print("Const\n", .{});
            },
            .Empty => {
                std.debug.print("Empty\n", .{});
            },
        }

        if (authority.externalSignature) |externalSignature| {
            std.debug.print("externalSignature.publicKey = {any}\n", .{externalSignature.publicKey});
        }
    }

    std.debug.print("block count = {}\n", .{biscuit.blocks.items.len});
    for (biscuit.blocks.items, 0..) |block, i| {
        std.debug.print("biscuit.block[{}] = {any}\n", .{ i, block });
    }

    if (biscuit.proof) |proof| {
        std.debug.print("biscuit.proof = {any}\n", .{proof});
        std.debug.print("biscuit.proof.Content = {any}\n", .{proof.Content});
        if (proof.Content) |Content| {
            _ = Content;
        }
    }
}
