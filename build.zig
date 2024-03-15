const std = @import("std");

fn includeConfigHeader(cs: *std.Build.Step.Compile, hdr: *std.Build.Step.ConfigHeader) void {
    const b = cs.step.owner;

    var iter = hdr.values.iterator();
    while (iter.next()) |entry| {
        switch (entry.value_ptr.*) {
            .undef => continue,
            .defined => cs.root_module.addCMacro(entry.key_ptr.*, ""),
            .boolean => cs.root_module.addCMacro(entry.key_ptr.*, "1"),
            .int => |i| cs.root_module.addCMacro(entry.key_ptr.*, b.fmt("{}", .{i})),
            .ident => |i| cs.root_module.addCMacro(entry.key_ptr.*, b.fmt("{s}", .{i})),
            .string => |i| cs.root_module.addCMacro(entry.key_ptr.*, b.fmt("\"{s}\"", .{i})),
        }
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(std.builtin.LinkMode, "linkage", "Sets the link mode") orelse @as(std.builtin.LinkMode, if (target.result.isGnuLibC()) .dynamic else .static);

    const source = b.dependency("eudev", .{});

    const configHeader = b.addConfigHeader(.{}, .{
        .HAVE_DECL_GETRANDOM = 0,
        .HAVE_DECL_STRNDUPA = 1,
        .HAVE_DECL_NAME_TO_HANDLE_AT = 1,
        .HAVE_DECL_GETTID = 1,
        .SIZEOF_PID_T = target.result.c_type_byte_size(.int),
        .SIZEOF_UID_T = target.result.c_type_byte_size(.uint),
        .SIZEOF_GID_T = target.result.c_type_byte_size(.uint),
        .SIZEOF_RLIM_T = target.result.c_type_byte_size(.ulonglong),
        .UDEV_ROOT_RUN = b.getInstallPath(.prefix, "run"),
        .UDEV_CONF_DIR = b.getInstallPath(.prefix, "etc/udev"),
        .UDEV_CONF_FILE = b.getInstallPath(.prefix, "etc/udev/udev.conf"),
        .UDEV_HWDB_DIR = b.getInstallPath(.prefix, "etc/udev/hwdb.d"),
        .UDEV_RULES_DIR = b.getInstallPath(.prefix, "etc/udev/rules.d"),
        .UDEV_LIBEXEC_DIR = b.getInstallPath(.prefix, "libexec"),
        .VERSION = "251",
        .UDEV_VERSION = "3.2.14",
        ._GNU_SOURCE = 1,
        .__USE_GNU = 1,
    });

    const libshared = b.addStaticLibrary(.{
        .name = "shared",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    includeConfigHeader(libshared, configHeader);
    libshared.addConfigHeader(configHeader);
    libshared.addIncludePath(source.path("src/shared"));

    libshared.addCSourceFiles(.{
        .root = source.path("src/shared"),
        .files = &.{
            "conf-files.c",
            "device-nodes.c",
            "dev-setup.c",
            "fileio.c",
            "hashmap.c",
            "label.c",
            "log.c",
            "mempool.c",
            "mkdir.c",
            "mkdir-label.c",
            "MurmurHash2.c",
            "path-util.c",
            "process-util.c",
            "random-util.c",
            "selinux-util.c",
            "siphash24.c",
            "smack-util.c",
            "strbuf.c",
            "strv.c",
            "strxcpyx.c",
            "sysctl-util.c",
            "terminal-util.c",
            "time-util.c",
            "util.c",
            "utf8.c",
            "virt.c",
        },
    });

    const libudev = std.Build.Step.Compile.create(b, .{
        .name = "udev",
        .root_module = .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        },
        .kind = .lib,
        .linkage = linkage,
    });

    includeConfigHeader(libudev, configHeader);
    libudev.addConfigHeader(configHeader);
    libudev.addIncludePath(source.path("src/shared"));
    libudev.addIncludePath(source.path("src/libudev"));

    libudev.addCSourceFiles(.{
        .root = source.path("src/libudev"),
        .files = &.{
            "libudev.c",
            "libudev-list.c",
            "libudev-util.c",
            "libudev-device.c",
            "libudev-enumerate.c",
            "libudev-monitor.c",
            "libudev-queue.c",
            "libudev-hwdb.c",
        },
    });

    libudev.setVersionScript(source.path("src/libudev/libudev.sym"));
    libudev.linkLibrary(libshared);

    b.installArtifact(libudev);

    {
        const install_file = b.addInstallFileWithDir(source.path("src/libudev/libudev.h"), .header, "libudev.h");
        b.getInstallStep().dependOn(&install_file.step);
        libudev.installed_headers.append(&install_file.step) catch @panic("OOM");
    }

    const libudevCore = b.addStaticLibrary(.{
        .name = "udev-core",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    includeConfigHeader(libudevCore, configHeader);
    libudevCore.addConfigHeader(configHeader);
    libudevCore.addIncludePath(source.path("src/shared"));
    libudevCore.addIncludePath(source.path("src/libudev"));
    libudevCore.addIncludePath(source.path("src/udev"));
    libudevCore.addIncludePath(.{ .path = b.pathFromRoot("src/udev") });

    libudevCore.addCSourceFiles(.{
        .root = source.path("src/udev"),
        .files = &.{
            "udev-event.c",
            "udev-watch.c",
            "udev-node.c",
            "udev-rules.c",
            "udev-ctrl.c",
            "udev-builtin.c",
            "udev-builtin-keyboard.c",
            "udev-builtin-btrfs.c",
            "udev-builtin-hwdb.c",
            "udev-builtin-input_id.c",
            "udev-builtin-net_id.c",
            "udev-builtin-path_id.c",
            "udev-builtin-usb_id.c",
        },
    });

    libudev.addCSourceFile(.{
        .file = source.path("src/libudev/libudev-device-private.c"),
    });

    const udevadm = b.addExecutable(.{
        .name = "udevadm",
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .link_libc = true,
    });

    includeConfigHeader(udevadm, configHeader);
    udevadm.addConfigHeader(configHeader);
    udevadm.addIncludePath(source.path("src/shared"));
    udevadm.addIncludePath(source.path("src/libudev"));
    udevadm.addIncludePath(source.path("src/udev"));

    udevadm.addCSourceFiles(.{
        .root = source.path("src/udev"),
        .files = &.{
            "udevadm.c",
            "udevadm-info.c",
            "udevadm-control.c",
            "udevadm-monitor.c",
            "udevadm-hwdb.c",
            "udevadm-settle.c",
            "udevadm-trigger.c",
            "udevadm-test.c",
            "udevadm-test-builtin.c",
            "udevadm-util.c",
        },
    });

    udevadm.linkLibrary(libudev);
    udevadm.linkLibrary(libudevCore);

    b.installArtifact(udevadm);

    const udevd = b.addExecutable(.{
        .name = "udevd",
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .link_libc = true,
    });

    includeConfigHeader(udevd, configHeader);
    udevd.addConfigHeader(configHeader);
    udevd.addIncludePath(source.path("src/shared"));
    udevd.addIncludePath(source.path("src/libudev"));
    udevd.addIncludePath(source.path("src/udev"));

    udevd.addCSourceFile(.{
        .file = source.path("src/udev/udevd.c"),
    });

    udevd.linkLibrary(libudev);
    udevd.linkLibrary(libudevCore);

    b.getInstallStep().dependOn(&b.addInstallArtifact(udevd, .{
        .dest_dir = .{
            .override = .{
                .custom = "sbin",
            },
        },
    }).step);
}
