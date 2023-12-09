const std = @import("std");
const mem = std.mem;
const decode = @import("biscuit-format").decode;
const Biscuit = @import("biscuit").Biscuit;
const Samples = @import("sample.zig").Samples;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() anyerror!void {
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();
    _ = args.skip();

    const testname = args.next();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const alloc = arena.allocator();

    // 2. Parse json
    const json_string = @embedFile("samples/samples.json");

    const dynamic_tree = try std.json.parseFromSliceLeaky(std.json.Value, alloc, json_string, .{});
    const r = try std.json.parseFromValueLeaky(Samples, alloc, dynamic_tree, .{});

    var public_key_mem: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&public_key_mem, r.root_public_key);
    const public_key = try std.crypto.sign.Ed25519.PublicKey.fromBytes(public_key_mem);

    for (r.testcases) |testcase| {
        // If we've been provided with a particular test to run, skip all other tests
        if (testname) |name| {
            if (!mem.eql(u8, name, testcase.filename)) continue;
        }

        std.debug.print("test = {any}\n", .{std.json.fmt(testcase, .{ .whitespace = .indent_2 })});

        const token = try std.fs.cwd().readFileAlloc(alloc, testcase.filename, 0xFFFFFFF);

        var b = try Biscuit.initFromBytes(alloc, token, public_key);
        defer b.deinit();

        var a = b.authorizer(alloc);
        defer a.deinit();

        try a.authorize();
    }
}
