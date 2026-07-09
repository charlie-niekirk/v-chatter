//! This build belongs to your app, written once by `native eject`:
//! the `native` CLI stops generating a build graph and
//! drives this file through `zig build` instead, and it will
//! never rewrite it. `addApp` wires the complete standard app
//! build — executable, `zig build run`, `zig build test`, and
//! the -Dplatform/-Dweb-engine/-Dautomation/-Doptimize flags —
//! from the framework's build/app.zig, so a framework upgrade
//! still upgrades your build. Extend from here with
//! `addAppArtifacts` when you need extra sources or steps.

const std = @import("std");
const native_sdk = @import("native_sdk");

pub fn build(b: *std.Build) void {
    const twitch_client_id = b.option([]const u8, "TWITCH_CLIENT_ID", "Public Twitch Client ID compiled into the app") orelse "";
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "twitch_client_id", twitch_client_id);
    const build_options_module = build_options.createModule();

    const artifacts = native_sdk.addAppArtifacts(b, b.dependency("native_sdk", .{}), .{ .name = "v-chatter" });
    artifacts.exe.root_module.addImport("v_chatter_build_options", build_options_module);
    artifacts.tests.root_module.addImport("v_chatter_build_options", build_options_module);

    const worker_options = b.addOptions();
    worker_options.addOption(bool, "websocket_blocking", false);
    const websocket_module = b.createModule(.{
        .root_source_file = b.path("vendor/websocket-zig/src/websocket.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
        .link_libc = true,
    });
    websocket_module.addOptions("build", worker_options);
    const worker_module = b.createModule(.{
        .root_source_file = b.path("src/eventsub_worker.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
        .link_libc = true,
    });
    worker_module.addImport("websocket", websocket_module);
    const worker = b.addExecutable(.{ .name = "v-chatter-eventsub", .root_module = worker_module });
    b.installArtifact(worker);
}
