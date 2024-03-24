const std = @import("std");

pub fn isDayMonthYearValid(year: i32, month: u8, day: u8) bool {
    return switch (month) {
        // 30 days has september, april june and november
        4, 6, 9, 11 => day <= 30,
        1, 3, 5, 7, 8, 10, 12 => day <= 31,
        2 => if (isLeapYear(year)) day <= 29 else day <= 28,
        else => false,
    };
}

fn isLeapYear(year: i32) bool {
    if (@mod(year, 400) == 0) return true;
    if (@mod(year, 100) == 0) return false;
    if (@mod(year, 4) == 0) return true;

    return false;
}

// test "Valid times" {
//     const testing = std.testing;
//     const Date = @import("biscuit-builder").Date;

//     const d1 = try Date.parseRFC3339("2018-12-20T00:00:00Z");
//     const d2 = try Date.parseRFC3339("2019-12-20T00:00:00Z");

//     try testing.expectEqual(2018, d1.year);
//     try testing.expectEqual(2019, d2.year);
//     try testing.expect(d1.lt(d2));
//     try testing.expect(d2.gt(d1));
// }
