const std = @import("std");
const pb = @import("protobuf");
const schema = @import("schema.pb.zig");

const expected_signature_length = 64;

fn decode_authority_block(allocator: std.mem.Allocator, biscuit: schema.Biscuit, public_key: std.crypto.sign.Ed25519.PublicKey) !void {
    _ = public_key;

    const authority = biscuit.authority orelse return error.ExpectedAuthority;

    const block = try pb.pb_decode(schema.Block, authority.block.getSlice(), allocator);
    defer pb.pb_deinit(block);

    // Print symbols
    for (block.symbols.items, 0..) |symbol, i| {
        std.debug.print("symbol[{}] = \"{s}\"\n", .{ i, symbol.getSlice() });
    }

    // Print facts
    for (block.facts_v2.items) |fact| {
        var predicate: schema.PredicateV2 = fact.predicate orelse continue;

        std.debug.print("predicate = {any}\n", .{predicate});

        for (predicate.terms.items) |term| {
            var content = term.Content orelse continue;
            std.debug.print("content = {any}\n", .{content});
            switch (content) {
                .string => |s| std.debug.print("string = {any}\n", .{s}),
                .variable,
                .integer,
                .date,
                .bytes,
                .bool,
                .set,
                => @panic("not implemented"),
            }
        }
    }
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

    try decode_authority_block(testing.allocator, biscuit, public_key);
}
