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

    pub fn convert(scope: Scope, _: *const SymbolTable, _: *SymbolTable) !Scope {
        //
        return scope;
    }
};

const ScopeTag = enum(u8) {
    authority,
    previous,
    public_key,
};
