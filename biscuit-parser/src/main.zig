const std = @import("std");
const ziglyph = @import("ziglyph");
const Term = @import("biscuit-builder").Term;
const Fact = @import("biscuit-builder").Fact;

pub const Parser = struct {
    input: []const u8,
    offset: usize = 0,

    pub fn init(input: []const u8) Parser {
        return .{ .input = input };
    }

    pub fn fact(parser: *Parser) !Fact {
        return try parser.factPredicate();
    }

    pub fn factPredicate(parser: *Parser, allocator: std.mem.Allocator) !Fact {
        std.debug.print("{s}[0] = {s}\n", .{ @src().fn_name, parser.rest() });
        defer std.debug.print("{s}[1] = {s}\n", .{ @src().fn_name, parser.rest() });

        const name = parser.readName();

        parser.skipWhiteSpace();

        // Consume left paren
        try parser.expect('(');

        // Parse terms
        var terms = std.ArrayList(Term).init(allocator);

        var it = parser.factTermsIterator();
        while (try it.next()) |term| {
            try terms.append(term);

            if (parser.peek()) |peeked| {
                if (peeked != ',') break;
            } else {
                break;
            }
        }

        try parser.expect(')');

        return .{
            .predicate = .{ .name = name, .terms = terms },
            .variables = null,
        };
    }

    const FactTermIterator = struct {
        parser: *Parser,

        pub fn next(it: *FactTermIterator) !?Term {
            it.parser.skipWhiteSpace();

            const term = try it.parser.factTerm();

            return term;
        }
    };

    pub fn factTermsIterator(parser: *Parser) FactTermIterator {
        return .{ .parser = parser };
    }

    pub fn factTerm(parser: *Parser) !Term {
        std.debug.print("{s}[0] = {s}\n", .{ @src().fn_name, parser.rest() });
        defer std.debug.print("{s}[1] = {s}\n", .{ @src().fn_name, parser.rest() });

        const rst = parser.rest();

        try parser.reject('$'); // Variables are disallowed in a fact term

        string_blk: {
            var term_parser = Parser.init(rst);
            const s = term_parser.string() catch {
                break :string_blk;
            };

            parser.offset += term_parser.offset;
            return .{ .string = s };
        }

        bool_blk: {
            var term_parser = Parser.init(rst);
            const b = term_parser.boolean() catch {
                break :bool_blk;
            };

            parser.offset += term_parser.offset;

            return .{ .bool = b };
        }

        return error.NoFactTermFound;
    }

    fn string(parser: *Parser) ![]const u8 {
        std.debug.print("{s}[0] = {s}\n", .{ @src().fn_name, parser.rest() });
        defer std.debug.print("{s}[1] = {s}\n", .{ @src().fn_name, parser.rest() });

        try parser.expect('"');

        return error.ExpectedStringTerm;
    }

    fn boolean(parser: *Parser) !bool {
        std.debug.print("{s}[0] = {s}\n", .{ @src().fn_name, parser.rest() });
        defer std.debug.print("{s}[1] = {s}\n", .{ @src().fn_name, parser.rest() });

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

test "parse fact predicate" {
    const testing = std.testing;
    const fact: []const u8 =
        \\read(true)
    ;

    var parser = Parser.init(fact);

    const f = try parser.factPredicate(testing.allocator);
    defer f.deinit();
    std.debug.print("{any}\n", .{f});
}
