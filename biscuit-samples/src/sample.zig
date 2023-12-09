const std = @import("std");

pub const Samples = struct {
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
    Err: union(enum) {
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
    },
};

const World = struct {
    facts: [][]const u8,
    rules: [][]const u8,
    checks: [][]const u8,
    policies: [][]const u8,
};
