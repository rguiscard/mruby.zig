const std = @import("std");

const cflags = &.{
    "-std=c99",

    // https://github.com/mruby/mruby/blob/3.2.0/include/mruby/presym.h#L10
    // https://github.com/mruby/mruby/blob/3.2.0/doc/guides/compile.md#preallocated-symbols
    // conf.disable_presym
    "-DMRB_NO_PRESYM",

    // https://github.com/mruby/mruby/blob/3.2.0/src/state.c#L81-L87
    // "-DMRB_NO_GEMS",
};

const mruby_rbfiles = [_][]const u8{
    "mrblib/00class.rb",
    "mrblib/00kernel.rb",
    "mrblib/10error.rb",
    "mrblib/array.rb",
    "mrblib/compar.rb",
    "mrblib/enum.rb",
    "mrblib/hash.rb",
    "mrblib/kernel.rb",
    "mrblib/numeric.rb",
    "mrblib/range.rb",
    "mrblib/string.rb",
    "mrblib/symbol.rb",
};

const mruby_srcs = [_][]const u8{
    "src/array.c",
    "src/backtrace.c",
    "src/cdump.c",
    "src/class.c",
    "src/codedump.c",
    "src/compar.c",
    "src/debug.c",
    "src/dump.c",
    "src/enum.c",
    "src/error.c",
    "src/etc.c",
    "src/fmt_fp.c",
    "src/gc.c",
    "src/hash.c",
    "src/init.c",
    "src/kernel.c",
    "src/load.c",
    "src/numeric.c",
    "src/numops.c",
    "src/object.c",
    "src/pool.c",
    "src/print.c",
    "src/proc.c",
    "src/range.c",
    "src/readfloat.c",
    "src/readint.c",
    "src/readnum.c",
    "src/state.c",
    "src/string.c",
    "src/symbol.c",
    "src/variable.c",
    "src/version.c",
    "src/vm.c",
};

pub const Mgem = struct {
    srcs: []const []const u8,
    rbfiles: []const []const u8,
    includePaths: []const []const u8,
    name: []const u8,
    builtin: bool = true,
};

