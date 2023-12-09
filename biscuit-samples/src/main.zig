const std = @import("std");
const mem = std.mem;
const decode = @import("biscuit-format").decode;
const Biscuit = @import("biscuit").Biscuit;
const Samples = @import("sample.zig").Samples;
const Result = @import("sample.zig").Result;

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

        const token = try std.fs.cwd().readFileAlloc(alloc, testcase.filename, 0xFFFFFFF);

        for (testcase.validations.map.values()) |validation| {
            try validate(alloc, token, public_key, validation.result);
        }
    }
}

pub fn validate(alloc: mem.Allocator, token: []const u8, public_key: std.crypto.sign.Ed25519.PublicKey, result: Result) !void {
    switch (result) {
        .Ok => try runValidation(alloc, token, public_key),
        .Err => |e| {
            switch (e) {
                .Format => |f| switch (f) {
                    .InvalidSignatureSize => runValidation(alloc, token, public_key) catch |err| switch (err) {
                        error.IncorrectBlockSignatureLength => return,
                        else => return err,
                    },
                    .Signature => |s| switch (s) {
                        .InvalidSignature => runValidation(alloc, token, public_key) catch |err| switch (err) {
                            error.SignatureVerificationFailed,
                            error.InvalidEncoding,
                            => return,
                            else => return err,
                        },
                    },
                },
                .FailedLogic => |f| switch (f) {
                    .Unauthorized => runValidation(alloc, token, public_key) catch |err| switch (err) {
                        else => return err,
                    },
                    .InvalidBlockRule => runValidation(alloc, token, public_key) catch |err| switch (err) {
                        else => return err,
                    },
                },
                .Execution => runValidation(alloc, token, public_key) catch |err| switch (err) {
                    else => return err,
                },
            }

            return error.ExpectedError;
        },
    }
}

pub fn runValidation(alloc: mem.Allocator, token: []const u8, public_key: std.crypto.sign.Ed25519.PublicKey) !void {
    var b = try Biscuit.initFromBytes(alloc, token, public_key);
    defer b.deinit();

    var a = b.authorizer(alloc);
    defer a.deinit();
}
