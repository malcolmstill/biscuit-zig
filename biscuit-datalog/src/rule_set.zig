const std = @import("std");
const Rule = @import("rule.zig").Rule;
const TrustedOrigins = @import("trusted_origins.zig").TrustedOrigins;

pub const RuleSet = struct {
    rules: std.AutoHashMap(TrustedOrigins, std.ArrayList(OriginRule)),
    allocator: std.mem.Allocator,

    const OriginRule = struct { u64, Rule };

    pub fn init(allocator: std.mem.Allocator) RuleSet {
        return .{
            .rules = std.AutoHashMap(TrustedOrigins, std.ArrayList(OriginRule)).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn testDeinit(rule_set: *RuleSet) void {
        var it = rule_set.rules.iterator();

        while (it.next()) |entry| {
            entry.key_ptr.testDeinit();
            entry.value_ptr.deinit();
        }

        rule_set.rules.deinit();
    }

    pub fn add(rule_set: *RuleSet, origin: u64, scope: TrustedOrigins, rule: Rule) !void {
        if (rule_set.rules.getEntry(scope)) |entry| {
            try entry.value_ptr.append(.{ origin, rule });
        } else {
            var list = std.ArrayList(OriginRule).init(rule_set.allocator);
            try list.append(.{ origin, rule });

            try rule_set.rules.put(scope, list);
        }
    }
};

test "RuleSet" {
    const testing = std.testing;

    const test_log = std.log.scoped(.test_rule_set);

    var rs = RuleSet.init(testing.allocator);
    defer rs.testDeinit();

    const default_origins = try TrustedOrigins.defaultOrigins(testing.allocator);
    const rule: Rule = undefined;

    try rs.add(0, default_origins, rule);
    test_log.debug("rs = {any}", .{rs});
}
