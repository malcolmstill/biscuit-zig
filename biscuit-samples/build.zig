const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const format = b.dependency("biscuit_format", .{ .target = target, .optimize = optimize });
    const biscuit = b.dependency("biscuit", .{ .target = target, .optimize = optimize });

    const testsuite_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    testsuite_tests.root_module.addImport("biscuit-format", format.module("biscuit-format"));
    testsuite_tests.root_module.addImport("biscuit", biscuit.module("biscuit"));

    const run_testsuite_tests = b.addRunArtifact(testsuite_tests);

    const testsuite_step = b.step("testsuite", "Run all the testsuite tests");
    testsuite_step.dependOn(&run_testsuite_tests.step);

    // Load samples.json to generate zig build testsuite commands for each case (for great justice)
    const testrunner = b.addExecutable(.{
        .name = "testrunner",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    testrunner.root_module.addImport("biscuit-format", format.module("biscuit-format"));
    testrunner.root_module.addImport("biscuit", biscuit.module("biscuit"));

    const json_string = @embedFile("src/samples/samples.json");
    const dynamic_tree = try std.json.parseFromSliceLeaky(std.json.Value, b.allocator, json_string, .{});
    const Samples = @import("src/sample.zig").Samples;
    const r = try std.json.parseFromValueLeaky(Samples, b.allocator, dynamic_tree, .{});
    for (r.testcases) |testcase| {
        const test_filename = testcase.filename;
        const title = testcase.title;
        const run_test = b.addRunArtifact(testrunner);

        run_test.addArg(b.fmt("{s}", .{test_filename}));
        run_test.cwd = .{ .path = b.pathFromRoot("src/samples") };

        var it = std.mem.splitScalar(u8, test_filename, '_');
        const short_name = it.next() orelse return error.ExpectedShortName;

        const step = b.step(b.fmt("testsuite-{s}", .{short_name}), b.fmt("Run test {s}: {s}", .{ test_filename, title }));
        step.dependOn(&run_test.step);
        testsuite_step.dependOn(&run_test.step);
    }
}
