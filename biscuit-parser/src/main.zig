const std = @import("std");
const ziglyph = @import("ziglyph");
const datalog = @import("biscuit-datalog");
const Term = @import("biscuit-builder").Term;
const Fact = @import("biscuit-builder").Fact;
const Check = @import("biscuit-builder").Check;
const Rule = @import("biscuit-builder").Rule;
const Predicate = @import("biscuit-builder").Predicate;
const Expression = @import("biscuit-builder").Expression;
const Scope = @import("biscuit-builder").Scope;
const Date = @import("biscuit-builder").Date;
const rfc3339 = @import("rfc3339.zig");

pub const Parser = struct {
    input: []const u8,
    offset: usize = 0,

    pub fn init(input: []const u8) Parser {
        return .{ .input = input };
    }

    pub fn fact(parser: *Parser, allocator: std.mem.Allocator) !Fact {
        return .{ .predicate = try parser.factPredicate(allocator), .variables = null };
    }

    pub fn factPredicate(parser: *Parser, allocator: std.mem.Allocator) !Predicate {
        const name = parser.readName();

        std.debug.print("name = {s}\n", .{name});

        parser.skipWhiteSpace();

        // Consume left paren
        try parser.expect('(');

        // Parse terms
        var terms = std.ArrayList(Term).init(allocator);

        var it = parser.factTermsIterator();
        while (try it.next()) |trm| {
            try terms.append(trm);

            if (parser.peek()) |peeked| {
                if (peeked != ',') break;
            } else {
                break;
            }
        }

        try parser.expect(')');

        return .{ .name = name, .terms = terms };
    }

    const FactTermIterator = struct {
        parser: *Parser,

        pub fn next(it: *FactTermIterator) !?Term {
            it.parser.skipWhiteSpace();

            return try it.parser.factTerm();
        }
    };

    pub fn factTermsIterator(parser: *Parser) FactTermIterator {
        return .{ .parser = parser };
    }

    const TermIterator = struct {
        parser: *Parser,

        pub fn next(it: *TermIterator) !?Term {
            it.parser.skipWhiteSpace();

            return try it.parser.term();
        }
    };

    pub fn termsIterator(parser: *Parser) TermIterator {
        return .{ .parser = parser };
    }

    pub fn term(parser: *Parser) !Term {
        const rst = parser.rest();

        variable_blk: {
            var term_parser = Parser.init(rst);

            const value = term_parser.variable() catch break :variable_blk;

            parser.offset += term_parser.offset;

            return .{ .variable = value };
        }

        string_blk: {
            var term_parser = Parser.init(rst);

            const value = term_parser.string() catch break :string_blk;

            parser.offset += term_parser.offset;

            return .{ .string = value };
        }

        date_blk: {
            var term_parser = Parser.init(rst);

            const value = term_parser.date() catch break :date_blk;

            parser.offset += term_parser.offset;

            return .{ .date = value };
        }

        number_blk: {
            var term_parser = Parser.init(rst);

            const value = term_parser.number(i64) catch break :number_blk;

            parser.offset += term_parser.offset;

            return .{ .integer = value };
        }

        bool_blk: {
            var term_parser = Parser.init(rst);

            const value = term_parser.boolean() catch break :bool_blk;

            parser.offset += term_parser.offset;

            return .{ .bool = value };
        }

        return error.NoFactTermFound;
    }

    pub fn factTerm(parser: *Parser) !Term {
        const rst = parser.rest();

        try parser.reject('$'); // Variables are disallowed in a fact term

        string_blk: {
            var term_parser = Parser.init(rst);

            const value = term_parser.string() catch break :string_blk;

            parser.offset += term_parser.offset;

            return .{ .string = value };
        }

        date_blk: {
            var term_parser = Parser.init(rst);

            const value = term_parser.date() catch break :date_blk;

            parser.offset += term_parser.offset;

            return .{ .date = value };
        }

        number_blk: {
            var term_parser = Parser.init(rst);

            const value = term_parser.number(i64) catch break :number_blk;

            parser.offset += term_parser.offset;

            return .{ .integer = value };
        }

        bool_blk: {
            var term_parser = Parser.init(rst);

            const value = term_parser.boolean() catch break :bool_blk;

            parser.offset += term_parser.offset;

            return .{ .bool = value };
        }

        return error.NoFactTermFound;
    }

    pub fn predicate(parser: *Parser, allocator: std.mem.Allocator) !Predicate {
        const name = parser.readName();

        parser.skipWhiteSpace();

        // Consume left paren
        try parser.expect('(');

        // Parse terms
        var terms = std.ArrayList(Term).init(allocator);

        var it = parser.termsIterator();
        while (try it.next()) |trm| {
            try terms.append(trm);

            if (parser.peek()) |peeked| {
                if (peeked == ',') {
                    parser.offset += 1;
                    continue;
                }
            }

            break;
        }

        try parser.expect(')');

        return .{ .name = name, .terms = terms };
    }

    fn variable(parser: *Parser) ![]const u8 {
        try parser.expect('$');

        const start = parser.offset;

        for (parser.rest()) |c| {
            if (ziglyph.isAlphaNum(c) or c == '_') {
                parser.offset += 1;
                continue;
            }

            break;
        }

        return parser.input[start..parser.offset];
    }

    fn string(parser: *Parser) ![]const u8 {
        try parser.expect('"');

        const start = parser.offset;

        while (parser.peek()) |peeked| {
            defer parser.offset += 1;
            if (peeked == '"') {
                return parser.input[start..parser.offset];
            }
        }

        return error.ExpectedStringTerm;
    }

    fn date(parser: *Parser) !u64 {
        const year = try parser.number(i32);

        try parser.expect('-');

        const month = try parser.number(u8);
        if (month < 1 or month > 12) return error.MonthOutOfRange;

        try parser.expect('-');

        const day = try parser.number(u8);
        if (!rfc3339.isDayMonthYearValid(year, month, day)) return error.InvalidDayMonthYearCombination;

        try parser.expect('T');

        const hour = try parser.number(u8);
        if (hour > 23) return error.HoyrOutOfRange;

        try parser.expect(':');

        const minute = try parser.number(u8);
        if (minute > 59) return error.MinuteOutOfRange;

        try parser.expect(':');

        const second = try parser.number(u8);
        if (second > 59) return error.SecondOutOfRange;

        try parser.expect('Z');

        const d: Date = .{
            .year = year,
            .month = month,
            .day = day,
            .hour = hour,
            .minute = minute,
            .second = second,
            .nanosecond = 0,
            .utc_offset = 0,
        };

        return d.unixEpoch();
    }

    fn number(parser: *Parser, comptime T: type) !T {
        const start = parser.offset;

        for (parser.rest()) |c| {
            if (ziglyph.isAsciiDigit(c)) {
                parser.offset += 1;
                continue;
            }

            break;
        }

        const text = parser.input[start..parser.offset];

        return try std.fmt.parseInt(T, text, 10);
    }

    fn boolean(parser: *Parser) !bool {
        if (std.mem.startsWith(u8, parser.rest(), "true")) {
            parser.offset += "term".len;
            return true;
        }

        if (std.mem.startsWith(u8, parser.rest(), "false")) {
            parser.offset += "false".len;
            return false;
        }

        return error.ExpectedBooleanTerm;
    }

    pub fn check(parser: *Parser, allocator: std.mem.Allocator) !Check {
        var kind: datalog.Check.Kind = undefined;

        if (std.mem.startsWith(u8, parser.rest(), "check if")) {
            parser.offset += "check if".len;
            kind = .one;
        } else if (std.mem.startsWith(u8, parser.rest(), "check all")) {
            parser.offset += "check all".len;
            kind = .all;
        } else {
            return error.UnexpectedCheckKind;
        }

        const queries = try parser.checkBody(allocator);

        return .{ .kind = kind, .queries = queries };
    }

    fn checkBody(parser: *Parser, allocator: std.mem.Allocator) !std.ArrayList(Rule) {
        var queries = std.ArrayList(Rule).init(allocator);

        const required_body = try parser.ruleBody(allocator);

        try queries.append(.{
            .head = .{ .name = "query", .terms = std.ArrayList(Term).init(allocator) },
            .body = required_body.predicates,
            .expressions = required_body.expressions,
            .scopes = required_body.scopes,
            .variables = null,
        });

        while (true) {
            parser.skipWhiteSpace();

            if (!std.mem.startsWith(u8, parser.rest(), "or")) break;

            parser.offset += "or".len;

            const body = try parser.ruleBody(allocator);

            try queries.append(.{
                .head = .{ .name = "query", .terms = std.ArrayList(Term).init(allocator) },
                .body = body.predicates,
                .expressions = body.expressions,
                .scopes = body.scopes,
                .variables = null,
            });
        }

        return queries;
    }

    pub fn rule(parser: *Parser, allocator: std.mem.Allocator) !Rule {
        const head = try parser.predicate(allocator);

        parser.skipWhiteSpace();

        if (!std.mem.startsWith(u8, parser.rest(), "<-")) return error.ExpectedArrow;

        parser.offset += "<-".len;

        const body = try parser.ruleBody(allocator);

        return .{
            .head = head,
            .body = body.predicates,
            .expressions = body.expressions,
            .scopes = body.scopes,
            .variables = null,
        };
    }

    pub fn ruleBody(parser: *Parser, allocator: std.mem.Allocator) !struct { predicates: std.ArrayList(Predicate), expressions: std.ArrayList(Expression), scopes: std.ArrayList(Scope) } {
        var predicates = std.ArrayList(Predicate).init(allocator);
        var expressions = std.ArrayList(Expression).init(allocator);
        var scopes = std.ArrayList(Scope).init(allocator);

        while (true) {
            parser.skipWhiteSpace();
            std.debug.print("{s}: \"{s}\"\n", .{ @src().fn_name, parser.rest() });

            // Try parsing a predicate
            predicate_blk: {
                var predicate_parser = Parser.init(parser.rest());

                const p = predicate_parser.predicate(allocator) catch break :predicate_blk;

                parser.offset += predicate_parser.offset;

                try predicates.append(p);

                parser.skipWhiteSpace();

                if (parser.peek()) |peeked| {
                    if (peeked == ',') {
                        parser.offset += 1;
                        continue;
                    }
                }
            }

            // Otherwise try parsing an expression
            expression_blk: {
                var expression_parser = Parser.init(parser.rest());

                const e = expression_parser.expression(allocator) catch break :expression_blk;

                parser.offset += expression_parser.offset;

                try expressions.append(e);

                parser.skipWhiteSpace();

                if (parser.peek()) |peeked| {
                    if (peeked == ',') {
                        parser.offset += 1;
                        continue;
                    }
                }
            }

            // We haven't found a predicate or expression so we're done,
            // other than potentially parsing a scope
            break;
        }

        scope_blk: {
            var scope_parser = Parser.init(parser.rest());

            const s = scope_parser.scope(allocator) catch break :scope_blk;

            parser.offset += scope_parser.offset;

            try scopes.append(s);
        }

        return .{ .predicates = predicates, .expressions = expressions, .scopes = scopes };
    }

    fn expression(_: *Parser, _: std.mem.Allocator) !Expression {
        return error.Unimplemented;
    }

    fn scope(_: *Parser, _: std.mem.Allocator) !Scope {
        return error.Unimplemented;
    }

    fn peek(parser: *Parser) ?u8 {
        if (parser.input[parser.offset..].len == 0) return null;

        return parser.input[parser.offset];
    }

    fn rest(parser: *Parser) []const u8 {
        return parser.input[parser.offset..];
    }

    /// Expect (and consume) char.
    fn expect(parser: *Parser, char: u8) !void {
        const peeked = parser.peek() orelse return error.ExpectedMoreInput;
        if (peeked != char) return error.ExpectedChar;

        parser.offset += 1;
    }

    /// Reject char. Does not consume the character
    fn reject(parser: *Parser, char: u8) !void {
        const peeked = parser.peek() orelse return error.ExpectedMoreInput;
        if (peeked == char) return error.DisallowedChar;
    }

    fn readName(parser: *Parser) []const u8 {
        const start = parser.offset;

        for (parser.rest()) |c| {
            if (ziglyph.isAlphaNum(c) or c == '_' or c == ':') {
                parser.offset += 1;
                continue;
            }

            break;
        }

        return parser.input[start..parser.offset];
    }

    fn skipWhiteSpace(parser: *Parser) void {
        for (parser.rest()) |c| {
            if (ziglyph.isWhiteSpace(c)) {
                parser.offset += 1;
                continue;
            }

            break;
        }
    }
};

// test "parse fact predicate" {
//     const testing = std.testing;
//     const input: []const u8 =
//         \\read(true)
//     ;

//     var parser = Parser.init(input);

//     const r = try parser.factPredicate(testing.allocator);
//     defer r.deinit();

//     std.debug.print("{any}\n", .{r});
// }

test "parse rule body" {
    const testing = std.testing;
    const input: []const u8 =
        \\query(false) <- read(true), write(false)
    ;

    var parser = Parser.init(input);

    const r = try parser.rule(testing.allocator);
    defer r.deinit();

    std.debug.print("{any}\n", .{r});
}

test "parse rule body with variables" {
    const testing = std.testing;
    const input: []const u8 =
        \\query($0) <- read($0), write(false)
    ;

    var parser = Parser.init(input);

    const r = try parser.rule(testing.allocator);
    defer r.deinit();

    std.debug.print("{any}\n", .{r});
}

test "parse check" {
    const testing = std.testing;
    const input: []const u8 =
        \\check if right($0, $1), resource($0), operation($1)
    ;

    var parser = Parser.init(input);

    const r = try parser.check(testing.allocator);
    defer r.deinit();

    std.debug.print("{any}\n", .{r});
}

// test "Date" {
//     _ = @import("rfc3339.zig");
// }
