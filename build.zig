const std = @import("std");

const ModuleSpec = struct {
    name: []const u8,
    path: []const u8,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module_specs = [_]ModuleSpec{
        .{ .name = "bin", .path = "src/bin/bin.zig" },
        .{ .name = "tui_test", .path = "src/tui_test/tui_test.zig" },
        .{ .name = "term", .path = "src/term/term.zig" },
        .{ .name = "ui", .path = "src/ui/ui.zig" },
        .{ .name = "base", .path = "src/base/base.zig" },
    };

    var modules: [module_specs.len]*std.Build.Module = undefined;

    inline for (module_specs, 0..) |spec, i| {
        modules[i] = b.createModule(.{
            .root_source_file = b.path(spec.path),
            .target = target,
            .optimize = optimize,
        });
    }

    inline for (0..modules.len) |i| {
        inline for (0..modules.len) |j| {
            if (i == j) continue;
            modules[i].addImport(module_specs[j].name, modules[j]);
        }
    }

    const test_step = b.step("test", "Run tests");
    inline for (modules) |module| {
        const module_tests = b.addTest(.{
            .root_module = module,
        });
        const run_module_tests = b.addRunArtifact(module_tests);
        test_step.dependOn(&run_module_tests.step);
    }

    // Main executable (bin)
    comptime std.debug.assert(std.mem.eql(u8, module_specs[0].name, "bin"));

    const exe = b.addExecutable(.{
        .name = "groschen",
        .root_module = modules[0],
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // TUI test harness (tui_test)
    comptime std.debug.assert(std.mem.eql(u8, module_specs[1].name, "tui_test"));

    const tui_test_exe = b.addExecutable(.{
        .name = "tui-test",
        .root_module = modules[1],
    });

    const testing_cmd = b.addRunArtifact(tui_test_exe);

    if (b.args) |args| {
        testing_cmd.addArgs(args);
    }

    const testing_step = b.step("testing", "Run TUI test applications");
    testing_step.dependOn(&testing_cmd.step);
}
