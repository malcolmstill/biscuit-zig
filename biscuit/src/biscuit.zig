const std = @import("std");
const mem = std.mem;
const Ed25519 = std.crypto.sign.Ed25519;
const Authorizer = @import("authorizer.zig").Authorizer;
const Block = @import("block.zig").Block;
const World = @import("biscuit-datalog").world.World;
const SerializedBiscuit = @import("biscuit-format").serialized_biscuit.SerializedBiscuit;

pub const Biscuit = struct {
    serialized: SerializedBiscuit,
    authority: Block,
    blocks: std.ArrayList(Block),
    symbols: std.ArrayList([]const u8),

    pub fn initFromBytes(allocator: mem.Allocator, bytes: []const u8, public_key: Ed25519.PublicKey) !Biscuit {
        std.debug.print("\ninitialising biscuit:\n", .{});
        const serialized = try SerializedBiscuit.initFromBytes(allocator, bytes, public_key);

        const authority = try Block.initFromBytes(allocator, serialized.authority.block);

        var blocks = std.ArrayList(Block).init(allocator);
        for (serialized.blocks.items) |b| {
            try blocks.append(try Block.initFromBytes(allocator, b.block));
        }

        return .{
            .serialized = serialized,
            .authority = authority,
            .blocks = blocks,
            .symbols = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Biscuit) void {
        for (self.blocks.items) |*block| {
            block.deinit();
        }
        self.blocks.deinit();
        self.authority.deinit();
        self.serialized.deinit();
    }

    pub fn authorizer(self: *Biscuit, allocator: std.mem.Allocator) Authorizer {
        return Authorizer.init(allocator, self.*);
    }
};

test {
    const decode = @import("biscuit-format").decode;
    const testing = std.testing;
    var allocator = testing.allocator;

    // Key
    // private: 83e03c958f83085923f3cd091bab3c3b33a0c7f93f44889739fdb6c6fdb26f5b
    // public:  49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da
    const tokens: [1][]const u8 = .{
        "EpACCqUBCgFhCgFiCgFjCgFkCgdtYWxjb2xtCgRqb2huCgEwCgExGAMiCQoHCAISAxiACCIJCgcIAhIDGIEIIgkKBwgCEgMYgggiCQoHCAISAxiDCCIOCgwIBxIDGIQIEgMYgAgiDgoMCAcSAxiECBIDGIIIIg4KDAgHEgMYhQgSAxiBCCokCgsIBBIDCIYIEgIYABIHCAISAwiGCBIMCAcSAwiHCBIDCIYIEiQIABIgnSmYbzjEQ2n09JhlmGs6j_ZhKYgj3nRkEMdGJJqQimwaQD4UTmEDtu5G8kRJZbNTcNuGg8Izb5ja2BSV3Rlkv1Y6IV_Nd00sIstiEq1RPH-M8xfFdWaW1gixH54Y5deHzwYiIgogFmxoQyXPm8ccNBKKh0hv8eRwrYjS56s0OTQWZShHoVw=",
        // "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCyIiCiCyJCJ0e-e00kyM_3O6IbbftDeYAnkoI8-G1x06NK283w==",
        // "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCxp9ChMKBGFiY2QYAyIJCgcIAhIDGIEIEiQIABIgkJwspMgTz4pW4hQ_Tkua7EdZ5AajdxV35q42IyXzAt0aQBH3kiLfP06W0dPlQeuxgLU26ssrjoK-v1vvw0dzQ2BtaQjPs8eKhsowhFCjQ6nnhSP0p7v4TaJHWeO2fPsbUQwiIgogeuDcbq6waTZ1HpYt_zYNtAy02gbnjV-5-juc9sdXNJg=",
        // "En0KEwoEMTIzNBgDIgkKBwgKEgMYgAgSJAgAEiCicdgxKsSQpGYPKcR7hmnI7WcRLaFNUNzqkCc92yZluhpAyMoux34FBhYaTsw32rddToN7qbl-XOAPQcaUALPg_SfmuxfXbU9aEIJGVCANQLUfoQwU1GAa8ZkXESkW1uCdCxp9ChMKBGFiY2QYAyIJCgcIAhIDGIEIEiQIABIgkJwspMgTz4pW4hQ_Tkua7EdZ5AajdxV35q42IyXzAt0aQBH3kiLfP06W0dPlQeuxgLU26ssrjoK-v1vvw0dzQ2BtaQjPs8eKhsowhFCjQ6nnhSP0p7v4TaJHWeO2fPsbUQwiQhJAfNph7vZIL6WSLwOCmMHkwb4OmCc5s7EByizwq6HZOF04SRwCF8THWcNImPj-5xWOuI3zVdxg11Qr6d0c5yxuCw==",
        // "Eq4BCkQKBDEyMzQKBmRvdWJsZQoBeAoBeRgDIgkKBwgKEgMYgAgqIQoNCIEIEgMIgggSAwiDCBIHCAoSAwiCCBIHCAoSAwiDCBIkCAASIHJpGIZ74pbiyybTMn2zrCqHf5t7ZUV9tMnT5xkLq5rsGkCnAznWzInI1-kJGuRUgluqmr96bJwKG3RT3iceJ3kzzzBWGT5dEFXYyIqWxpLDk9Qoy-AWpwS49SA5ynGKb5UGIiIKIESr7u80iDgTstDzVk6obTp6zJmVfBqNcBNtwjOQyVOr",
    };

    var public_key_mem: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&public_key_mem, "49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da");
    const public_key = try Ed25519.PublicKey.fromBytes(public_key_mem);

    for (tokens) |token| {
        const bytes = try decode.urlSafeBase64ToBytes(allocator, token);
        defer allocator.free(bytes);

        var b = try Biscuit.initFromBytes(allocator, bytes, public_key);
        defer b.deinit();

        var a = b.authorizer(allocator);
        defer a.deinit();

        try a.authorize();
    }
}
