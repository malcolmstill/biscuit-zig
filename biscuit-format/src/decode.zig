const std = @import("std");

pub fn urlSafeBase64ToBytes(allocator: std.mem.Allocator, token: []const u8) ![]u8 {
    const size = try std.base64.url_safe.Decoder.calcSizeForSlice(token);
    var bytes = try allocator.alloc(u8, size);
    errdefer allocator.free(bytes);

    try std.base64.url_safe.Decoder.decode(bytes, token);

    return bytes;
}
