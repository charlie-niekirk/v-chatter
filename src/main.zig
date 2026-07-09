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
const auth = @import("auth.zig");

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
const CounterApp = native_sdk.UiApp(Model, Msg);
const Effects = CounterApp.Effects;

const request_device_code_key: u64 = 1;
const request_token_key: u64 = 2;
const request_validation_key: u64 = 3;
const request_user_key: u64 = 4;
const request_revoke_key: u64 = 5;
const poll_timer_key: u64 = 1;
const oauth_timeout_ms: u32 = 15_000;

pub fn update(model: *Model, msg: Msg, fx: *Effects) void {
    switch (msg) {
        .begin_auth => startDeviceAuthorization(model, fx),
        .reopen_browser => openVerificationUri(model, fx),
        .cancel_auth => resetToSignedOut(model, fx, "Twitch sign-in cancelled. You can try again when ready."),
        .sign_out => signOut(model, fx),
        .device_code_response => |response| handleDeviceCodeResponse(model, fx, response),
        .token_response => |response| handleTokenResponse(model, fx, response),
        .validation_response => |response| handleValidationResponse(model, fx, response),
        .user_response => |response| handleUserResponse(model, fx, response),
        .poll_timer => |timer| {
            if (timer.outcome == .fired and model.auth_phase == .waiting_for_authorization) requestDeviceToken(model, fx);
            if (timer.outcome == .rejected) resetToSignedOut(model, fx, "Your system could not schedule Twitch sign-in. Please try again.");
        },
    }
}

// ------------------------------------------------------------------- view

pub const AppUi = canvas.Ui(Msg);
pub const app_markup = @embedFile("app.native");

// -------------------------------------------------------------------- app

pub fn initialModel() Model {
    _ = chat;
    _ = config;
    _ = twitch;
    _ = storage;
    return .{};
}

fn initialEffects(model: *Model, fx: *Effects) void {
    restoreSession(model, fx);
}

fn keychain(fx: *Effects) ?storage.KeychainStore {
    const services = fx.services orelse return null;
    return .{ .services = services.* };
}

fn startDeviceAuthorization(model: *Model, fx: *Effects) void {
    if (!config.hasTwitchClientId()) {
        resetToSignedOut(model, fx, "This build is missing its public Twitch Client ID. Rebuild with -DTWITCH_CLIENT_ID=… to sign in.");
        return;
    }
    clearDeviceAuthorization(model);
    model.auth_error.clear();
    model.auth_state = .authenticating;
    model.auth_phase = .requesting_device_code;

    var body_buffer: [512]u8 = undefined;
    const body = auth.deviceRequestBody(&body_buffer, config.twitch_client_id) catch {
        resetToSignedOut(model, fx, "The configured Twitch Client ID is invalid.");
        return;
    };
    fx.fetch(.{
        .key = request_device_code_key,
        .method = .POST,
        .url = auth.device_endpoint,
        .headers = &.{.{ .name = "content-type", .value = "application/x-www-form-urlencoded" }},
        .body = body,
        .timeout_ms = oauth_timeout_ms,
        .on_response = Effects.responseMsg(.device_code_response),
    });
}

fn handleDeviceCodeResponse(model: *Model, fx: *Effects, response: native_sdk.EffectResponse) void {
    if (response.outcome != .ok or response.status != 200 or response.truncated) {
        resetToSignedOut(model, fx, "Twitch could not start browser sign-in. Check your connection and try again.");
        return;
    }
    const DeviceResponse = struct {
        device_code: []const u8 = "",
        expires_in: u32 = 0,
        interval: u32 = 5,
        user_code: []const u8 = "",
        verification_uri: []const u8 = "",
    };
    var parsed = std.json.parseFromSlice(DeviceResponse, std.heap.page_allocator, response.body, .{ .ignore_unknown_fields = true }) catch {
        resetToSignedOut(model, fx, "Twitch returned an unreadable sign-in response. Please try again.");
        return;
    };
    defer parsed.deinit();
    const value = parsed.value;
    if (value.device_code.len == 0 or value.user_code.len == 0 or value.expires_in == 0 or !std.mem.startsWith(u8, value.verification_uri, "https://www.twitch.tv/activate")) {
        resetToSignedOut(model, fx, "Twitch returned an invalid browser sign-in link. Please try again.");
        return;
    }
    model.device_code.set(value.device_code) catch {
        resetToSignedOut(model, fx, "Twitch returned an unsupported sign-in response. Please try again.");
        return;
    };
    model.device_user_code.set(value.user_code) catch {
        resetToSignedOut(model, fx, "Twitch returned an unsupported sign-in code. Please try again.");
        return;
    };
    model.verification_uri.set(value.verification_uri) catch {
        resetToSignedOut(model, fx, "Twitch returned an unsupported sign-in link. Please try again.");
        return;
    };
    model.auth_phase = .waiting_for_authorization;
    model.poll_interval_seconds = @max(value.interval, 5);
    openVerificationUri(model, fx);
    schedulePoll(model, fx);
}

