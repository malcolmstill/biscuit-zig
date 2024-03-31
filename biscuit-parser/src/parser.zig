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
const Set = @import("biscuit-builder").Set;
const Ed25519 = std.crypto.sign.Ed25519;

const log = std.log.scoped(.parser);

pub const Parser = struct {
    input: []const u8,
    offset: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Parser {
        return .{ .input = input, .allocator = allocator };
    }

    /// Return a new temporary parser with the current state of parent parser
    /// for attempting to parse one of choice of things.
    ///
    /// E.g. when we parse a term we try parse each subtype of term with a temporary
    /// parser.
    pub fn temporary(parser: *Parser) Parser {
        return Parser.init(parser.allocator, parser.rest());
    }

    /// Try to parse fact
    ///
    /// E.g. read(1, "hello") will parse successfully, but read($foo, "hello")
    /// will fail because it contains a variable `$foo`.
    pub fn fact(parser: *Parser) !Fact {
        return .{ .predicate = try parser.predicate(.fact), .variables = null };
    }

    pub fn predicate(parser: *Parser, kind: enum { fact, rule }) !Predicate {
        var terms = std.ArrayList(Term).init(parser.allocator);

        const predicate_name = try parser.name();

        try parser.consume("(");

        while (true) {
            parser.skipWhiteSpace();

            try terms.append(try parser.term(switch (kind) {
                .rule => .allow,
                .fact => .disallow,
            }));

            parser.skipWhiteSpace();

            if (!parser.startsWithConsuming(",")) break;
        }

        try parser.consume(")");

        return .{ .name = predicate_name, .terms = terms };
    }

    /// Try to parse a term
    ///
    /// Does not consume `parser` input on failure.
    fn term(parser: *Parser, variables: AllowVariables) ParserError!Term {
        if (variables == .disallow) {
            try parser.reject("$"); // Variables are disallowed in a fact term
        } else {
            variable_blk: {
                var term_parser = parser.temporary();

                const value = term_parser.variable() catch break :variable_blk;

                parser.offset += term_parser.offset;

                return .{ .variable = value };
            }
        }

        string_blk: {
            var term_parser = parser.temporary();

            const value = term_parser.string() catch break :string_blk;

            parser.offset += term_parser.offset;

            return .{ .string = value };
        }

        date_blk: {
            var term_parser = parser.temporary();

            const value = term_parser.date() catch break :date_blk;

            parser.offset += term_parser.offset;

            return .{ .date = value };
        }

        number_blk: {
            var term_parser = parser.temporary();

            const value = term_parser.number(i64) catch break :number_blk;

            parser.offset += term_parser.offset;

            return .{ .integer = value };
        }

        bool_blk: {
            var term_parser = parser.temporary();

            const value = term_parser.boolean() catch break :bool_blk;

            parser.offset += term_parser.offset;

            return .{ .bool = value };
        }

        bytes_blk: {
            var term_parser = parser.temporary();

            const value = term_parser.bytes() catch break :bytes_blk;

            parser.offset += term_parser.offset;

            return .{ .bytes = value };
        }

        set_blk: {
            var term_parser = parser.temporary();

            const value = term_parser.set(variables) catch break :set_blk;

            parser.offset += term_parser.offset;

            return .{ .set = value };
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

        try parser.requiredWhiteSpace();

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

        try parser.requiredWhiteSpace();

        const queries = try parser.checkBody();

        return .{ .kind = kind, .queries = queries };
    }

    /// Parse check body
    ///
    /// E.g. given check if right($0, $1), resource($0), operation($1), $0.contains(\"file\") or admin(true)
    /// this will (attempt to) parse `right($0, $1), resource($0), operation($1), $0.contains(\"file\") or admin(true)`
    ///
    /// Requires at least one rule body.
    fn checkBody(parser: *Parser) !std.ArrayList(Rule) {
        var queries = std.ArrayList(Rule).init(parser.allocator);

        while (true) {
            parser.skipWhiteSpace();

            const body = try parser.ruleBody();

            try queries.append(.{
                .head = .{ .name = "query", .terms = std.ArrayList(Term).init(parser.allocator) },
                .body = body.predicates,
                .expressions = body.expressions,
                .scopes = body.scopes,
                .variables = null,
            });

            parser.skipWhiteSpace();

            if (!parser.startsWithConsuming("or")) break;
        }

        return queries;
    }

    pub fn rule(parser: *Parser) !Rule {
        const head = try parser.predicate(.rule);

        parser.skipWhiteSpace();

        try parser.consume("<-");

        parser.skipWhiteSpace();

        const body = try parser.ruleBody();

        return .{
            .head = head,
            .body = body.predicates,
            .expressions = body.expressions,
            .scopes = body.scopes,
            .variables = null,
        };
    }

    fn ruleBody(parser: *Parser) !struct { predicates: std.ArrayList(Predicate), expressions: std.ArrayList(Expression), scopes: std.ArrayList(Scope) } {
        var predicates = std.ArrayList(Predicate).init(parser.allocator);
        var expressions = std.ArrayList(Expression).init(parser.allocator);
        var scps = std.ArrayList(Scope).init(parser.allocator);

        while (true) {
            parser.skipWhiteSpace();

            const rule_body = try parser.ruleBodyElement();

            switch (rule_body) {
                .predicate => |p| try predicates.append(p),
                .expression => |e| try expressions.append(e),
            }

            parser.skipWhiteSpace();

            if (!parser.startsWithConsuming(",")) break;
        }

        scopes_blk: {
            var scope_parser = parser.temporary();

            const s = scope_parser.scopes(parser.allocator) catch break :scopes_blk;

            parser.offset += scope_parser.offset;

            scps = s;
        }

        return .{ .predicates = predicates, .expressions = expressions, .scopes = scps };
    }

    const BodyElementTag = enum {
        predicate,
        expression,
    };

    /// Try to parse a rule body element (a predicate or an expression)
    ///
    /// Does not consume `parser` input on failure.
    fn ruleBodyElement(parser: *Parser) !union(BodyElementTag) { predicate: Predicate, expression: Expression } {
        predicate_blk: {
            var predicate_parser = parser.temporary();

            const p = predicate_parser.predicate(.rule) catch break :predicate_blk;

            parser.offset += predicate_parser.offset;

            return .{ .predicate = p };
        }

        // Otherwise try parsing an expression
        expression_blk: {
            var expression_parser = parser.temporary();

            const e = expression_parser.expression() catch break :expression_blk;

            parser.offset += expression_parser.offset;

            return .{ .expression = e };
        }

        return error.ExpectedPredicateOrExpression;
    }

    fn variable(parser: *Parser) ![]const u8 {
        try parser.consume("$");

        return try parser.variableName();
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

        if (parser.rest().len == 0) return error.ParsingNumberExpectsAtLeastOneCharacter;
        const first_char = parser.rest()[0];

        if (!(isDigit(first_char) or first_char == '-')) return error.ParsingNameFirstCharacterMustBeLetter;
        parser.offset += 1;

        for (parser.rest()) |c| {
            if (isDigit(c)) {
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

    fn bytes(parser: *Parser) ![]const u8 {
        try parser.consume("hex:");

        const hex_string = try parser.hex();

        if (!(hex_string.len % 2 == 0)) return error.ExpectedEvenNumberOfHexDigis;

        const out = try parser.allocator.alloc(u8, hex_string.len / 2);

        return try std.fmt.hexToBytes(out, hex_string);
    }

    fn set(parser: *Parser, variables: AllowVariables) !Set(Term) {
        var new_set = Set(Term).init(parser.allocator);

        try parser.consume("[");

        while (true) {
            parser.skipWhiteSpace();

            // Try to parse a term. Since sets can be empty we break on catch;
            const trm = parser.term(variables) catch break;
            try new_set.add(trm);

            parser.skipWhiteSpace();

            if (!parser.startsWithConsuming(",")) break;
        }

        try parser.consume("]");

        return new_set;
    }

    fn expression(parser: *Parser) ParserError!Expression {
        parser.skipWhiteSpace();
        const e = try parser.expr0();

        return e;
    }

    fn expr0(parser: *Parser) ParserError!Expression {
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

        if (!parser.startsWithConsuming(".")) return e1;

        const op = try parser.binaryOp7();

        parser.skipWhiteSpace();

        try parser.consume("(");

        parser.skipWhiteSpace();

        const e2 = try parser.expr0();

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
            var unary_parser = parser.temporary();

            const p = unary_parser.unary() catch break :unary_blk;

            parser.offset += unary_parser.offset;

            return p;
        }

        // Otherwise we expect term
        const term1 = try parser.term(.allow);

        return try Expression.value(term1);
    }

    fn unary(parser: *Parser) ParserError!Expression {
        parser.skipWhiteSpace();

        if (parser.startsWithConsuming("!")) {
            parser.skipWhiteSpace();

            const e = try parser.expr0();

            return try Expression.unary(parser.allocator, .negate, e);
        }

        if (parser.startsWith("(")) {
            return try parser.unaryParens();
        }

        var e: Expression = undefined;
        if (parser.term(.allow)) |t1| {
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

        const e = try parser.expr0();

        parser.skipWhiteSpace();

        try parser.consume(")");

        return try Expression.unary(parser.allocator, .parens, e);
    }

    fn scopes(parser: *Parser, allocator: std.mem.Allocator) !std.ArrayList(Scope) {
        try parser.requiredWhiteSpace();

        try parser.consume("trusting");

        parser.skipWhiteSpace();

        var scps = std.ArrayList(Scope).init(allocator);

        while (true) {
            parser.skipWhiteSpace();

            const scp = try parser.scope(allocator);

            try scps.append(scp);

            parser.skipWhiteSpace();

            if (!parser.startsWithConsuming(",")) break;
        }

        return scps;
    }

    fn scope(parser: *Parser, _: std.mem.Allocator) !Scope {
        if (parser.startsWithConsuming("authority")) return .{ .authority = {} };
        if (parser.startsWithConsuming("previous")) return .{ .previous = {} };

        if (parser.startsWithConsuming("{")) {
            const parameter = try parser.name();

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
    fn reject(parser: *Parser, str: []const u8) !void {
        if (parser.startsWith(str)) return error.DisallowedChar;
    }

    fn name(parser: *Parser) ![]const u8 {
        const start = parser.offset;

        if (parser.rest().len == 0) return error.ParsingNameExpectsAtLeastOneCharacter;

        const first_codepoint = try nextCodepoint(parser.rest());

        if (!ziglyph.isLetter(first_codepoint.codepoint)) return error.ParsingNameFirstCharacterMustBeLetter;

        parser.offset += first_codepoint.len;

        while (true) {
            const next_codepoint = try nextCodepoint(parser.rest());

            if (ziglyph.isAlphaNum(next_codepoint.codepoint)) {
                parser.offset += next_codepoint.len;
                continue;
            } else if (parser.startsWith("_") or parser.startsWith(":")) {
                parser.offset += 1;
                continue;
            }

            break;
        }

        return parser.input[start..parser.offset];
    }

    fn variableName(parser: *Parser) ![]const u8 {
        const start = parser.offset;

        if (parser.rest().len == 0) return error.ParsingNameExpectsAtLeastOneCharacter;

        const first_codepoint = try nextCodepoint(parser.rest());

        if (!ziglyph.isAlphaNum(first_codepoint.codepoint)) return error.ParsingNameFirstCharacterMustBeLetter;

        parser.offset += first_codepoint.len;

        while (true) {
            const next_codepoint = try nextCodepoint(parser.rest());

            if (ziglyph.isAlphaNum(next_codepoint.codepoint)) {
                parser.offset += next_codepoint.len;
                continue;
            } else if (parser.startsWith("_") or parser.startsWith(":")) {
                parser.offset += 1;
                continue;
            }

            break;
        }

        return parser.input[start..parser.offset];
    }

    fn hex(parser: *Parser) ![]const u8 {
        const start = parser.offset;

        for (parser.rest()) |c| {
            if (isHexDigit(c)) {
                parser.offset += 1;
                continue;
            }

            break;
        }

        return parser.input[start..parser.offset];
    }

    /// Skip whitespace but the whitespace is required (i.e. we need at least one space, tab or newline)
    fn requiredWhiteSpace(parser: *Parser) !void {
        if (!(parser.startsWith(" ") or parser.startsWith("\t") or parser.startsWith("\n"))) return error.ExpectedWhiteSpace;

        parser.skipWhiteSpace();
    }

    /// Skip (optional) whitespace
    fn skipWhiteSpace(parser: *Parser) void {
        for (parser.rest()) |c| {
            if (c == ' ' or c == '\t' or c == '\n') {
                parser.offset += 1;
                continue;
            }

            break;
        }
    }
};

const AllowVariables = enum {
    allow,
    disallow,
};

fn isHexDigit(char: u8) bool {
    switch (char) {
        'a', 'b', 'c', 'd', 'e', 'f', 'A', 'B', 'C', 'D', 'E', 'F', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => return true,
        else => return false,
    }
}

fn isDigit(char: u8) bool {
    switch (char) {
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => return true,
        else => return false,
    }
}

/// Try to get the next UTF-8 codepoint from input. Returns the codepoint
/// and the number of bytes that codepoint takes up.
fn nextCodepoint(input: []const u8) !struct { codepoint: u21, len: u32 } {
    if (input.len == 0) return error.NextCodePointExpectsAtLeastOneByte;

    const first_byte = input[0];

    const byte_len = try std.unicode.utf8ByteSequenceLength(first_byte);

    if (input.len < byte_len) return error.NotEnoughInputForCodepoint;

    const codepoint = switch (byte_len) {
        1 => try std.unicode.utf8Decode(input[0..1]),
        2 => try std.unicode.utf8Decode2(input[0..2]),
        3 => try std.unicode.utf8Decode3(input[0..3]),
        4 => try std.unicode.utf8Decode4(input[0..4]),
        else => return error.IncorrectUtfDecodeLength,
    };

    return .{ .len = byte_len, .codepoint = codepoint };
}

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

test "parse predicates" {
    const testing = std.testing;

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    {
        var parser = Parser.init(arena, "read(-1, 1, \"hello world\", hex:abcd, true, false, $foo, 2024-03-30T20:48:00Z, [1, 2, 3], [])");
        const predicate = try parser.predicate(.rule);

        try testing.expectEqualStrings("read", predicate.name);
        try testing.expectEqual(-1, predicate.terms.items[0].integer);
        try testing.expectEqual(1, predicate.terms.items[1].integer);
        try testing.expectEqualStrings("hello world", predicate.terms.items[2].string);
        try testing.expectEqualStrings("\xab\xcd", predicate.terms.items[3].bytes);
        try testing.expectEqual(true, predicate.terms.items[4].bool);
        try testing.expectEqual(false, predicate.terms.items[5].bool);
        try testing.expectEqualStrings("foo", predicate.terms.items[6].variable);
        try testing.expectEqual(1711831680, predicate.terms.items[7].date);

        const set = predicate.terms.items[8].set;
        try testing.expect(set.contains(.{ .integer = 1 }));
        try testing.expect(set.contains(.{ .integer = 2 }));
        try testing.expect(set.contains(.{ .integer = 3 }));

        const empty_set = predicate.terms.items[9].set;
        try testing.expectEqual(0, empty_set.count());
    }

    {
        var parser = Parser.init(arena, "read(true)");
        const predicate = try parser.predicate(.fact);

        try testing.expectEqualStrings("read", predicate.name);
        try testing.expectEqual(true, predicate.terms.items[0].bool);
    }

    {
        // Names can contain : and _
        var parser = Parser.init(arena, "read:write_admin(true)");
        const predicate = try parser.predicate(.fact);

        try testing.expectEqualStrings("read:write_admin", predicate.name);
        try testing.expectEqual(true, predicate.terms.items[0].bool);
    }

    {
        var parser = Parser.init(arena, "read(true, false)");
        const predicate = try parser.predicate(.fact);

        try testing.expectEqualStrings("read", predicate.name);
        try testing.expectEqual(true, predicate.terms.items[0].bool);
        try testing.expectEqual(false, predicate.terms.items[1].bool);
    }

    {
        var parser = Parser.init(arena, "read(true,false)");
        const predicate = try parser.predicate(.fact);

        try testing.expectEqualStrings("read", predicate.name);
        try testing.expectEqual(true, predicate.terms.items[0].bool);
        try testing.expectEqual(false, predicate.terms.items[1].bool);
    }

    {
        // We are allowed spaces around predicate terms
        var parser = Parser.init(arena, "read( true , false )");
        const predicate = try parser.predicate(.fact);

        try testing.expectEqualStrings("read", predicate.name);
        try testing.expectEqual(true, predicate.terms.items[0].bool);
        try testing.expectEqual(false, predicate.terms.items[1].bool);
    }

    {
        // We don't allow a space between the predicate name and its opening paren
        var parser = Parser.init(arena, "read  (true, false )");

        try testing.expectError(error.UnexpectedString, parser.predicate(.fact));
    }

    {
        // We don't allow variables in fact predicates
        var parser = Parser.init(arena, "read(true, $foo)");

        try testing.expectError(error.DisallowedChar, parser.predicate(.fact));
    }

    {
        // Non-fact predicates can contain variables
        var parser = Parser.init(arena, "read(true, $foo)");

        const predicate = try parser.predicate(.rule);

        try testing.expectEqualStrings("read", predicate.name);
        try testing.expectEqual(true, predicate.terms.items[0].bool);
        try testing.expectEqualStrings("foo", predicate.terms.items[1].variable);
    }

    {
        // Facts must have at least one term
        var parser = Parser.init(arena, "read()");

        try testing.expectError(error.NoFactTermFound, parser.predicate(.fact));
    }

    {
        // Facts must start with a (UTF-8) letter
        var parser = Parser.init(arena, "3read(true)");

        try testing.expectError(error.ParsingNameFirstCharacterMustBeLetter, parser.predicate(.fact));
    }

    {
        // Names can be UTF-8
        const input = "ビスケット(true)";
        var parser = Parser.init(arena, input);

        const predicate = try parser.predicate(.fact);

        try testing.expectEqualStrings("ビスケット", predicate.name);
        try testing.expectEqual(true, predicate.terms.items[0].bool);
    }
}

test "parse numbers" {
    const testing = std.testing;

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    {
        var parser = Parser.init(arena, "1");
        const integer = try parser.number(i64);

        try testing.expectEqual(1, integer);
    }

    {
        var parser = Parser.init(arena, "12345");
        const integer = try parser.number(i64);

        try testing.expectEqual(12345, integer);
    }

    {
        var parser = Parser.init(arena, "-1");
        const integer = try parser.number(i64);

        try testing.expectEqual(-1, integer);
    }

    {
        var parser = Parser.init(arena, "-");

        try testing.expectError(error.InvalidCharacter, parser.number(i64));
    }
}

test "parse boolean" {
    const testing = std.testing;

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    {
        var parser = Parser.init(arena, "true");
        const boolean = try parser.boolean();

        try testing.expectEqual(true, boolean);
    }

    {
        var parser = Parser.init(arena, "false");
        const boolean = try parser.boolean();

        try testing.expectEqual(false, boolean);
    }
}

test "parse hex" {
    const testing = std.testing;

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    {
        var parser = Parser.init(arena, "hex:BeEf");
        const bytes = try parser.bytes();

        try testing.expectEqualStrings("\xbe\xef", bytes);
    }

    {
        var parser = Parser.init(arena, "hex:BeE");

        try testing.expectError(error.ExpectedEvenNumberOfHexDigis, parser.bytes());
    }
}

test "parse rule" {
    const testing = std.testing;

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    {
        var parser = Parser.init(arena, "read($0, $1) <- operation($0), file($1)");
        const rule = try parser.rule();

        try testing.expectEqualStrings("read", rule.head.name);
        try testing.expectEqualStrings("0", rule.head.terms.items[0].variable);
        try testing.expectEqualStrings("1", rule.head.terms.items[1].variable);

        try testing.expectEqualStrings("operation", rule.body.items[0].name);
        try testing.expectEqualStrings("0", rule.body.items[0].terms.items[0].variable);

        try testing.expectEqualStrings("file", rule.body.items[1].name);
        try testing.expectEqualStrings("1", rule.body.items[1].terms.items[0].variable);
    }

    {
        // Remove some spaces
        var parser = Parser.init(arena, "read($0, $1)<-operation($0),file($1)");
        const rule = try parser.rule();

        try testing.expectEqualStrings("read", rule.head.name);
        try testing.expectEqualStrings("0", rule.head.terms.items[0].variable);
        try testing.expectEqualStrings("1", rule.head.terms.items[1].variable);

        try testing.expectEqualStrings("operation", rule.body.items[0].name);
        try testing.expectEqualStrings("0", rule.body.items[0].terms.items[0].variable);

        try testing.expectEqualStrings("file", rule.body.items[1].name);
        try testing.expectEqualStrings("1", rule.body.items[1].terms.items[0].variable);
    }

    {
        // Remove some spaces
        var parser = Parser.init(arena, "read($0, $1) <- operation($0), 1 < 3, file($1)");
        const rule = try parser.rule();

        try testing.expectEqualStrings("read", rule.head.name);
        try testing.expectEqualStrings("0", rule.head.terms.items[0].variable);
        try testing.expectEqualStrings("1", rule.head.terms.items[1].variable);

        try testing.expectEqualStrings("operation", rule.body.items[0].name);
        try testing.expectEqualStrings("0", rule.body.items[0].terms.items[0].variable);

        try testing.expectEqualStrings("file", rule.body.items[1].name);
        try testing.expectEqualStrings("1", rule.body.items[1].terms.items[0].variable);

        try testing.expectEqualStrings("1 < 3", try std.fmt.allocPrint(arena, "{any}", .{rule.expressions.items[0]}));
    }

    {
        // We need at least one predicate or expression in the body
        var parser = Parser.init(arena, "read($0, $1) <- ");

        try testing.expectError(error.ExpectedPredicateOrExpression, parser.rule());
    }
}

test "parse check" {
    const testing = std.testing;

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    {
        var parser = Parser.init(arena, "check if right($0, $1), resource($0), operation($1), $0.contains(\"file\")");
        const check = try parser.check();

        try testing.expectEqual(.one, check.kind);
        try testing.expectEqual(1, check.queries.items.len);

        try testing.expectEqualStrings("query", check.queries.items[0].head.name);
        try testing.expectEqualStrings("right", check.queries.items[0].body.items[0].name);
        try testing.expectEqualStrings("resource", check.queries.items[0].body.items[1].name);
        try testing.expectEqualStrings("operation", check.queries.items[0].body.items[2].name);

        try testing.expectEqualStrings("$0.contains(\"file\")", try std.fmt.allocPrint(arena, "{any}", .{check.queries.items[0].expressions.items[0]}));
    }

    {
        // Check with or
        var parser = Parser.init(arena, "check if right($0, $1), resource($0), operation($1), $0.contains(\"file\") or admin(true)");
        const check = try parser.check();

        try testing.expectEqual(.one, check.kind);
        try testing.expectEqual(2, check.queries.items.len);

        try testing.expectEqualStrings("query", check.queries.items[0].head.name);
        try testing.expectEqualStrings("right", check.queries.items[0].body.items[0].name);
        try testing.expectEqualStrings("resource", check.queries.items[0].body.items[1].name);
        try testing.expectEqualStrings("operation", check.queries.items[0].body.items[2].name);

        try testing.expectEqualStrings("query", check.queries.items[1].head.name);
        try testing.expectEqualStrings("admin", check.queries.items[1].body.items[0].name);
    }

    {
        // Check all
        var parser = Parser.init(arena, "check all right($0, $1), resource($0), operation($1), $0.contains(\"file\") or admin(true)");
        const check = try parser.check();

        try testing.expectEqual(.all, check.kind);
        try testing.expectEqual(2, check.queries.items.len);

        try testing.expectEqualStrings("query", check.queries.items[0].head.name);
        try testing.expectEqualStrings("right", check.queries.items[0].body.items[0].name);
        try testing.expectEqualStrings("resource", check.queries.items[0].body.items[1].name);
        try testing.expectEqualStrings("operation", check.queries.items[0].body.items[2].name);

        try testing.expectEqualStrings("query", check.queries.items[1].head.name);
        try testing.expectEqualStrings("admin", check.queries.items[1].body.items[0].name);
    }

    {
        var parser = Parser.init(arena, "check if");

        try testing.expectError(error.ExpectedWhiteSpace, parser.check());
    }

    {
        var parser = Parser.init(arena, "check if ");

        try testing.expectError(error.ExpectedPredicateOrExpression, parser.check());
    }
}

test "parse policy" {
    const testing = std.testing;

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    {
        var parser = Parser.init(arena, "allow if right($0, $1), resource($0), operation($1), $0.contains(\"file\")");
        const policy = try parser.policy();

        try testing.expectEqual(.allow, policy.kind);
        try testing.expectEqual(1, policy.queries.items.len);

        try testing.expectEqualStrings("query", policy.queries.items[0].head.name);
        try testing.expectEqualStrings("right", policy.queries.items[0].body.items[0].name);
        try testing.expectEqualStrings("resource", policy.queries.items[0].body.items[1].name);
        try testing.expectEqualStrings("operation", policy.queries.items[0].body.items[2].name);

        try testing.expectEqualStrings("$0.contains(\"file\")", try std.fmt.allocPrint(arena, "{any}", .{policy.queries.items[0].expressions.items[0]}));
    }

    {
        var parser = Parser.init(arena, "deny if right($0, $1), resource($0), operation($1), $0.contains(\"file\")");
        const policy = try parser.policy();

        try testing.expectEqual(.deny, policy.kind);
        try testing.expectEqual(1, policy.queries.items.len);

        try testing.expectEqualStrings("query", policy.queries.items[0].head.name);
        try testing.expectEqualStrings("right", policy.queries.items[0].body.items[0].name);
        try testing.expectEqualStrings("resource", policy.queries.items[0].body.items[1].name);
        try testing.expectEqualStrings("operation", policy.queries.items[0].body.items[2].name);

        try testing.expectEqualStrings("$0.contains(\"file\")", try std.fmt.allocPrint(arena, "{any}", .{policy.queries.items[0].expressions.items[0]}));
    }
}
