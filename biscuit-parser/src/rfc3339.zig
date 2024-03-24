const std = @import("std");
const fmt = std.fmt;

const Date = struct {
    year: i32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    nanosecond: u32,
    // Timezone offset in minutes from UTC; can be negative
    utc_offset: i32,

    pub fn eql(left: Date, right: Date) bool {
        return left.year == right.year and
            left.month == right.month and
            left.day == right.day and
            left.hour == right.hour and
            left.minute == right.minute and
            left.second == right.second and
            left.nanosecond == right.nanosecond;
    }

    pub fn lt(left: Date, right: Date) bool {
        if (left.year < right.year) return true;
        if (left.year > right.year) return false;

        std.debug.assert(left.year == right.year);

        if (left.month < right.month) return true;
        if (left.month > right.month) return false;

        std.debug.assert(left.month == right.month);

        if (left.day < right.day) return true;
        if (left.day > right.day) return false;

        std.debug.assert(left.day == right.day);

        if (left.hour < right.hour) return true;
        if (left.hour > right.hour) return false;

        std.debug.assert(left.hour == right.hour);

        if (left.minute < right.minute) return true;
        if (left.minute > right.minute) return false;

        std.debug.assert(left.minute == right.minute);

        if (left.second < right.second) return true;
        if (left.second > right.second) return false;

        std.debug.assert(left.second == right.second);

        if (left.nanosecond < right.nanosecond) return true;
        if (left.nanosecond > right.nanosecond) return false;

        std.debug.assert(left.nanosecond == right.nanosecond);

        return false;
    }

    pub fn gt(left: Date, right: Date) bool {
        if (left.year > right.year) return true;
        if (left.year < right.year) return false;

        std.debug.assert(left.year == right.year);

        if (left.month > right.month) return true;
        if (left.month < right.month) return false;

        std.debug.assert(left.month == right.month);

        if (left.day > right.day) return true;
        if (left.day < right.day) return false;

        std.debug.assert(left.day == right.day);

        if (left.hour > right.hour) return true;
        if (left.hour < right.hour) return false;

        std.debug.assert(left.hour == right.hour);

        if (left.minute > right.minute) return true;
        if (left.minute < right.minute) return false;

        std.debug.assert(left.minute == right.minute);

        if (left.second > right.second) return true;
        if (left.second < right.second) return false;

        std.debug.assert(left.second == right.second);

        if (left.nanosecond > right.nanosecond) return true;
        if (left.nanosecond < right.nanosecond) return false;

        std.debug.assert(left.nanosecond == right.nanosecond);

        return false;
    }

    pub fn lteq(left: Date, right: Date) bool {
        return left.eq(right) or left.lt(right);
    }

    pub fn gteq(left: Date, right: Date) bool {
        return left.eq(right) or left.gt(right);
    }

    pub fn parseRFC3339(input: []const u8) !Date {
        var it = std.mem.tokenize(u8, input, "T-:.+Z");

        // Date
        const year = try fmt.parseInt(i32, it.next() orelse return error.ExpectedYear, 10);

        // Parse month
        const month_part = it.next() orelse return error.ExpectedMonth;
        if (month_part.len != 2) return error.ExpectedTwoDigitMonth;
        const month = try fmt.parseInt(u8, month_part, 10);
        if (month < 1 or month > 12) return error.MonthOutOfRange;

        // Parse day
        const day_part = it.next() orelse return error.ExpectedDay;
        if (day_part.len != 2) return error.ExpectedTwoDigitDay;
        const day = try fmt.parseInt(u8, day_part, 10);
        if (day < 1 or day > 31) return error.DayOutOfRange;

        if (!isDayMonthYearValid(year, month, day)) return error.InvalidDayMonthYearCombination;

        // Parse hour
        const hour_part = it.next() orelse return error.ExpectedHour;
        if (hour_part.len != 2) return error.ExpectedTwoDigitHour;
        const hour = try fmt.parseInt(u8, hour_part, 10);
        if (hour > 23) return error.HoyrOutOfRange;

        // Parse minute
        const minute_part = it.next() orelse return error.ExpectedMinute;
        if (minute_part.len != 2) return error.ExpectedTwoDigitMinute;
        const minute = try fmt.parseInt(u8, minute_part, 10);
        if (minute > 59) return error.MinuteOutOfRange;

        // Parse second
        const second_part = it.next() orelse return error.ExpectedSecond;
        if (second_part.len != 2) return error.ExpectedTwoDigitSecond;
        const second = try fmt.parseInt(u8, second_part, 10);
        if (second > 59) return error.SecondOutOfRange;

        // Time offset (assuming the input ends with a 'Z' or a time offset like '-07:00')
        // const next = it.next() orelse "";

        const offset: i32 = 0;

        // if (!std.mem.eql(u8, next, "Z")) {
        //     return error.OffsetNotImplemented;
        //     // const sign = if (next[0] == '-') -1 else 1;
        //     // const offset_hour = try fmt.parseInt(i32, next[1..3], 10);
        //     // const offset_minute = try fmt.parseInt(i32, it.next().?, 10);

        //     // offset = std.time.minutes(sign * (offset_hour * 60 + offset_minute));
        // }

        return .{
            .year = year,
            .month = month,
            .day = day,
            .hour = hour,
            .minute = minute,
            .second = second,
            .nanosecond = 0, // This example does not parse nanoseconds
            .utc_offset = offset,
        };
    }
};

fn isLeapYear(year: i32) bool {
    if (@mod(year, 400) == 0) return true;
    if (@mod(year, 100) == 0) return false;
    if (@mod(year, 4) == 0) return true;

    return false;
}

fn isDayMonthYearValid(year: i32, month: u8, day: u8) bool {
    return switch (month) {
        // 30 days has september, april june and november
        4, 6, 9, 11 => day <= 30,
        1, 3, 5, 7, 8, 10, 12 => day <= 31,
        2 => if (isLeapYear(year)) day <= 29 else day <= 28,
        else => false,
    };
}

test "Valid times" {
    const testing = std.testing;
    const d1 = try Date.parseRFC3339("2018-12-20T00:00:00Z");
    const d2 = try Date.parseRFC3339("2019-12-20T00:00:00Z");

    try testing.expectEqual(2018, d1.year);
    try testing.expectEqual(2019, d2.year);
    try testing.expect(d1.lt(d2));
    try testing.expect(d2.gt(d1));
}
