const std = @import("std");

pub const Date = struct {
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

    pub fn format(date: Date, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        return writer.print("{}-{}-{}T{}:{}:{}Z", .{ date.year, date.month, date.day, date.hour, date.minute, date.second });
    }

    // FIXME: leap seconds?
    pub fn unixEpoch(date: Date) u64 {
        var total_days: usize = 0;

        const date_year = @as(usize, @intCast(date.year));

        for (1970..date_year) |year| {
            if (isLeapYear(usize, year)) {
                total_days += 366;
            } else {
                total_days += 365;
            }
        }

        for (1..date.month) |month| {
            total_days += daysInMonth(usize, date_year, @as(u8, @intCast(month)));
        }

        for (1..date.day) |_| {
            total_days += 1;
        }

        var total_seconds: u64 = total_days * 24 * 60 * 60;

        total_seconds += @as(u64, date.hour) * 60 * 60;
        total_seconds += @as(u64, date.minute) * 60;
        total_seconds += date.second;

        return total_seconds;
    }

    pub fn isDayMonthYearValid(comptime T: type, year: T, month: u8, day: u8) bool {
        return switch (month) {
            // 30 days has september, april june and november
            4, 6, 9, 11 => day <= 30,
            1, 3, 5, 7, 8, 10, 12 => day <= 31,
            2 => if (isLeapYear(T, year)) day <= 29 else day <= 28,
            else => false,
        };
    }
};

pub fn daysInMonth(comptime T: type, year: T, month: u8) u8 {
    return switch (month) {
        4, 6, 9, 11 => 30,
        1, 3, 5, 7, 8, 10, 12 => 31,
        2 => if (isLeapYear(T, year)) 29 else 28,
        else => unreachable,
    };
}

fn isLeapYear(comptime T: type, year: T) bool {
    if (@mod(year, 400) == 0) return true;
    if (@mod(year, 100) == 0) return false;
    if (@mod(year, 4) == 0) return true;

    return false;
}
