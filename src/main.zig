//! Native SDK wiring for V Chatter. Application state and service boundaries
//! live in focused modules; this file owns only the app shell.

const std = @import("std");
const runner = @import("runner");
const native_sdk = @import("native_sdk");
const state = @import("app_state.zig");

// Keep these imports explicit: each subsystem gets its own implementation
// milestone, but the app surface is established from the first commit.
const chat = @import("chat.zig");
const config = @import("config.zig");
const twitch = @import("twitch.zig");
const storage = @import("storage.zig");

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

const canvas_label = "v-chatter-canvas";
const window_width: f32 = 960;
const window_height: f32 = 640;
const window_min_width: f32 = 720;
const window_min_height: f32 = 520;

const app_permissions = [_][]const u8{ native_sdk.security.permission_command, native_sdk.security.permission_view };
const shell_views = [_]native_sdk.ShellView{
    .{ .label = canvas_label, .kind = .gpu_surface, .fill = true, .role = "V Chatter application", .accessibility_label = "V Chatter", .gpu_backend = .metal, .gpu_pixel_format = .bgra8_unorm, .gpu_present_mode = .timer, .gpu_alpha_mode = .@"opaque", .gpu_color_space = .srgb, .gpu_vsync = true },
};
const shell_windows = [_]native_sdk.ShellWindow{.{
    .label = "main",
    .title = "V Chatter",
    .width = window_width,
    .height = window_height,
    .min_width = window_min_width,
    .min_height = window_min_height,
    .restore_state = true,
    .views = &shell_views,
}};
const shell_scene: native_sdk.ShellConfig = .{ .windows = &shell_windows };

// ------------------------------------------------------------------ model

pub const Msg = state.Msg;
pub const Model = state.Model;

pub fn update(_: *Model, msg: Msg) void {
    switch (msg) {}
}

// ------------------------------------------------------------------- view

pub const AppUi = canvas.Ui(Msg);
pub const app_markup = @embedFile("app.native");

// -------------------------------------------------------------------- app

const CounterApp = native_sdk.UiApp(Model, Msg);

pub fn initialModel() Model {
    _ = chat;
    _ = config;
    _ = twitch;
    _ = storage;
    return .{};
}

pub fn main(init: std.process.Init) !void {
    // The app struct (and any real Model) is multi-MB: `create`
    // heap-allocates and constructs everything in place, so neither
    // ever rides the stack. Mutate `app_state.model` through the
    // pointer before running if boot state is not the default.
    const app_state = try CounterApp.create(std.heap.page_allocator, .{
        .name = "v-chatter",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update = update,
        .markup = .{ .source = app_markup, .watch_path = "src/app.native", .io = init.io },
    });
    defer app_state.destroy();
    app_state.model = initialModel();

    try runner.runWithOptions(app_state.app(), .{
        .app_name = "v-chatter",
        .window_title = "V Chatter",
        .bundle_id = "dev.native_sdk.v-chatter",
        .icon_path = "assets/icon.png",
        .default_frame = geometry.RectF.init(0, 0, window_width, window_height),
        .restore_state = false,
        .js_window_api = false,
        .security = .{
            .permissions = &app_permissions,
            .navigation = .{ .allowed_origins = &.{ "zero://inline", "zero://app" } },
        },
    }, init);
}

test {
    _ = @import("tests.zig");
}
