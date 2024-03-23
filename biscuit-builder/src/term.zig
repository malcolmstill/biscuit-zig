const TermTag = enum(u8) {
    string,
    bool,
};

pub const Term = union(TermTag) {
    string: []const u8,
    bool: bool,
};