fn openVerificationUri(model: *Model, fx: *Effects) void {
    if (model.auth_phase != .waiting_for_authorization) return;
    const services = fx.services orelse {
        setError(model, "The system browser service is unavailable. Please restart V Chatter.");
        return;
    };
    services.openExternalUrl(model.verification_uri.slice()) catch {
        setError(model, "V Chatter could not open your default browser. Use the displayed URL and code, then return here.");
    };
}

fn schedulePoll(model: *Model, fx: *Effects) void {
    fx.startTimer(.{
        .key = poll_timer_key,
        .interval_ms = @as(u64, model.poll_interval_seconds) * 1000,
        .on_fire = Effects.timerMsg(.poll_timer),
    });
}

fn requestDeviceToken(model: *Model, fx: *Effects) void {
    var body_buffer: [2048]u8 = undefined;
    const body = auth.deviceTokenRequestBody(&body_buffer, config.twitch_client_id, model.device_code.slice()) catch {
        resetToSignedOut(model, fx, "The browser sign-in request expired. Please start again.");
        return;
    };
    fx.fetch(.{
        .key = request_token_key,
        .method = .POST,
        .url = auth.token_endpoint,
        .headers = &.{.{ .name = "content-type", .value = "application/x-www-form-urlencoded" }},
        .body = body,
        .timeout_ms = oauth_timeout_ms,
        .on_response = Effects.responseMsg(.token_response),
    });
}

fn restoreSession(model: *Model, fx: *Effects) void {
    if (!config.hasTwitchClientId()) return;
    const store = keychain(fx) orelse return;
    var access_buffer: [1024]u8 = undefined;
    const access = store.loadAccessToken(&access_buffer) catch {
        startRefreshFromKeychain(model, fx, store);
        return;
    };
    model.auth_state = .authenticating;
    model.auth_phase = .restoring;
    beginValidation(model, fx, access);
}

fn startRefreshFromKeychain(model: *Model, fx: *Effects, store: storage.KeychainStore) void {
    var refresh_buffer: [1024]u8 = undefined;
    const refresh = store.loadRefreshToken(&refresh_buffer) catch {
        resetToSignedOut(model, fx, "Your saved Twitch session has expired. Please sign in again.");
        return;
    };
    var body_buffer: [2048]u8 = undefined;
    const body = auth.refreshRequestBody(&body_buffer, config.twitch_client_id, refresh) catch {
        resetToSignedOut(model, fx, "Your saved Twitch session is invalid. Please sign in again.");
        return;
    };
    model.auth_state = .authenticating;
    model.auth_phase = .refreshing;
    fx.fetch(.{
        .key = request_token_key,
        .method = .POST,
        .url = auth.token_endpoint,
        .headers = &.{.{ .name = "content-type", .value = "application/x-www-form-urlencoded" }},
        .body = body,
        .timeout_ms = oauth_timeout_ms,
        .on_response = Effects.responseMsg(.token_response),
    });
}

