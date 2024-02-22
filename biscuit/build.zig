const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const schema = b.dependency("biscuit_schema", .{ .target = target, .optimize = optimize });
    const format = b.dependency("biscuit_format", .{ .target = target, .optimize = optimize });
    const datalog = b.dependency("biscuit_datalog", .{ .target = target, .optimize = optimize });

    _ = b.addModule("biscuit", .{
        .root_source_file = .{ .path = "src/main.zig" },
        .imports = &.{
            .{ .name = "biscuit-schema", .module = schema.module("biscuit-schema") },
            .{ .name = "biscuit-format", .module = format.module("biscuit-format") },
            .{ .name = "biscuit-datalog", .module = datalog.module("biscuit-datalog") },
        },
    });

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .name = "biscuit-tests",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addImport("biscuit-schema", schema.module("biscuit-schema"));
    lib_unit_tests.root_module.addImport("biscuit-format", format.module("biscuit-format"));
    lib_unit_tests.root_module.addImport("biscuit-datalog", datalog.module("biscuit-datalog"));

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
