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

    const lib = b.addStaticLibrary(.{
        .name = "biscuit",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "biscuit/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    //
    const protobuf = b.dependency("zig_protobuf", .{ .target = target, .optimize = optimize });
    // lib.addModule("protobuf", protobuf.module("protobuf"));

    // Define our biscuit-format module. This module depends on the external protobuf library
    const schema_module = b.createModule(.{
        .root_source_file = .{ .path = "biscuit-schema/src/main.zig" },
        .imports = &.{
            .{ .name = "protobuf", .module = protobuf.module("protobuf") },
        },
    });

    const format_module = b.createModule(.{
        .root_source_file = .{ .path = "biscuit-format/src/main.zig" },
        .imports = &.{
            .{
                .name = "biscuit-schema",
                .module = schema_module,
            },
        },
    });

    // Define our datalog module
    const datalog_module = b.createModule(.{
        .root_source_file = .{ .path = "biscuit-datalog/src/main.zig" },
        .imports = &.{
            .{
                .name = "biscuit-format",
                .module = format_module,
            },
            .{
                .name = "biscuit-schema",
                .module = schema_module,
            },
        },
    });

    // Define our datalog module
    const biscuit_module = b.createModule(.{
        .root_source_file = .{ .path = "biscuit/src/main.zig" },
        .imports = &.{
            .{
                .name = "biscuit-format",
                .module = format_module,
            },
            .{
                .name = "biscuit-schema",
                .module = schema_module,
            },
            .{
                .name = "biscuit-datalog",
                .module = datalog_module,
            },
        },
    });

    // Add modules to root
    // lib.addModule("biscuit-format", format_module);
    // lib.addModule("biscuit-datalog", datalog_module);

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "biscuit/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    // main_tests.addModule("protobuf", protobuf.module("protobuf"));
    main_tests.root_module.addImport("biscuit-schema", schema_module);
    main_tests.root_module.addImport("biscuit-format", format_module);
    main_tests.root_module.addImport("biscuit-datalog", datalog_module);

    const run_main_tests = b.addRunArtifact(main_tests);
    const main_step = b.step("test-biscuit", "Run the biscuit module tests");
    main_step.dependOn(&run_main_tests.step);

    const datalog_tests = b.addTest(.{
        .root_source_file = .{ .path = "biscuit-datalog/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_datalog_tests = b.addRunArtifact(datalog_tests);

    const format_tests = b.addTest(.{
        .root_source_file = .{ .path = "biscuit-format/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_format_tests = b.addRunArtifact(format_tests);

    const schema_tests = b.addTest(.{
        .root_source_file = .{ .path = "biscuit-schema/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_schema_tests = b.addRunArtifact(schema_tests);

    const testsuite_tests = b.addTest(.{
        .root_source_file = .{ .path = "biscuit-samples/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    testsuite_tests.root_module.addImport("biscuit-format", format_module);
    testsuite_tests.root_module.addImport("biscuit", biscuit_module);
    const run_testsuite_tests = b.addRunArtifact(testsuite_tests);

    const testsuite_step = b.step("testsuite", "Run all the testsuite tests");
    testsuite_step.dependOn(&run_testsuite_tests.step);

    // Load samples.json to generate zig build testsuite commands for each case (for great justice)
    const testrunner = b.addExecutable(.{
        .name = "testrunner",
        .root_source_file = .{ .path = "biscuit-samples/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    testrunner.root_module.addImport("biscuit-format", format_module);
    testrunner.root_module.addImport("biscuit", biscuit_module);

    const json_string = @embedFile("biscuit-samples/src/samples/samples.json");
    const dynamic_tree = try std.json.parseFromSliceLeaky(std.json.Value, b.allocator, json_string, .{});
    const Samples = @import("biscuit-samples/src/sample.zig").Samples;
    const r = try std.json.parseFromValueLeaky(Samples, b.allocator, dynamic_tree, .{});
    for (r.testcases) |testcase| {
        const test_filename = testcase.filename;
        const title = testcase.title;
        const run_test = b.addRunArtifact(testrunner);

        run_test.addArg(b.fmt("{s}", .{test_filename}));
        run_test.cwd = .{ .path = b.pathFromRoot("biscuit-samples/src/samples") };
        var it = std.mem.splitScalar(u8, test_filename, '_');
        const short_name = it.next() orelse return error.ExpectedShortName;

        const step = b.step(b.fmt("testsuite-{s}", .{short_name}), b.fmt("Run test {s}: {s}", .{ test_filename, title }));
        step.dependOn(&run_test.step);
        testsuite_step.dependOn(&run_test.step);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
    test_step.dependOn(&run_datalog_tests.step);
    test_step.dependOn(&run_format_tests.step);
    test_step.dependOn(&run_schema_tests.step);
    test_step.dependOn(testsuite_step);
}
