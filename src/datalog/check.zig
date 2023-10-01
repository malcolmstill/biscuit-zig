const std = @import("std");

const schema = @import("biscuit-format").schema;

pub const Check = struct {
    pub fn fromSchema(allocator: std.mem.Allocator, check: schema.CheckV2) !Check {
        _ = check;
        _ = allocator;
        return .{};
    }

    pub fn deinit(self: *Check) void {
        _ = self;
    }
};
