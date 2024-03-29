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

    const ziglyph = b.dependency("ziglyph", .{ .optimize = optimize, .target = target });
    const schema = b.dependency("biscuit-schema", .{ .target = target, .optimize = optimize });
    const format = b.dependency("biscuit-format", .{ .target = target, .optimize = optimize });
    const builder = b.dependency("biscuit-builder", .{ .target = target, .optimize = optimize });
    const datalog = b.dependency("biscuit-datalog", .{ .target = target, .optimize = optimize });

    _ = b.addModule("biscuit-parser", .{
        .root_source_file = .{ .path = "src/parser.zig" },
        .imports = &.{
            .{ .name = "biscuit-schema", .module = schema.module("biscuit-schema") },
            .{ .name = "biscuit-format", .module = format.module("biscuit-format") },
            .{ .name = "biscuit-builder", .module = builder.module("biscuit-builder") },
            .{ .name = "biscuit-datalog", .module = datalog.module("biscuit-datalog") },
            .{ .name = "ziglyph", .module = ziglyph.module("ziglyph") },
        },
    });

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/parser.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addImport("biscuit-schema", schema.module("biscuit-schema"));
    lib_unit_tests.root_module.addImport("biscuit-format", format.module("biscuit-format"));
    lib_unit_tests.root_module.addImport("biscuit-builder", builder.module("biscuit-builder"));
    lib_unit_tests.root_module.addImport("biscuit-datalog", datalog.module("biscuit-datalog"));
    lib_unit_tests.root_module.addImport("ziglyph", ziglyph.module("ziglyph"));

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
