const std = @import("std");
const Fact = @import("fact.zig").Fact;
const Rule = @import("rule.zig").Rule;
const Check = @import("check.zig").Check;
const Scope = @import("scope.zig").Scope;
const Parser = @import("parser.zig").Parser;

const log = std.log.scoped(.builder_block);

/// Block builder that allows us to append blocks to a token
pub const Block = struct {
    arena: std.mem.Allocator,
    context: ?[]const u8,
    facts: std.ArrayList(Fact),
    rules: std.ArrayList(Rule),
    checks: std.ArrayList(Check),
    scopes: std.ArrayList(Scope),

    /// Initialise a new block builder.
    ///
    /// This can take any std.mem.Allocator but by design allocations
    /// leak so the caller should pass in an ArenaAllocator or other
    /// allocator with arena-like properties.
    pub fn init(arena: std.mem.Allocator) Block {
        return .{
            .arena = arena,
            .context = null,
            .facts = std.ArrayList(Fact).init(arena),
            .rules = std.ArrayList(Rule).init(arena),
            .checks = std.ArrayList(Check).init(arena),
            .scopes = std.ArrayList(Scope).init(arena),
        };
    }

    pub fn addFact(block: *Block, input: []const u8) !void {
        log.debug("addFact = {s}", .{input});
        defer log.debug("addFact = {s}", .{input});

        var parser = Parser.init(block.arena, input);

        const fact = try parser.fact();

        try block.facts.append(fact);
    }

    pub fn addRule(block: *Block, input: []const u8) !void {
        log.debug("addRule = {s}", .{input});
        defer log.debug("addRule = {s}", .{input});

        var parser = Parser.init(block.arena, input);

        const rule = try parser.rule();

        try block.rules.append(rule);
    }

    pub fn addCheck(block: *Block, input: []const u8) !void {
        log.debug("addCheck = {s}", .{input});
        defer log.debug("addCheck = {s}", .{input});

        var parser = Parser.init(block.arena, input);

        const check = try parser.check();

        try block.checks.append(check);
    }

    pub fn addScope(block: *Block, input: []const u8) !void {
        log.debug("addScope = {s}", .{input});
        defer log.debug("addScope = {s}", .{input});

        var parser = Parser.init(block.arena, input);

        const scope = try parser.scope();

        try block.scopes.append(scope);
    }
};