// libmruby_core.a
pub fn mrubyCoreLib(
    b: *std.Build,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const src_dir = std.fs.path.dirname(@src().file) orelse ".";

    const lib = b.addStaticLibrary(.{
        .name = "mruby_core",
        .target = target,
        .optimize = optimize,
    });

    lib.addIncludePath(.{ .path = b.pathJoin(&.{ src_dir, "mruby/include" }) });
    lib.linkLibC();

    if (target.isDarwin()) {
        lib.addFrameworkPath(.{ .path = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" });
    }

    var srcs = std.ArrayList([]const u8).init(b.allocator);
    for (mruby_srcs) |src| {
        srcs.append(
            b.pathJoin(&.{ src_dir, "mruby", src }),
        ) catch @panic("append");
    }
    lib.addCSourceFiles(srcs.items, cflags);

    return lib;
}

pub fn mrbcExecutable(
    b: *std.Build,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
    mruby_core_lib: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const src_dir = std.fs.path.dirname(@src().file) orelse ".";

    const exe = b.addExecutable(.{
        .name = "mrbc",
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(mruby_core_lib);

    exe.addIncludePath(.{ .path = b.pathJoin(&.{ src_dir, "mruby/include" }) });
    exe.linkLibC();

    if (target.isDarwin()) {
        exe.addFrameworkPath(.{ .path = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" });
    }

    const srcs = &[_][]const u8{
        "mrbgems/mruby-compiler/core/y.tab.c",
        "mrbgems/mruby-compiler/core/codegen.c",
        "mrbgems/mruby-bin-mrbc/tools/mrbc/mrbc.c",
    };
    var results = std.ArrayList([]const u8).init(b.allocator);
    for (srcs) |src| {
        results.append(
            b.pathJoin(&.{ src_dir, "mruby", src }),
        ) catch @panic("append");
    }

    exe.addCSourceFiles(results.items, cflags);

    return exe;
}

// libmruby.a
pub fn mrubyLib(
    b: *std.Build,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
    mruby_core_lib: *std.Build.Step.Compile,
    mrbc_exe: *std.Build.Step.Compile,
    gems: []const Mgem,
) *std.Build.Step.Compile {
    const src_dir = std.fs.path.dirname(@src().file) orelse ".";

    const lib = b.addStaticLibrary(.{
        .name = "mruby",
        .target = target,
        .optimize = optimize,
    });

    lib.addIncludePath(.{ .path = b.pathJoin(&.{ src_dir, "mruby/include" }) });
    lib.linkLibC();
    lib.linkLibrary(mruby_core_lib);

    if (target.isDarwin()) {
        lib.addFrameworkPath(.{ .path = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" });
    }
    for (gems) |gem| {
        for (gem.includePaths) |path| {
            lib.addIncludePath(.{
                .path = b.pathJoin(&.{ src_dir, "mruby", path }),
            });
        }
    }

    var srcs = std.ArrayList([]const u8).init(b.allocator);

    for (mruby_srcs) |src| {
        srcs.append(
            b.pathJoin(&.{ src_dir, "mruby", src }),
        ) catch @panic("append");
    }
    for (gems) |gem| {
        for (gem.srcs) |src| {
            if (gem.builtin) {
                srcs.append(
                    b.pathJoin(&.{ src_dir, "mruby", src }),
                ) catch @panic("append");
            } else {
                srcs.append(src) catch @panic("append");
            }
        }
    }

    lib.addCSourceFiles(srcs.items, cflags);

    const compile_mrblib_cmd = b.addRunArtifact(mrbc_exe);
    compile_mrblib_cmd.addArgs(&.{
        // TODO: only do this for `optimize=Debug` builds
        "-g -B%{funcname} -o-", // `-g` is required for line numbers
        "-B",
        "entrypoint_mrblib",
        "-o",
    });
    const mrblib = compile_mrblib_cmd.addOutputFileArg("mrblib.c");
    for (mruby_rbfiles) |file| {
        compile_mrblib_cmd.addFileSourceArg(.{
            .path = b.pathJoin(&.{ src_dir, "mruby", file }),
        });
    }

    const compile_mrbgems_cmd = b.addRunArtifact(mrbc_exe);
    compile_mrbgems_cmd.addArgs(&.{
        // TODO: only do this for `optimize=Debug` builds
        "-g -B%{funcname} -o-", // `-g` is required for line numbers
        "-B",
        "entrypoint_mrbgems",
        "-o",
    });
    const gem_init = compile_mrbgems_cmd.addOutputFileArg(
        "src/gem_init.c",
    );
    for (gems) |gem| {
        if (!std.mem.eql(u8, gem.name, "mruby_compiler")) {
            for (gem.rbfiles) |src| {
                if (gem.builtin) {
                    compile_mrbgems_cmd.addFileSourceArg(.{
                        .path = b.pathJoin(&.{ src_dir, "mruby", src }),
                    });
                } else {
                    compile_mrbgems_cmd.addFileSourceArg(.{ .path = src });
                }
            }
        }
    }

    const mrblib_obj = b.addObject(.{
        .name = "mrblib",
        .target = target,
        .optimize = optimize,
        .root_source_file = mrblib,
    });

    const mrbgems_obj = b.addObject(.{
        .name = "gem_init",
        .target = target,
        .optimize = optimize,
        .root_source_file = gem_init,
    });

    // see https://github.com/mruby/mruby/blob/3.2.0/lib/mruby/gem.rb

    const header =
        \\#include <mruby.h>
        \\#include <mruby/irep.h>
        \\
        \\#include <stdint.h>
        \\#include <stdlib.h>
        \\#include <stdio.h>
        \\
        \\extern const uint8_t entrypoint_mrblib[];
        \\extern const uint8_t entrypoint_mrbgems[];
        \\
        \\void mrb_init_mrblib(mrb_state *mrb) {
        \\  mrb_load_irep(mrb, entrypoint_mrblib);
        \\}
        \\
    ;
    var result = std.ArrayList(u8).init(b.allocator);
    result.appendSlice(header[0..]) catch @panic("appendSlice");

    for (gems) |gem| {
        if (gem.srcs.len > 0 and !std.mem.eql(u8, gem.name, "mruby_compiler")) {
            const str = std.fmt.allocPrint(
                b.allocator,
                "\nvoid mrb_{s}_gem_init(mrb_state *mrb);\n",
                .{gem.name},
            ) catch @panic("allocPrint");
            result.appendSlice(str) catch @panic("appendSlice");
        }
    }

    result.appendSlice(
        \\void mrb_init_mrbgems(mrb_state *mrb) {
    ) catch @panic("appendSlice");

    for (gems) |gem| {
        if (gem.srcs.len > 0 and !std.mem.eql(u8, gem.name, "mruby_compiler")) {
            const str = std.fmt.allocPrint(
                b.allocator,
                "  mrb_{s}_gem_init(mrb);\n",
                .{gem.name},
            ) catch @panic("allocPrint");
            result.appendSlice(str) catch @panic("appendSlice");
        }
    }
    result.appendSlice(
        \\  mrb_load_irep(mrb, entrypoint_mrbgems);
        \\
        \\  if (mrb->exc) {
        \\    mrb_print_error(mrb);
        \\    mrb_close(mrb);
        \\    exit(EXIT_FAILURE);
        \\  }
        \\}
        \\
    ) catch @panic("appendSlice");

    const generated_mrbloader = b.addWriteFile(
        "generated_mrbloader.c",
        result.items,
    );

    const mrbloader_obj = b.addObject(.{
        .name = "mrbloader",
        .target = target,
        .optimize = optimize,
        .root_source_file = generated_mrbloader.files.items[0].getFileSource(),
    });
    mrbloader_obj.linkLibC();
    mrbloader_obj.addIncludePath(.{
        .path = b.pathJoin(&.{ src_dir, "mruby", "include" }),
    });
    if (target.isDarwin()) {
        mrbloader_obj.addFrameworkPath(.{ .path = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" });
    }

    lib.addObject(mrblib_obj);
    lib.addObject(mrbgems_obj);
    lib.addObject(mrbloader_obj);
    lib.linkLibC();

    return lib;
}

pub fn addMruby(
    b: *std.Build,
    exe: *std.Build.CompileStep,
    target: std.zig.CrossTarget,
    mruby_lib: *std.Build.CompileStep,
    extra_files: []const []const u8,
) void {
    const src_dir = std.fs.path.dirname(@src().file) orelse ".";

    exe.linkLibrary(mruby_lib);
    exe.addCSourceFiles(extra_files, cflags);

    exe.addIncludePath(.{
        .path = b.pathJoin(&.{ src_dir, "mruby", "include" }),
    });

    if (target.isDarwin()) {
        exe.addFrameworkPath(.{ .path = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" });
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cwd = comptime std.fs.path.dirname(@src().file) orelse ".";
    const src_dir = cwd ++ "/mruby/";

    //-- mrbc

    const mruby_core_lib = mrubyCoreLib(b, target, optimize);

    const mrbc_exe = mrbcExecutable(
        b,
        target,
        optimize,
        mruby_core_lib,
    );
    b.installArtifact(mrbc_exe);

    const mruby_lib = mrubyLib(
        b,
        target,
        optimize,
        mruby_core_lib,
        mrbc_exe,
        &.{
            .{
                .name = "mruby_compiler",
                .srcs = &.{
                    "mrbgems/mruby-compiler/core/y.tab.c",
                    "mrbgems/mruby-compiler/core/codegen.c",
                },
                .rbfiles = &.{},
                .includePaths = &.{},
            },
            .{
                .name = "mruby_io",
                .rbfiles = &.{
                    "mrbgems/mruby-io/mrblib/file.rb",
                    "mrbgems/mruby-io/mrblib/file_constants.rb",
                    "mrbgems/mruby-io/mrblib/io.rb",
                    "mrbgems/mruby-io/mrblib/kernel.rb",
                },
                .srcs = &.{
                    "mrbgems/mruby-io/src/file.c",
                    "mrbgems/mruby-io/src/file_test.c",
                    "mrbgems/mruby-io/src/io.c",
                    "mrbgems/mruby-io/src/mruby_io_gem.c",
                },
                .includePaths = &.{
                    "mrbgems/mruby-io/include",
                },
            },
            // Test seems to need this for some reason
            .{
                .name = "mruby_fiber",
                .srcs = &.{"mrbgems/mruby-fiber/src/fiber.c"},
                .includePaths = &.{},
                .rbfiles = &.{},
            },
        },
    );
    b.installArtifact(mruby_lib);

    //-- mruby

    const mruby_exe = b.addExecutable(.{
        .name = "mruby",
        .target = target,
        .optimize = optimize,
    });
    addMruby(b, mruby_exe, target, mruby_lib, &.{
        src_dir ++ "mrbgems/mruby-bin-mruby/tools/mruby/mruby.c",
    });
    b.installArtifact(mruby_exe);

    //-- mirb

    const mirb_exe = b.addExecutable(.{
        .name = "mirb",
        .target = target,
        .optimize = optimize,
    });
    addMruby(b, mirb_exe, target, mruby_lib, &.{
        src_dir ++ "mrbgems/mruby-bin-mirb/tools/mirb/mirb.c",
    });
    b.installArtifact(mirb_exe);

    //--------------

    const mruby_mod = b.createModule(.{
        .source_file = .{ .path = "src/mruby.zig" },
    });

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "examples/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    addMruby(b, unit_tests, target, mruby_lib, &.{});
    unit_tests.addModule("mruby", mruby_mod);
    unit_tests.addCSourceFiles(&.{"src/mruby_compat.c"}, &.{});

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const c_test_exe = b.addExecutable(.{
        .name = "c_example",
        .root_source_file = .{ .path = "examples/main.c" },
        .target = target,
        .optimize = optimize,
    });
    addMruby(b, c_test_exe, target, mruby_lib, &.{});
    b.installArtifact(c_test_exe);

    const zig_test_exe = b.addExecutable(.{
        .name = "zig_example",
        .root_source_file = .{ .path = "examples/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    addMruby(b, zig_test_exe, target, mruby_lib, &.{});
    zig_test_exe.addModule("mruby", mruby_mod);
    zig_test_exe.addCSourceFiles(&.{"src/mruby_compat.c"}, &.{});

    b.installArtifact(zig_test_exe);

    const run_c_cmd = b.addRunArtifact(c_test_exe);
    const run_c_step = b.step("c-example", "runs examples/main.c");
    run_c_step.dependOn(&run_c_cmd.step);

    const run_zig_cmd = b.addRunArtifact(zig_test_exe);
    const run_zig_step = b.step("zig-example", "runs examples/main.zig");
    run_zig_step.dependOn(&run_zig_cmd.step);
}
