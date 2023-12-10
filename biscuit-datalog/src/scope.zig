pub const Scope = union(ScopeTag) {
    authority: void,
    previous: void,
    public_key: u64,
};

const ScopeTag = enum(u8) {
    authority,
    previous,
    public_key,
};
