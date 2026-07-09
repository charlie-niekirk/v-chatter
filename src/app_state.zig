const ui = @import("ui.zig");
const chat = @import("chat.zig");

pub fn FixedText(comptime capacity: usize) type {
    return struct {
        buffer: [capacity]u8 = @splat(0),
        len: usize = 0,

        pub fn slice(self: *const @This()) []const u8 {
            return self.buffer[0..self.len];
        }

        pub fn set(self: *@This(), value: []const u8) !void {
            if (value.len > capacity) return error.ValueTooLong;
            @memcpy(self.buffer[0..value.len], value);
            self.len = value.len;
        }

        pub fn clear(self: *@This()) void {
            self.len = 0;
        }
    };
}

pub const AuthState = enum {
    signed_out,
    authenticating,
    signed_in,
};

pub const AuthPhase = enum {
    signed_out,
    requesting_device_code,
    waiting_for_authorization,
    restoring,
    refreshing,
    validating,
    loading_identity,
    signed_in,
};

pub const ConnectionState = enum {
    offline,
    connecting,
    connected,
    reconnecting,
    failed,
};

/// Identity metadata only. OAuth credentials deliberately live outside the
/// UI model, in the platform credential store.
pub const AuthSession = struct {
    user_id: FixedText(64) = .{},
    login: FixedText(64) = .{},
    display_name: FixedText(128) = .{},
    expires_at_unix_seconds: i64 = 0,
};

pub const AuthCredentials = struct {
    access_token: []const u8,
    refresh_token: []const u8,
};

pub const SavedChannel = struct {
    broadcaster_id: []const u8 = "",
    login: []const u8 = "",
    display_name: []const u8 = "",
};

pub const ActiveChannel = struct {
    saved: SavedChannel = .{},
    connection_state: ConnectionState = .offline,
    unread_count: u32 = 0,
};

pub const MessageFragment = union(enum) {
    text: []const u8,
    twitch_emote: struct { id: []const u8, name: []const u8 },
    third_party_emote: struct { provider: []const u8, id: []const u8, name: []const u8 },
    mention: struct { user_id: []const u8, login: []const u8 },
};

pub const ChatMessage = struct {
    id: []const u8 = "",
    sender_id: []const u8 = "",
    sender_login: []const u8 = "",
    sender_display_name: []const u8 = "",
    sent_at_unix_seconds: i64 = 0,
    fragments: []const MessageFragment = &.{},
    reply_to_message_id: ?[]const u8 = null,
};

pub const Model = struct {
    // Device codes and credentials are intentionally not bound into markup.
    pub const view_unbound = .{ "auth_state", "connection_state", "auth_phase", "device_code", "device_user_code", "verification_uri", "poll_interval_seconds", "auth_error", "session", "chat" };

    auth_state: AuthState = .signed_out,
    auth_phase: AuthPhase = .signed_out,
    connection_state: ConnectionState = .offline,
    session: AuthSession = .{},
    device_code: FixedText(1024) = .{},
    device_user_code: FixedText(64) = .{},
    verification_uri: FixedText(512) = .{},
    poll_interval_seconds: u32 = 5,
    auth_error: FixedText(192) = .{},
    chat: chat.State = .{},

    pub fn authTitle(model: *const Model) []const u8 {
        return switch (model.auth_phase) {
            .signed_out => ui.signed_out_title,
            .requesting_device_code => "Preparing Twitch sign-in",
            .waiting_for_authorization => "Finish signing in with Twitch",
            .restoring => "Restoring your Twitch session",
            .refreshing => "Refreshing your Twitch session",
            .validating => "Verifying your Twitch session",
            .loading_identity => "Loading your Twitch identity",
            .signed_in => "Connected to Twitch",
        };
    }

    pub fn authDescription(model: *const Model) []const u8 {
        return switch (model.auth_phase) {
            .signed_out => ui.signed_out_description,
            .requesting_device_code => "Contacting Twitch to start secure browser authentication.",
            .waiting_for_authorization => "Approve access in your default browser. This app will continue automatically.",
            .restoring, .refreshing, .validating => "Checking your saved Twitch session before enabling chat.",
            .loading_identity => "Confirming the Twitch account that will send chat messages.",
            .signed_in => "Your Twitch identity is ready. Add channels to start a focused chat workspace.",
        };
    }

    pub fn hasAuthError(model: *const Model) bool {
        return model.auth_error.len > 0;
    }

    pub fn isSignedOut(model: *const Model) bool {
        return model.auth_phase == .signed_out;
    }

    pub fn isWaitingForAuthorization(model: *const Model) bool {
        return model.auth_phase == .waiting_for_authorization;
    }

    pub fn isSignedIn(model: *const Model) bool {
        return model.auth_phase == .signed_in;
    }

    pub fn authError(model: *const Model) []const u8 {
        return model.auth_error.slice();
    }

    pub fn userCode(model: *const Model) []const u8 {
        return model.device_user_code.slice();
    }

    pub fn verificationUri(model: *const Model) []const u8 {
        return model.verification_uri.slice();
    }

    pub fn displayName(model: *const Model) []const u8 {
        return model.session.display_name.slice();
    }

    pub fn channelInput(model: *const Model) []const u8 { return model.chat.channel_input.text(); }
    pub fn composerInput(model: *const Model) []const u8 { return model.chat.composer_input.text(); }
    pub fn hasChannels(model: *const Model) bool { return model.chat.hasChannels(); }
    pub fn hasChatError(model: *const Model) bool { return model.chat.hasError(); }
    pub fn chatError(model: *const Model) []const u8 { return model.chat.errorText(); }
    pub fn selectedChannelTitle(model: *const Model) []const u8 { return model.chat.selectedTitle(); }
    pub fn selectedChannelConnection(model: *const Model) []const u8 { return model.chat.selectedConnection(); }
    pub fn channels(model: *const Model) []const chat.Channel { return model.chat.activeChannels(); }

    pub fn connectionLabel(model: *const Model) []const u8 {
        return switch (model.connection_state) {
            .offline => "Offline",
            .connecting => "Connecting",
            .connected => "Connected",
            .reconnecting => "Reconnecting",
            .failed => "Connection needs attention",
        };
    }
};

pub const Msg = union(enum) {
    pub const view_unbound = .{ "device_code_response", "token_response", "validation_response", "user_response", "poll_timer", "channel_resolved", "send_message_response", "eventsub_line", "eventsub_exit", "subscription_response" };

    begin_auth,
    reopen_browser,
    cancel_auth,
    sign_out,
    device_code_response: @import("native_sdk").EffectResponse,
    token_response: @import("native_sdk").EffectResponse,
    validation_response: @import("native_sdk").EffectResponse,
    user_response: @import("native_sdk").EffectResponse,
    poll_timer: @import("native_sdk").EffectTimer,
    channel_input_changed: @import("native_sdk").canvas.TextInputEvent,
    add_channel,
    select_channel: usize,
    close_channel: usize,
    composer_input_changed: @import("native_sdk").canvas.TextInputEvent,
    send_message,
    channel_resolved: @import("native_sdk").EffectResponse,
    send_message_response: @import("native_sdk").EffectResponse,
    eventsub_line: @import("native_sdk").EffectLine,
    eventsub_exit: @import("native_sdk").EffectExit,
    subscription_response: @import("native_sdk").EffectResponse,
};
