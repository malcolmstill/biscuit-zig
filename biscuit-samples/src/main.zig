const std = @import("std");
const decode = @import("biscuit-format").decode;
const Biscuit = @import("biscuit").Biscuit;

const Samples = struct {
    root_private_key: []const u8,
    root_public_key: []const u8,
    testcases: []const Testcase,
};

const Testcase = struct {
    title: []const u8,
    filename: []const u8,
    token: []Token,
    validations: std.json.ArrayHashMap(Validation),
};

const Token = struct {
    symbols: [][]const u8,
    public_keys: [][]const u8,
    external_key: ?[]const u8,
    code: []const u8,
};

const Validation = struct {
    world: ?World,
    result: Result,
    authorizer_code: []const u8,
    revocation_ids: [][]const u8,
};

const Result = union(enum) {
    Ok: usize,
    Err: Err,

    const Err = union(enum) {
        Format: union(enum) {
            InvalidSignatureSize: usize,
            Signature: union(enum) {
                InvalidSignature: []const u8,
            },
        },
        FailedLogic: union(enum) {
            Unauthorized: struct {
                policy: union(enum) {
                    Allow: usize,
                },
                checks: []union(enum) {
                    Block: struct {
                        block_id: usize,
                        check_id: usize,
                        rule: []const u8,
                    },
                    Authorizer: struct {
                        check_id: usize,
                        rule: []const u8,
                    },
                },
            },
            InvalidBlockRule: struct { usize, []const u8 },
        },
        Execution: []const u8,
    };
};

const World = struct {
    facts: [][]const u8,
    rules: [][]const u8,
    checks: [][]const u8,
    policies: [][]const u8,
};

test "samples" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer _ = arena.deinit();

    const alloc = arena.allocator();
    const filename = "samples/samples.json";

    // 2. Parse json
    const json_string = @embedFile(filename);

    const dynamic_tree = try std.json.parseFromSliceLeaky(std.json.Value, alloc, json_string, .{});
    const r = try std.json.parseFromValueLeaky(Samples, alloc, dynamic_tree, .{});

    std.debug.print("sk = {s}\n", .{r.root_private_key});
    std.debug.print("pk = {s}\n", .{r.root_public_key});
    for (r.testcases, 0..) |testcase, i| {
        std.debug.print("testcase[{}] = {any}\n", .{ i, testcase });
    }

    // const tokens: [1][]const u8 = .{
    //     // Token with check (in authority block) that should pass and a check (in the authority block) that should fail
    //     "Es8CCuQBCgFhCgFiCgFjCgFkCgdtYWxjb2xtCgRqb2huCgExCgEwCgRlcmljGAMiCQoHCAISAxiACCIJCgcIAhIDGIEIIgkKBwgCEgMYgggiCQoHCAISAxiDCCIOCgwIBxIDGIQIEgMYgAgiDgoMCAcSAxiECBIDGIIIIg4KDAgHEgMYhQgSAxiBCCopChAIBBIDCIYIEgMIhwgSAhgAEgcIAhIDCIcIEgwIBxIDCIYIEgMIhwgyGAoWCgIIGxIQCAQSAxiECBIDGIAIEgIYADIYChYKAggbEhAIBBIDGIgIEgMYgwgSAhgBEiQIABIgbACOx_sohlqZpzEwG23cKbN5wsUseLHHPt1tM8zVilIaQHMBawtn2NIa0jkJ38FR-uw7ncEAP1Qp_g6zctajVDLo1eMhBzjBO6lCddBHyEgvwZ9bufXYClHAwEZQyGKeEgwiIgogCfqPElEy9fyO6r-E5GT9-io3bhhSSe9wVAn6x6fsM7k=",
    // };

    // var public_key_mem: [32]u8 = undefined;
    // _ = try std.fmt.hexToBytes(&public_key_mem, "49fe7ec1972952c8c92119def96235ad622d0d024f3042a49c7317f7d5baf3da");
    // const public_key = try std.crypto.sign.Ed25519.PublicKey.fromBytes(public_key_mem);

    // const token = tokens[0];
    // const bytes = try decode.urlSafeBase64ToBytes(allocator, token);
    // defer allocator.free(bytes);

    // var b = try Biscuit.initFromBytes(allocator, bytes, public_key);
    // defer b.deinit();

    // var a = b.authorizer(allocator);
    // defer a.deinit();

    // try testing.expectError(error.AuthorizationFailed, a.authorize());

    // try testing.expectEqual(2, 2);
}
