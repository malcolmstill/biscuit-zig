const std = @import("std");
const testing = std.testing;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test {
    _ = @import("format/format.zig");
    _ = @import("format/serialized_biscuit.zig");
}
