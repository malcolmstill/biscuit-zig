const std = @import("std");
const ziglyph = @import("ziglyph");
const Term = @import("biscuit-builder").Term;
const Fact = @import("biscuit-builder").Fact;
const Check = @import("biscuit-builder").Check;
const Rule = @import("biscuit-builder").Rule;
const Predicate = @import("biscuit-builder").Predicate;
const Expression = @import("biscuit-builder").Expression;
const Scope = @import("biscuit-builder").Scope;
const Date = @import("biscuit-builder").Date;
const Policy = @import("biscuit-builder").Policy;
const Ed25519 = std.crypto.sign.Ed25519;

const log = std.log.scoped(.parser);

pub const Parser = struct {
    input: []const u8,
    offset: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Parser {
        return .{ .input = input, .allocator = allocator };
    }

    pub fn fact(parser: *Parser) !Fact {
        return .{ .predicate = try parser.factPredicate(), .variables = null };
    }

    pub fn factPredicate(parser: *Parser) !Predicate {
        var terms = std.ArrayList(Term).init(parser.allocator);

        const name = parser.readName();

        parser.skipWhiteSpace();

        try parser.consume("(");

        while (true) {
            parser.skipWhiteSpace();

            try terms.append(try parser.factTerm());

            if (parser.peek()) |peeked| {
                if (peeked != ',') break;
            } else {
                break;
            }
        }

        try parser.consume(")");

        return .{ .name = name, .terms = terms };
    }

    pub fn predicate(parser: *Parser) !Predicate {
        var terms = std.ArrayList(Term).init(parser.allocator);

        const name = parser.readName();

        parser.skipWhiteSpace();

        try parser.consume("(");

        while (true) {
            parser.skipWhiteSpace();

            try terms.append(try parser.term());

            if (parser.startsWithConsuming(",")) continue;

            break;
        }

        try parser.consume(")");

        return .{ .name = name, .terms = terms };
    }

    pub fn term(parser: *Parser) !Term {
        const rst = parser.rest();

        variable_blk: {
            var term_parser = Parser.init(parser.allocator, rst);

            const value = term_parser.variable() catch break :variable_blk;

            parser.offset += term_parser.offset;

            return .{ .variable = value };
        }

        string_blk: {
            var term_parser = Parser.init(parser.allocator, rst);

            const value = term_parser.string() catch break :string_blk;

            parser.offset += term_parser.offset;

            return .{ .string = value };
        }

        date_blk: {
            var term_parser = Parser.init(parser.allocator, rst);

            const value = term_parser.date() catch break :date_blk;

            parser.offset += term_parser.offset;

            return .{ .date = value };
        }

        number_blk: {
            var term_parser = Parser.init(parser.allocator, rst);

            const value = term_parser.number(i64) catch break :number_blk;

            parser.offset += term_parser.offset;

            return .{ .integer = value };
        }

        bool_blk: {
            var term_parser = Parser.init(parser.allocator, rst);

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
            var term_parser = Parser.init(parser.allocator, rst);

            const value = term_parser.string() catch break :string_blk;

            parser.offset += term_parser.offset;

            return .{ .string = value };
        }

        date_blk: {
            var term_parser = Parser.init(parser.allocator, rst);

            const value = term_parser.date() catch break :date_blk;

            parser.offset += term_parser.offset;

            return .{ .date = value };
        }

        number_blk: {
            var term_parser = Parser.init(parser.allocator, rst);

            const value = term_parser.number(i64) catch break :number_blk;

            parser.offset += term_parser.offset;

            return .{ .integer = value };
        }

        bool_blk: {
            var term_parser = Parser.init(parser.allocator, rst);

            const value = term_parser.boolean() catch break :bool_blk;

            parser.offset += term_parser.offset;

            return .{ .bool = value };
        }

        return error.NoFactTermFound;
    }

    pub fn policy(parser: *Parser) !Policy {
        const kind: Policy.Kind = if (parser.startsWithConsuming("allow if"))
            .allow
        else if (parser.startsWithConsuming("deny if"))
            .deny
        else
            return error.UnexpectedPolicyKind;

        const queries = try parser.checkBody();

        return .{ .kind = kind, .queries = queries };
    }

    pub fn check(parser: *Parser) !Check {
        const kind: Check.Kind = if (parser.startsWithConsuming("check if"))
            .one
        else if (parser.startsWithConsuming("check all"))
            .all
        else
            return error.UnexpectedCheckKind;

        const queries = try parser.checkBody();

        return .{ .kind = kind, .queries = queries };
    }

    fn checkBody(parser: *Parser) !std.ArrayList(Rule) {
        var queries = std.ArrayList(Rule).init(parser.allocator);

        const required_body = try parser.ruleBody();

        try queries.append(.{
            .head = .{ .name = "query", .terms = std.ArrayList(Term).init(parser.allocator) },
            .body = required_body.predicates,
            .expressions = required_body.expressions,
            .scopes = required_body.scopes,
            .variables = null,
        });

        while (true) {
            parser.skipWhiteSpace();

            if (!parser.startsWith("or")) break;

            try parser.consume("or");

            const body = try parser.ruleBody();

            try queries.append(.{
                .head = .{ .name = "query", .terms = std.ArrayList(Term).init(parser.allocator) },
                .body = body.predicates,
                .expressions = body.expressions,
                .scopes = body.scopes,
                .variables = null,
            });
        }

        return queries;
    }

    pub fn rule(parser: *Parser) !Rule {
        const head = try parser.predicate();

        parser.skipWhiteSpace();

        try parser.consume("<-");

        const body = try parser.ruleBody();

        return .{
            .head = head,
            .body = body.predicates,
            .expressions = body.expressions,
            .scopes = body.scopes,
            .variables = null,
        };
    }

    pub fn ruleBody(parser: *Parser) !struct { predicates: std.ArrayList(Predicate), expressions: std.ArrayList(Expression), scopes: std.ArrayList(Scope) } {
        var predicates = std.ArrayList(Predicate).init(parser.allocator);
        var expressions = std.ArrayList(Expression).init(parser.allocator);
        var scps = std.ArrayList(Scope).init(parser.allocator);

        while (true) {
            parser.skipWhiteSpace();

            // Try parsing a predicate
            predicate_blk: {
                var predicate_parser = Parser.init(parser.allocator, parser.rest());

                const p = predicate_parser.predicate() catch break :predicate_blk;

                parser.offset += predicate_parser.offset;

                try predicates.append(p);

                parser.skipWhiteSpace();

                if (parser.startsWithConsuming(",")) continue;
            }

            // Otherwise try parsing an expression
            expression_blk: {
                var expression_parser = Parser.init(parser.allocator, parser.rest());

                const e = expression_parser.expression() catch break :expression_blk;

                parser.offset += expression_parser.offset;

                try expressions.append(e);

                parser.skipWhiteSpace();

                if (parser.startsWithConsuming(",")) continue;
            }

            // We haven't found a predicate or expression so we're done,
            // other than potentially parsing a scope
            break;
        }

        scopes_blk: {
            var scope_parser = Parser.init(parser.allocator, parser.rest());

            const s = scope_parser.scopes(parser.allocator) catch break :scopes_blk;

            parser.offset += scope_parser.offset;

            scps = s;
        }

        return .{ .predicates = predicates, .expressions = expressions, .scopes = scps };
    }

    fn variable(parser: *Parser) ![]const u8 {
        try parser.consume("$");

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

    // FIXME: properly implement string parsing
    fn string(parser: *Parser) ![]const u8 {
        try parser.consume("\"");

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

        try parser.consume("-");

        const month = try parser.number(u8);
        if (month < 1 or month > 12) return error.MonthOutOfRange;

        try parser.consume("-");

        const day = try parser.number(u8);
        if (!Date.isDayMonthYearValid(i32, year, month, day)) return error.InvalidDayMonthYearCombination;

        try parser.consume("T");

        const hour = try parser.number(u8);
        if (hour > 23) return error.HoyrOutOfRange;

        try parser.consume(":");

        const minute = try parser.number(u8);
        if (minute > 59) return error.MinuteOutOfRange;

        try parser.consume(":");

        const second = try parser.number(u8);
        if (second > 59) return error.SecondOutOfRange;

        try parser.consume("Z");

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
        if (parser.startsWithConsuming("true")) return true;

        if (parser.startsWithConsuming("false")) return false;

        return error.ExpectedBooleanTerm;
    }

    fn hex(parser: *Parser) ![]const u8 {
        const start = parser.offset;

        for (parser.rest()) |c| {
            if (ziglyph.isHexDigit(c)) {
                parser.offset += 1;
                continue;
            }

            break;
        }

        return parser.input[start..parser.offset];
    }

    fn expression(parser: *Parser) ParserError!Expression {
        parser.skipWhiteSpace();
        const e = try parser.expr();

        return e;
    }

    fn expr(parser: *Parser) ParserError!Expression {
        var e = try parser.expr1();

        while (true) {
            parser.skipWhiteSpace();
            if (parser.rest().len == 0) break;

            const op = parser.binaryOp0() catch break;

            parser.skipWhiteSpace();

            const e2 = try parser.expr1();

            e = try Expression.binary(parser.allocator, op, e, e2);
        }

        return e;
    }

    fn binaryOp0(parser: *Parser) ParserError!Expression.BinaryOp {
        if (parser.startsWithConsuming("&&")) return .@"and";
        if (parser.startsWithConsuming("||")) return .@"or";

        return error.UnexpectedOp;
    }

    fn expr1(parser: *Parser) ParserError!Expression {
        var e = try parser.expr2();

        while (true) {
            parser.skipWhiteSpace();
            if (parser.rest().len == 0) break;

            const op = parser.binaryOp1() catch break;

            parser.skipWhiteSpace();

            const e2 = try parser.expr2();

            e = try Expression.binary(parser.allocator, op, e, e2);
        }

        return e;
    }

    fn binaryOp1(parser: *Parser) ParserError!Expression.BinaryOp {
        if (parser.startsWithConsuming("<=")) return .less_or_equal;
        if (parser.startsWithConsuming(">=")) return .greater_or_equal;
        if (parser.startsWithConsuming("<")) return .less_than;
        if (parser.startsWithConsuming(">")) return .greater_than;
        if (parser.startsWithConsuming("==")) return .equal;
        if (parser.startsWithConsuming("!=")) return .not_equal;

        return error.UnexpectedOp;
    }

    fn expr2(parser: *Parser) ParserError!Expression {
        var e = try parser.expr3();

        while (true) {
            parser.skipWhiteSpace();
            if (parser.rest().len == 0) break;

            const op = parser.binaryOp2() catch break;

            parser.skipWhiteSpace();

            const e2 = try parser.expr3();

            e = try Expression.binary(parser.allocator, op, e, e2);
        }

        return e;
    }

    fn binaryOp2(parser: *Parser) ParserError!Expression.BinaryOp {
        if (parser.startsWithConsuming("+")) return .add;
        if (parser.startsWithConsuming("-")) return .sub;

        return error.UnexpectedOp;
    }

    fn expr3(parser: *Parser) ParserError!Expression {
        var e = try parser.expr4();

        while (true) {
            parser.skipWhiteSpace();
            if (parser.rest().len == 0) break;

            const op = parser.binaryOp3() catch break;

            parser.skipWhiteSpace();

            const e2 = try parser.expr4();

            e = try Expression.binary(parser.allocator, op, e, e2);
        }

        return e;
    }

    fn binaryOp3(parser: *Parser) ParserError!Expression.BinaryOp {
        if (parser.startsWithConsuming("^")) return .bitwise_xor;

        return error.UnexpectedOp;
    }

    fn expr4(parser: *Parser) ParserError!Expression {
        var e = try parser.expr5();

        while (true) {
            parser.skipWhiteSpace();
            if (parser.rest().len == 0) break;

            const op = parser.binaryOp4() catch break;

            parser.skipWhiteSpace();

            const e2 = try parser.expr5();

            e = try Expression.binary(parser.allocator, op, e, e2);
        }

        return e;
    }

    fn binaryOp4(parser: *Parser) ParserError!Expression.BinaryOp {
        if (parser.startsWith("|") and !parser.startsWith("||")) {
            try parser.consume("|");
            return .bitwise_or;
        }

        return error.UnexpectedOp;
    }

    fn expr5(parser: *Parser) ParserError!Expression {
        var e = try parser.expr6();

        while (true) {
            parser.skipWhiteSpace();
            if (parser.rest().len == 0) break;

            const op = parser.binaryOp5() catch break;

            parser.skipWhiteSpace();

            const e2 = try parser.expr6();

            e = try Expression.binary(parser.allocator, op, e, e2);
        }

        return e;
    }

    fn binaryOp5(parser: *Parser) ParserError!Expression.BinaryOp {
        if (parser.startsWith("&") and !parser.startsWith("&&")) {
            try parser.consume("&");
            return .bitwise_and;
        }

        return error.UnexpectedOp;
    }

    fn expr6(parser: *Parser) ParserError!Expression {
        var e = try parser.expr7();

        while (true) {
            parser.skipWhiteSpace();
            if (parser.rest().len == 0) break;

            const op = parser.binaryOp6() catch break;

            parser.skipWhiteSpace();

            const e2 = try parser.expr7();

            e = try Expression.binary(parser.allocator, op, e, e2);
        }

        return e;
    }

    fn binaryOp6(parser: *Parser) ParserError!Expression.BinaryOp {
        if (parser.startsWithConsuming("*")) return .mul;
        if (parser.startsWithConsuming("/")) return .div;

        return error.UnexpectedOp;
    }

    fn expr7(parser: *Parser) ParserError!Expression {
        const e1 = try parser.exprTerm();

        parser.skipWhiteSpace();

        if (!parser.startsWith(".")) return e1;
        try parser.consume(".");

        const op = try parser.binaryOp7();
        parser.skipWhiteSpace();

        try parser.consume("(");

        parser.skipWhiteSpace();

        const e2 = try parser.expr();

        parser.skipWhiteSpace();

        try parser.consume(")");

        parser.skipWhiteSpace();

        return try Expression.binary(parser.allocator, op, e1, e2);
    }

    fn binaryOp7(parser: *Parser) ParserError!Expression.BinaryOp {
        if (parser.startsWithConsuming("contains")) return .contains;
        if (parser.startsWithConsuming("starts_with")) return .prefix;
        if (parser.startsWithConsuming("ends_with")) return .suffix;
        if (parser.startsWithConsuming("matches")) return .regex;

        return error.UnexpectedOp;
    }

    fn exprTerm(parser: *Parser) ParserError!Expression {
        // Try to parse unary
        unary_blk: {
            var unary_parser = Parser.init(parser.allocator, parser.rest());

            const p = unary_parser.unary() catch break :unary_blk;

            parser.offset += unary_parser.offset;

            return p;
        }

        // Otherwise we expect term
        const term1 = try parser.term();

        return try Expression.value(term1);
    }

    fn unary(parser: *Parser) ParserError!Expression {
        parser.skipWhiteSpace();

        if (parser.startsWithConsuming("!")) {
            parser.skipWhiteSpace();

            const e = try parser.expr();

            return try Expression.unary(parser.allocator, .negate, e);
        }

        if (parser.startsWith("(")) {
            return try parser.unaryParens();
        }

        var e: Expression = undefined;
        if (parser.term()) |t1| {
            parser.skipWhiteSpace();
            e = try Expression.value(t1);
        } else |_| {
            e = try parser.unaryParens();
            parser.skipWhiteSpace();
        }

        if (parser.consume(".length()")) |_| {
            return try Expression.unary(parser.allocator, .length, e);
        } else |_| {
            return error.UnexpectedToken;
        }

        return error.UnexpectedToken;
    }

    fn unaryParens(parser: *Parser) ParserError!Expression {
        try parser.consume("(");

        parser.skipWhiteSpace();

        const e = try parser.expr();

        parser.skipWhiteSpace();

        try parser.consume(")");

        return try Expression.unary(parser.allocator, .parens, e);
    }

    fn scopes(parser: *Parser, allocator: std.mem.Allocator) !std.ArrayList(Scope) {
        try parser.consume("trusting");

        parser.skipWhiteSpace();

        var scps = std.ArrayList(Scope).init(allocator);

        while (true) {
            parser.skipWhiteSpace();

            const scp = try parser.scope(allocator);

            try scps.append(scp);

            parser.skipWhiteSpace();

            if (!parser.startsWith(",")) break;

            try parser.consume(",");
        }

        return scps;
    }

    fn scope(parser: *Parser, _: std.mem.Allocator) !Scope {
        parser.skipWhiteSpace();

        if (parser.startsWith("authority")) {
            try parser.consume("authority");

            return .{ .authority = {} };
        }

        if (parser.startsWith("previous")) {
            try parser.consume("previous");

            return .{ .previous = {} };
        }

        if (parser.startsWith("{")) {
            try parser.consume("{");

            const parameter = parser.readName();

            try parser.consume("}");

            return .{ .parameter = parameter };
        }

        return .{ .public_key = try parser.publicKey() };
    }

    /// Parser a public key. Currently only supports ed25519.
    fn publicKey(parser: *Parser) !Ed25519.PublicKey {
        try parser.consume("ed25519/");

        const h = try parser.hex();

        var out_buf: [Ed25519.PublicKey.encoded_length]u8 = undefined;

        _ = try std.fmt.hexToBytes(out_buf[0..], h);

        return try Ed25519.PublicKey.fromBytes(out_buf);
    }

    fn peek(parser: *Parser) ?u8 {
        if (parser.input[parser.offset..].len == 0) return null;

        return parser.input[parser.offset];
    }

    fn rest(parser: *Parser) []const u8 {
        return parser.input[parser.offset..];
    }

    /// Expect and consume string. Return error.UnexpectedString if
    /// str is not the start of remaining parser input.
    fn consume(parser: *Parser, str: []const u8) !void {
        if (!std.mem.startsWith(u8, parser.rest(), str)) return error.UnexpectedString;

        parser.offset += str.len;
    }

    /// Returns true if the remaining parser input starts with str
    ///
    /// Does not consume any input.
    ///
    /// See also `fn startsWithConsuming`
    fn startsWith(parser: *Parser, str: []const u8) bool {
        return std.mem.startsWith(u8, parser.rest(), str);
    }

    /// Returns true if the remaining parse input starts with str. If
    /// it does start with that string, the parser consumes the string.
    ///
    /// See also `fn startsWith`
    fn startsWithConsuming(parser: *Parser, str: []const u8) bool {
        if (parser.startsWith(str)) {
            parser.offset += str.len; // Consume
            return true;
        }

        return false;
    }

    /// Reject char. Does not consume the character
    fn reject(parser: *Parser, char: u8) !void {
        const peeked = parser.peek() orelse return error.ExpectedMoreInput;
        if (peeked == char) return error.DisallowedChar;
    }

    // FIXME: this should error?
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

const ParserError = error{
    ExpectedMoreInput,
    DisallowedChar,
    UnexpectedString,
    ExpectedChar,
    NoFactTermFound,
    UnexpectedOp,
    MissingLeftParen,
    MissingRightParen,
    OutOfMemory,
    UnexpectedToken,
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

// test "parse rule body" {
//     const testing = std.testing;
//     const input: []const u8 =
//         \\query(false) <- read(true), write(false)
//     ;

//     var parser = Parser.init(testing.allocator, input);

//     const r = try parser.rule();
//     defer r.deinit();

//     std.debug.print("{any}\n", .{r});
// }

// test "parse rule body with variables" {
//     const testing = std.testing;
//     const input: []const u8 =
//         \\query($0) <- read($0), write(false)
//     ;

//     var parser = Parser.init(testing.allocator, input);

//     const r = try parser.rule();
//     defer r.deinit();

//     std.debug.print("{any}\n", .{r});
// }

// test "parse check" {
//     const testing = std.testing;
//     const input: []const u8 =
//         \\check if right($0, $1), resource($0), operation($1)
//     ;

//     var parser = Parser.init(testing.allocator, input);

//     const r = try parser.check();
//     defer r.deinit();

//     std.debug.print("{any}\n", .{r});
// }

test "parse check with expression" {
    const testing = std.testing;
    const input: []const u8 =
        \\check if right($0, $1), resource($0), operation($1), $0.contains("file")
    ;

    var parser = Parser.init(testing.allocator, input);

    const r = try parser.check();
    defer r.deinit();
}
