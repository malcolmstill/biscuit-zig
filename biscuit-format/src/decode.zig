const std = @import("std");

pub fn urlSafeBase64ToBytes(allocator: std.mem.Allocator, token: []const u8) ![]u8 {
    const size = try std.base64.url_safe.Decoder.calcSizeForSlice(token);
    const bytes = try allocator.alloc(u8, size);
    errdefer allocator.free(bytes);

    try std.base64.url_safe.Decoder.decode(bytes, token);

    return bytes;
}

pub fn bytesToUrlSafeBase64(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    const size = std.base64.url_safe.Encoder.calcSize(bytes.len);

    const encoded = try allocator.alloc(u8, size);
    errdefer allocator.free(bytes);

    return std.base64.url_safe.Encoder.encode(encoded, bytes);
}

pub fn bytesToBase64(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    const size = std.base64.standard.Encoder.calcSize(bytes.len);

    const encoded = try allocator.alloc(u8, size);
    errdefer allocator.free(bytes);

    return std.base64.standard.Encoder.encode(encoded, bytes);
}