fn handleTokenResponse(model: *Model, fx: *Effects, response: native_sdk.EffectResponse) void {
    if (response.outcome != .ok or response.truncated) {
        resetToSignedOut(model, fx, "Twitch could not complete sign-in. Check your connection and try again.");
        return;
    }
    if (response.status != 200) {
        switch (auth.classifyTokenFailure(response.status, response.body)) {
            .pending => if (model.auth_phase == .waiting_for_authorization) schedulePoll(model, fx),
            .slow_down => if (model.auth_phase == .waiting_for_authorization) {
                model.poll_interval_seconds = @min(model.poll_interval_seconds + 5, 60);
                schedulePoll(model, fx);
            },
            .denied => resetToSignedOut(model, fx, "Twitch access was denied. Try again to approve chat access."),
            .expired => resetToSignedOut(model, fx, "The Twitch sign-in code expired. Start a new sign-in attempt."),
            .invalid, .unexpected => resetToSignedOut(model, fx, "Your Twitch session is no longer valid. Please sign in again."),
        }
        return;
    }
    const TokenResponse = struct {
        access_token: []const u8 = "",
        refresh_token: []const u8 = "",
        expires_in: i64 = 0,
        scope: []const []const u8 = &.{},
    };
    var parsed = std.json.parseFromSlice(TokenResponse, std.heap.page_allocator, response.body, .{ .ignore_unknown_fields = true }) catch {
        resetToSignedOut(model, fx, "Twitch returned an unreadable session. Please sign in again.");
        return;
    };
    defer parsed.deinit();
    const token = parsed.value;
    if (token.access_token.len == 0 or token.refresh_token.len == 0 or !auth.containsOnlyRequestedScopes(token.scope)) {
        resetToSignedOut(model, fx, "Twitch did not grant the required chat permissions. Please sign in again.");
        return;
    }
    const store = keychain(fx) orelse {
        resetToSignedOut(model, fx, "macOS Keychain is unavailable, so V Chatter cannot safely store your session.");
        return;
    };
    store.save(.{ .access_token = token.access_token, .refresh_token = token.refresh_token }) catch {
        resetToSignedOut(model, fx, "V Chatter could not securely save your Twitch session. Please check Keychain access and try again.");
        return;
    };
    model.session.expires_at_unix_seconds = @divTrunc(fx.wallMs(), 1000) + token.expires_in;
    beginValidation(model, fx, token.access_token);
}

fn beginValidation(model: *Model, fx: *Effects, access_token: []const u8) void {
    var authorization: [1200]u8 = undefined;
    const header = std.fmt.bufPrint(&authorization, "OAuth {s}", .{access_token}) catch {
        resetToSignedOut(model, fx, "Your Twitch session is invalid. Please sign in again.");
        return;
    };
    model.auth_state = .authenticating;
    if (model.auth_phase != .restoring) model.auth_phase = .validating;
    fx.fetch(.{
        .key = request_validation_key,
        .url = auth.validate_endpoint,
        .headers = &.{.{ .name = "authorization", .value = header }},
        .timeout_ms = oauth_timeout_ms,
        .on_response = Effects.responseMsg(.validation_response),
    });
}

fn handleValidationResponse(model: *Model, fx: *Effects, response: native_sdk.EffectResponse) void {
    if (response.outcome != .ok or response.status == 401 or response.status == 403 or response.truncated) {
        const store = keychain(fx);
        if (model.auth_phase == .restoring and store != null) {
            startRefreshFromKeychain(model, fx, store.?);
            return;
        }
        resetToSignedOut(model, fx, "Your Twitch session could not be validated. Please sign in again.");
        return;
    }
    if (response.status != 200) {
        resetToSignedOut(model, fx, "Twitch could not validate your session. Please try again.");
        return;
    }
    const Validation = struct { user_id: []const u8 = "", login: []const u8 = "", expires_in: i64 = 0 };
    var parsed = std.json.parseFromSlice(Validation, std.heap.page_allocator, response.body, .{ .ignore_unknown_fields = true }) catch {
        resetToSignedOut(model, fx, "Twitch returned an unreadable session validation. Please sign in again.");
        return;
    };
    defer parsed.deinit();
    if (parsed.value.user_id.len == 0 or parsed.value.login.len == 0) {
        resetToSignedOut(model, fx, "Twitch did not return an authenticated user. Please sign in again.");
        return;
    }
    model.session.user_id.set(parsed.value.user_id) catch {
        resetToSignedOut(model, fx, "Your Twitch identity is too large to store safely.");
        return;
    };
    model.session.login.set(parsed.value.login) catch {
        resetToSignedOut(model, fx, "Your Twitch identity is too large to store safely.");
        return;
    };
    model.session.expires_at_unix_seconds = @divTrunc(fx.wallMs(), 1000) + parsed.value.expires_in;
    fetchUserIdentity(model, fx);
}

