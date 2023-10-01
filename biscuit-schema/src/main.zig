const std = @import("std");
const pb = @import("protobuf");
const schema = @import("schema.pb.zig");

pub usingnamespace @import("schema.pb.zig");

pub fn decodeBiscuit(allocator: std.mem.Allocator, bytes: []const u8) !schema.Biscuit {
    return pb.pb_decode(schema.Biscuit, bytes, allocator);
}

pub fn decodeBlock(allocator: std.mem.Allocator, bytes: []const u8) !schema.Block {
    return pb.pb_decode(schema.Block, bytes, allocator);
}
