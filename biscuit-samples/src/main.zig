const std = @import("std");
const mem = std.mem;
const decode = @import("biscuit-format").decode;
const Biscuit = @import("biscuit").Biscuit;
const AuthorizerError = @import("biscuit").AuthorizerError;
const Samples = @import("sample.zig").Samples;
const Result = @import("sample.zig").Result;

const log = std.log.scoped(.samples);

var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() anyerror!void {
    defer _ = gpa_state.deinit();

    const gpa = gpa_state.allocator();

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();

    const arena = arena_state.allocator();

    var args = try std.process.argsWithAllocator(arena);
    defer args.deinit();
    _ = args.skip();

    const testname = args.next();

    // 2. Parse json
    const json_string = @embedFile("samples/samples.json");

    const dynamic_tree = try std.json.parseFromSliceLeaky(std.json.Value, arena, json_string, .{});
    const r = try std.json.parseFromValueLeaky(Samples, arena, dynamic_tree, .{});

    var public_key_mem: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&public_key_mem, r.root_public_key);
    const public_key = try std.crypto.sign.Ed25519.PublicKey.fromBytes(public_key_mem);

    for (r.testcases) |testcase| {
        // If we've been provided with a particular test to run, skip all other tests
        if (testname) |name| {
            if (!mem.eql(u8, name, testcase.filename)) continue;
        }

        const token = try std.fs.cwd().readFileAlloc(arena, testcase.filename, 0xFFFFFFF);

        for (testcase.validations.map.values(), 0..) |validation, i| {
            errdefer log.err("Error on validation {} of {s}\n", .{ i, testcase.filename });
            try validate(gpa, token, public_key, validation.result, validation.authorizer_code);
        }
    }
}

pub fn validate(allocator: mem.Allocator, token: []const u8, public_key: std.crypto.sign.Ed25519.PublicKey, result: Result, authorizer_code: []const u8) !void {
    var errors = std.ArrayList(AuthorizerError).init(allocator);
    defer errors.deinit();

    switch (result) {
        .Ok => try runValidation(allocator, token, public_key, authorizer_code, &errors),
        .Err => |e| {
            switch (e) {
                .Format => |f| switch (f) {
                    .InvalidSignatureSize => runValidation(allocator, token, public_key, authorizer_code, &errors) catch |err| switch (err) {
                        error.IncorrectBlockSignatureLength => return,
                        else => return err,
                    },
                    .Signature => |s| switch (s) {
                        .InvalidSignature => runValidation(allocator, token, public_key, authorizer_code, &errors) catch |err| switch (err) {
                            error.SignatureVerificationFailed,
                            error.InvalidEncoding,
                            => return,
                            else => return err,
                        },
                    },
                },
                .FailedLogic => |f| switch (f) {
                    .Unauthorized => |u| runValidation(allocator, token, public_key, authorizer_code, &errors) catch |err| switch (err) {
                        error.AuthorizationFailed => {

                            // Check that we have expected check failures
                            for (u.checks) |expected_failed_check| {
                                var check_accounted_for = false;

                                switch (expected_failed_check) {
                                    .Block => |expected_failed_block_check| {
                                        for (errors.items) |found_failed_check| {
                                            switch (found_failed_check) {
                                                .no_matching_policy => continue,
                                                .denied_by_policy => continue,
                                                .failed_block_check => |failed_block_check| {
                                                    if (failed_block_check.block_id == expected_failed_block_check.block_id and failed_block_check.check_id == expected_failed_block_check.check_id) {
                                                        // continue :blk;
                                                        check_accounted_for = true;
                                                    }
                                                },
                                                .failed_authorizer_check => return error.NotImplemented,
                                                .unbound_variable => continue,
                                            }
                                        }
                                    },
                                    .Authorizer => |expected_failed_authorizer_check| {
                                        for (errors.items) |found_failed_check| {
                                            switch (found_failed_check) {
                                                .no_matching_policy => continue,
                                                .denied_by_policy => continue,
                                                .failed_block_check => return error.NotImplemented,
                                                .failed_authorizer_check => |failed_block_check| {
                                                    if (failed_block_check.check_id == expected_failed_authorizer_check.check_id) {
                                                        // continue :blk;
                                                        check_accounted_for = true;
                                                    }
                                                },
                                                .unbound_variable => continue,
                                            }
                                        }
                                    },
                                }

                                if (!check_accounted_for) return error.ExpectedFailedCheck;
                            }

                            return;
                        },
                        else => return err,
                    },
                    .InvalidBlockRule => |_| runValidation(allocator, token, public_key, authorizer_code, &errors) catch |err| switch (err) {
                        error.AuthorizationFailed => {
                            for (errors.items) |found_failed_check| {
                                switch (found_failed_check) {
                                    .no_matching_policy => continue,
                                    .denied_by_policy => continue,
                                    .failed_block_check => continue,
                                    .failed_authorizer_check => return error.NotImplemented,
                                    .unbound_variable => return,
                                }
                            }
                        },
                        else => return err,
                    },
                },
                .Execution => runValidation(allocator, token, public_key, authorizer_code, &errors) catch |err| switch (err) {
                    error.Overflow => return,
                    else => return err,
                },
            }

            return error.ExpectedError;
        },
    }
}

pub fn runValidation(allocator: mem.Allocator, token: []const u8, public_key: std.crypto.sign.Ed25519.PublicKey, authorizer_code: []const u8, errors: *std.ArrayList(AuthorizerError)) !void {
    var b = try Biscuit.fromBytes(allocator, token, public_key);
    defer b.deinit();

    var a = try b.authorizer();
    defer a.deinit();

    var it = std.mem.split(u8, authorizer_code, ";");
    while (it.next()) |code| {
        const text = std.mem.trim(u8, code, " \n");
        if (text.len == 0) continue;

        if (std.mem.startsWith(u8, text, "check if") or std.mem.startsWith(u8, text, "check all")) {
            try a.addCheck(text);
        } else if (std.mem.startsWith(u8, text, "allow if") or std.mem.startsWith(u8, text, "deny if")) {
            try a.addPolicy(text);
        } else if (std.mem.startsWith(u8, text, "revocation_id")) {
            //
        } else {
            try a.addFact(text);
        }
    }

    _ = a.authorize(errors) catch |err| {
        log.debug("authorize() returned with errors: {any}\n", .{errors.items});
        return err;
    };
}

test "Basic token can be sealed" {
    const testing = std.testing;

    const hex_root_public_key = "1055c750b1a1505937af1537c626ba3263995c33a64758aaafb1275b0312e284";

    var public_key_mem: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&public_key_mem, hex_root_public_key);
    const public_key = try std.crypto.sign.Ed25519.PublicKey.fromBytes(public_key_mem);

    const token = try std.fs.cwd().readFileAlloc(testing.allocator, "src/samples/test001_basic.bc", 0xFFFFFFF);
    defer testing.allocator.free(token);

    var b = try Biscuit.fromBytes(testing.allocator, token, public_key);
    defer b.deinit();

    _ = try b.seal();
}
