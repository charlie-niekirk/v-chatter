const ui = @import("ui.zig");

pub const AuthState = enum {
    signed_out,
    authenticating,
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
    user_id: []const u8 = "",
    login: []const u8 = "",
    display_name: []const u8 = "",
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
    pub const view_unbound = .{ "auth_state", "connection_state" };

    auth_state: AuthState = .signed_out,
    connection_state: ConnectionState = .offline,

    pub fn authTitle(model: *const Model) []const u8 {
        return switch (model.auth_state) {
            .signed_out => ui.signed_out_title,
            .authenticating => "Finish signing in with Twitch",
            .signed_in => "Connected to Twitch",
        };
    }

    pub fn authDescription(model: *const Model) []const u8 {
        return switch (model.auth_state) {
            .signed_out => ui.signed_out_description,
            .authenticating => "V Chatter will keep this window ready while you approve access in your browser.",
            .signed_in => "Your Twitch identity is ready. Channel chat will be available in the next milestone.",
        };
    }

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

pub const Msg = union(enum) {};
