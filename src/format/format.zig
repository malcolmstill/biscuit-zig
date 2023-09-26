const std = @import("std");
const pb = @import("protobuf");
const schema = @import("schema.pb.zig");

test {
    const testing = std.testing;

    const token = "EoEBChcKCHVzZXIxMjM0GAMiCQoHCAoSAxiACBIkCAASILlAs6cGNuxR38X_BUrynKGqkdwDvPa1qYB1Kw3PeFbPGkBu8IxQUirKrePMSlFHRpUdOXx0bMud8IZoWWevxhpZvvW99FuJ3_-FNTiSKVS6Jf-b6kZuQVYh6RJzqYCkWSQGIiIKIGMXXAMftXOmoiHEp6jgKOe2KNS53MSOaQovGh3byC_r";
    const private_key = "bac44cb1dd1c5880f92cd1ea15278809d444a0ca17bd8bc32e132c5a0899f6ad";
    const public_key = "1b3d3aac1055040f0320a2c2563234bfcf216df0983e439becf0f268fcdb303f";

    std.debug.print("token = {s}\nprivate key = {s}\npublic key = {s}\n", .{ token, private_key, public_key });

    const size = try std.base64.url_safe.Decoder.calcSizeForSlice(token);
    var allocator = testing.allocator;

    var dst = try allocator.alloc(u8, size);
    defer allocator.free(dst);

    std.debug.print("Decoding...\n", .{});
    try std.base64.url_safe.Decoder.decode(dst, token);

    std.debug.print("Decoded = {any}\n", .{dst});

    const biscuit = try pb.pb_decode(schema.Biscuit, dst, testing.allocator);
    defer pb.pb_deinit(biscuit);

    if (biscuit.authority) |authority| {
        std.debug.print("biscuit.authority = {any}\n", .{authority});
        std.debug.print("biscuit.authority.signature = {any}\n", .{authority.signature.getSlice()});
    }

    std.debug.print("block count = {}\n", .{biscuit.blocks.items.len});
    for (biscuit.blocks.items, 0..) |block, i| {
        std.debug.print("biscuit.block[{}] = {any}\n", .{ i, block });
    }
}
