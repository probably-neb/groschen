const std = @import("std");

const ModuleSpec = struct {
    name: []const u8,
    path: []const u8,
    exe_name: ?[]const u8 = null,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module_specs = [_]ModuleSpec{
        .{ .name = "bin", .path = "src/bin/bin.zig", .exe_name = "groschen" },
        .{ .name = "tui_test", .path = "src/tui_test/tui_test.zig", .exe_name = "tui-test" },
        .{ .name = "term", .path = "src/term/term.zig" },
        .{ .name = "ui", .path = "src/ui/ui.zig" },
        .{ .name = "widgets", .path = "src/widgets/widgets.zig" },
        .{ .name = "base", .path = "src/base/base.zig" },
        .{ .name = "plaid", .path = "src/plaid/plaid.zig" },
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

    const check_step = b.step("check", "check");
    inline for (modules, module_specs) |module, module_spec| {
        if (module_spec.exe_name == null) continue;

        const run_name = "run:" ++ module_spec.exe_name.?;
        const run_step = b.step(run_name, "Run the app");

        const exe = b.addExecutable(.{
            .name = module_spec.exe_name.?,
            .root_module = module,
        });
        const check_exe = b.addExecutable(.{
            .name = module_spec.exe_name.?,
            .root_module = module,
        });
        check_step.dependOn(&check_exe.step);
        b.installArtifact(exe);
        const run_cmd = b.addRunArtifact(exe);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        run_cmd.step.dependOn(b.getInstallStep());
        run_step.dependOn(&run_cmd.step);
    }
}
