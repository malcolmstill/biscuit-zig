const std = @import("std");
const testing = std.testing;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test {
    _ = @import("token/format/format.zig");
    _ = @import("token/format/serialized_biscuit.zig");
    _ = @import("token/block.zig");
}
