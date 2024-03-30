const std = @import("std");
const schema = @import("biscuit-schema");
const SymbolTable = @import("symbol_table.zig").SymbolTable;

pub const Scope = union(ScopeTag) {
    authority: void,
    previous: void,
    public_key: u64,

    pub fn fromSchema(schema_scope: schema.Scope) !Scope {
        const schema_scope_content = schema_scope.Content orelse return error.ExpectedScopeContent;

        return switch (schema_scope_content) {
            .scopeType => |scope_type| switch (scope_type) {
                .Authority => .authority,
                .Previous => .previous,
                else => return error.UnknownSchemaScopeType,
            },
            .publicKey => |key| .{ .public_key = @bitCast(key) }, // FIXME: should we check for negativity?
        };
    }

    pub fn remapSymbols(scope: Scope, old_symbols: *const SymbolTable, new_symbols: *SymbolTable) !Scope {
        return switch (scope) {
            .authority => .authority,
            .previous => .previous,
            .public_key => |index| .{ .public_key = try new_symbols.insertPublicKey(try old_symbols.getPublicKey(index)) },
        };
    }

    pub fn format(scope: Scope, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (scope) {
            .authority => try writer.print("authority", .{}),
            .previous => try writer.print("previous", .{}),
            .public_key => |public_key| try writer.print("public key {}", .{public_key}),
        }
    }
};

const ScopeTag = enum(u8) {
    authority,
    previous,
    public_key,
};