fn fetchUserIdentity(model: *Model, fx: *Effects) void {
    const store = keychain(fx) orelse {
        resetToSignedOut(model, fx, "macOS Keychain is unavailable. Please sign in again.");
        return;
    };
    var token_buffer: [1024]u8 = undefined;
    const token = store.loadAccessToken(&token_buffer) catch {
        resetToSignedOut(model, fx, "Your Twitch session is unavailable. Please sign in again.");
        return;
    };
    var authorization: [1200]u8 = undefined;
    const header = std.fmt.bufPrint(&authorization, "Bearer {s}", .{token}) catch {
        resetToSignedOut(model, fx, "Your Twitch session is invalid. Please sign in again.");
        return;
    };
    model.auth_phase = .loading_identity;
    fx.fetch(.{
        .key = request_user_key,
        .url = auth.users_endpoint,
        .headers = &.{
            .{ .name = "authorization", .value = header },
            .{ .name = "client-id", .value = config.twitch_client_id },
        },
        .timeout_ms = oauth_timeout_ms,
        .on_response = Effects.responseMsg(.user_response),
    });
}

fn handleUserResponse(model: *Model, fx: *Effects, response: native_sdk.EffectResponse) void {
    if (response.outcome != .ok or response.status != 200 or response.truncated) {
        resetToSignedOut(model, fx, "Twitch could not load your identity. Please sign in again.");
        return;
    }
    const User = struct { id: []const u8 = "", login: []const u8 = "", display_name: []const u8 = "" };
    const Users = struct { data: []const User = &.{} };
    var parsed = std.json.parseFromSlice(Users, std.heap.page_allocator, response.body, .{ .ignore_unknown_fields = true }) catch {
        resetToSignedOut(model, fx, "Twitch returned an unreadable identity. Please sign in again.");
        return;
    };
    defer parsed.deinit();
    const users = parsed.value.data;
    if (users.len != 1 or !std.mem.eql(u8, users[0].id, model.session.user_id.slice())) {
        resetToSignedOut(model, fx, "Twitch returned an unexpected identity. Please sign in again.");
        return;
    }
    model.session.display_name.set(users[0].display_name) catch {
        resetToSignedOut(model, fx, "Your Twitch display name is too large to store safely.");
        return;
    };
    model.auth_error.clear();
    clearDeviceAuthorization(model);
    model.auth_state = .signed_in;
    model.auth_phase = .signed_in;
}

fn signOut(model: *Model, fx: *Effects) void {
    if (keychain(fx)) |store| {
        var token_buffer: [1024]u8 = undefined;
        if (store.loadAccessToken(&token_buffer)) |token| {
            var body_buffer: [1400]u8 = undefined;
            if (auth.revokeRequestBody(&body_buffer, config.twitch_client_id, token)) |body| {
                fx.fetch(.{
                    .key = request_revoke_key,
                    .method = .POST,
                    .url = auth.revoke_endpoint,
                    .headers = &.{.{ .name = "content-type", .value = "application/x-www-form-urlencoded" }},
                    .body = body,
                    .timeout_ms = oauth_timeout_ms,
                });
            } else |_| {}
        } else |_| {}
        store.clear();
    }
    resetToSignedOut(model, fx, "You have signed out of Twitch.");
}

fn resetToSignedOut(model: *Model, fx: *Effects, message: []const u8) void {
    fx.cancel(request_device_code_key);
    fx.cancel(request_token_key);
    fx.cancel(request_validation_key);
    fx.cancel(request_user_key);
    fx.cancelTimer(poll_timer_key);
    if (keychain(fx)) |store| store.clear();
    clearDeviceAuthorization(model);
    model.session = .{};
    model.auth_state = .signed_out;
    model.auth_phase = .signed_out;
    setError(model, message);
}

fn clearDeviceAuthorization(model: *Model) void {
    model.device_code.clear();
    model.device_user_code.clear();
    model.verification_uri.clear();
    model.poll_interval_seconds = 5;
}

fn setError(model: *Model, message: []const u8) void {
    model.auth_error.set(message) catch model.auth_error.clear();
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
        .update_fx = update,
        .init_fx = initialEffects,
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
