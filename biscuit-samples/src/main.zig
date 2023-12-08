const std = @import("std");
const decode = @import("biscuit-format").decode;
const Biscuit = @import("biscuit").Biscuit;

test "samples" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const tokens: [1][]const u8 = .{
        // Token with check (in authority block) that should pass and a check (in the authority block) that should fail
        "Es8CCuQBCgFhCgFiCgFjCgFkCgdtYWxjb2xtCgRqb2huCgExCgEwCgRlcmljGAMiCQoHCAISAxiACCIJCgcIAhIDGIEIIgkKBwgCEgMYgggiCQoHCAISAxiDCCIOCgwIBxIDGIQIEgMYgAgiDgoMCAcSAxiECBIDGIIIIg4KDAgHEgMYhQgSAxiBCCopChAIBBIDCIYIEgMIhwgSAhgAEgcIAhIDCIcIEgwIBxIDCIYIEgMIhwgyGAoWCgIIGxIQCAQSAxiECBIDGIAIEgIYADIYChYKAggbEhAIBBIDGIgIEgMYgwgSAhgBEiQIABIgbACOx_sohlqZpzEwG23cKbN5wsUseLHHPt1tM8zVilIaQHMBawtn2NIa0jkJ38FR-uw7ncEAP1Qp_g6zctajVDLo1eMhBzjBO6lCddBHyEgvwZ9bufXYClHAwEZQyGKeEgwiIgogCfqPElEy9fyO6r-E5GT9-io3bhhSSe9wVAn6x6fsM7k=",
    };

    var public_key_mem: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&public_key_mem, "49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da");
    const public_key = try std.crypto.sign.Ed25519.PublicKey.fromBytes(public_key_mem);

    const token = tokens[0];
    const bytes = try decode.urlSafeBase64ToBytes(allocator, token);
    defer allocator.free(bytes);

    var b = try Biscuit.initFromBytes(allocator, bytes, public_key);
    defer b.deinit();

    var a = b.authorizer(allocator);
    defer a.deinit();

    try testing.expectError(error.AuthorizationFailed, a.authorize());

    try testing.expectEqual(2, 2);
}
