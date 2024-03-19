const std = @import("std");
const mem = std.mem;
const decode = @import("biscuit-format").decode;
const Biscuit = @import("biscuit").Biscuit;
const AuthorizerError = @import("biscuit").AuthorizerError;
const Samples = @import("sample.zig").Samples;
const Result = @import("sample.zig").Result;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() anyerror!void {
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const alloc = arena.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.skip();

    const testname = args.next();

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
    var errors = std.ArrayList(AuthorizerError).init(alloc);
    defer errors.deinit();

    switch (result) {
        .Ok => try runValidation(alloc, token, public_key, &errors),
        .Err => |e| {
            switch (e) {
                .Format => |f| switch (f) {
                    .InvalidSignatureSize => runValidation(alloc, token, public_key, &errors) catch |err| switch (err) {
                        error.IncorrectBlockSignatureLength => return,
                        else => return err,
                    },
                    .Signature => |s| switch (s) {
                        .InvalidSignature => runValidation(alloc, token, public_key, &errors) catch |err| switch (err) {
                            error.SignatureVerificationFailed,
                            error.InvalidEncoding,
                            => return,
                            else => return err,
                        },
                    },
                },
                .FailedLogic => |f| switch (f) {
                    .Unauthorized => |u| runValidation(alloc, token, public_key, &errors) catch |err| switch (err) {
                        error.AuthorizationFailed => {

                            // Check that we have expected check failures
                            for (u.checks) |expected_failed_check| {
                                var check_accounted_for = false;

                                switch (expected_failed_check) {
                                    .Block => |expected_failed_block_check| {
                                        for (errors.items) |found_failed_check| {
                                            switch (found_failed_check) {
                                                .failed_block_check => |failed_block_check| {
                                                    if (failed_block_check.block_id == expected_failed_block_check.block_id and failed_block_check.check_id == expected_failed_block_check.check_id) {
                                                        // continue :blk;
                                                        check_accounted_for = true;
                                                    }
                                                },
                                                .failed_authority_check => return error.NotImplemented,
                                            }
                                        }
                                    },
                                    .Authorizer => return error.NotImplemented,
                                }

                                if (!check_accounted_for) return error.ExpectedFailedCheck;
                            }

                            return;
                        },
                        else => return err,
                    },
                    .InvalidBlockRule => runValidation(alloc, token, public_key, &errors) catch |err| switch (err) {
                        else => return err,
                    },
                },
                .Execution => runValidation(alloc, token, public_key, &errors) catch |err| switch (err) {
                    else => return err,
                },
            }

            return error.ExpectedError;
        },
    }
}

pub fn runValidation(alloc: mem.Allocator, token: []const u8, public_key: std.crypto.sign.Ed25519.PublicKey, errors: *std.ArrayList(AuthorizerError)) !void {
    var b = try Biscuit.initFromBytes(alloc, token, public_key);
    defer b.deinit();

    var a = b.authorizer(alloc);
    defer a.deinit();

    try a.authorize(errors);
}
