const std = @import("std");
const canvas = @import("native_sdk").canvas;

pub const max_active_channels: usize = 10;
pub const max_messages_per_channel: usize = 200;

pub fn canActivate(current: anytype) bool { return current.len < max_active_channels; }

pub fn FixedText(comptime capacity: usize) type {
    return struct {
        buffer: [capacity]u8 = @splat(0),
        len: usize = 0,
        pub fn slice(self: *const @This()) []const u8 { return self.buffer[0..self.len]; }
        pub fn set(self: *@This(), value: []const u8) !void {
            if (value.len > capacity) return error.ValueTooLong;
            @memcpy(self.buffer[0..value.len], value);
            self.len = value.len;
        }
        pub fn clear(self: *@This()) void { self.len = 0; }
    };
}

pub const ConnectionState = enum { offline, connecting, connected, reconnecting, failed };
pub const DeliveryState = enum { received, pending, sent, held, failed, rate_limited };

pub const Message = struct {
    id: FixedText(96) = .{},
    sender_login: FixedText(64) = .{},
    sender_name: FixedText(128) = .{},
    text: FixedText(500) = .{},
    delivery: DeliveryState = .received,

    pub fn body(message: *const Message) []const u8 { return message.text.slice(); }
    pub fn sender(message: *const Message) []const u8 { return message.sender_name.slice(); }
};

pub const Channel = struct {
    index: usize = 0,
    broadcaster_id: FixedText(64) = .{},
    login: FixedText(64) = .{},
    display_name: FixedText(128) = .{},
    subscription_id: FixedText(96) = .{},
    connection: ConnectionState = .offline,
    messages: [max_messages_per_channel]Message = [_]Message{.{}} ** max_messages_per_channel,
    message_count: usize = 0,
    unread_count: u32 = 0,

    pub fn label(channel: *const Channel) []const u8 { return channel.display_name.slice(); }
    pub fn isSelected(_: *const Channel) bool { return false; }
    pub fn connectionLabel(channel: *const Channel) []const u8 {
        return switch (channel.connection) { .offline => "Offline", .connecting => "Connecting", .connected => "Live", .reconnecting => "Reconnecting", .failed => "Needs attention" };
    }
};

pub const State = struct {
    channels: [max_active_channels]Channel = [_]Channel{.{}} ** max_active_channels,
    channel_count: usize = 0,
    selected_index: ?usize = null,
    channel_input: canvas.TextBuffer(64) = .{},
    composer_input: canvas.TextBuffer(500) = .{},
    inline_error: FixedText(192) = .{},
    socket_session_id: FixedText(128) = .{},
    reconnect_attempt: u8 = 0,

    pub fn activeChannels(state: *const State) []const Channel { return state.channels[0..state.channel_count]; }
    pub fn hasChannels(state: *const State) bool { return state.channel_count > 0; }
    pub fn hasError(state: *const State) bool { return state.inline_error.len > 0; }
    pub fn errorText(state: *const State) []const u8 { return state.inline_error.slice(); }
    pub fn canAdd(state: *const State) bool { return state.channel_count < max_active_channels; }
    pub fn selectedChannel(state: *State) ?*Channel { if (state.selected_index) |index| if (index < state.channel_count) return &state.channels[index]; return null; }
    pub fn selectedChannelConst(state: *const State) ?*const Channel { if (state.selected_index) |index| if (index < state.channel_count) return &state.channels[index]; return null; }
    pub fn selectedTitle(state: *const State) []const u8 { return if (state.selectedChannelConst()) |channel| channel.display_name.slice() else "Select a channel"; }
    pub fn selectedConnection(state: *const State) []const u8 { return if (state.selectedChannelConst()) |channel| channel.connectionLabel() else "Offline"; }
    pub fn selectedMessages(state: *const State) []const Message { return if (state.selectedChannelConst()) |channel| channel.messages[0..channel.message_count] else &.{}; }
};

pub fn normalizeLogin(input: []const u8, out: *FixedText(64)) !void {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyChannel;
    const login = if (trimmed[0] == '#') trimmed[1..] else trimmed;
    if (login.len == 0) return error.EmptyChannel;
    var buffer: [64]u8 = undefined;
    if (login.len > buffer.len) return error.InvalidChannel;
    for (login, 0..) |byte, i| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_') return error.InvalidChannel;
        buffer[i] = std.ascii.toLower(byte);
    }
    try out.set(buffer[0..login.len]);
}

pub fn containsLogin(state: *const State, login: []const u8) bool {
    for (state.activeChannels()) |channel| if (std.mem.eql(u8, channel.login.slice(), login)) return true;
    return false;
}

pub fn addResolvedChannel(state: *State, broadcaster_id: []const u8, login: []const u8, display_name: []const u8) !*Channel {
    if (!state.canAdd()) return error.ChannelLimitReached;
    if (containsLogin(state, login)) return error.DuplicateChannel;
    const channel = &state.channels[state.channel_count];
    channel.* = .{ .index = state.channel_count, .connection = .connecting };
    try channel.broadcaster_id.set(broadcaster_id);
    try channel.login.set(login);
    try channel.display_name.set(display_name);
    state.selected_index = state.channel_count;
    state.channel_count += 1;
    state.inline_error.clear();
    return channel;
}

pub fn removeChannel(state: *State, index: usize) ?Channel {
    if (index >= state.channel_count) return null;
    const removed = state.channels[index];
    var cursor = index;
    while (cursor + 1 < state.channel_count) : (cursor += 1) {
        state.channels[cursor] = state.channels[cursor + 1];
        state.channels[cursor].index = cursor;
    }
    state.channel_count -= 1;
    state.channels[state.channel_count] = .{};
    if (state.channel_count == 0) state.selected_index = null else state.selected_index = @min(index, state.channel_count - 1);
    return removed;
}

pub fn appendMessage(channel: *Channel, message_id: []const u8, sender_login: []const u8, sender_name: []const u8, text: []const u8, delivery: DeliveryState) !bool {
    for (channel.messages[0..channel.message_count]) |existing| if (std.mem.eql(u8, existing.id.slice(), message_id)) return false;
    const target = if (channel.message_count < max_messages_per_channel) blk: { const i = channel.message_count; channel.message_count += 1; break :blk &channel.messages[i]; } else blk: {
        std.mem.copyForwards(Message, channel.messages[0 .. max_messages_per_channel - 1], channel.messages[1..]);
        break :blk &channel.messages[max_messages_per_channel - 1];
    };
    target.* = .{ .delivery = delivery };
    try target.id.set(message_id);
    try target.sender_login.set(sender_login);
    try target.sender_name.set(sender_name);
    try target.text.set(text);
    return true;
}

test "channels reject empty duplicate and over-capacity additions" {
    var state: State = .{};
    var login: FixedText(64) = .{};
    try std.testing.expectError(error.EmptyChannel, normalizeLogin("  ", &login));
    try normalizeLogin("#Twitch", &login);
    _ = try addResolvedChannel(&state, "1", login.slice(), "Twitch");
    try std.testing.expectError(error.DuplicateChannel, addResolvedChannel(&state, "2", "twitch", "Twitch"));
    while (state.channel_count < max_active_channels) {
        var id: [16]u8 = undefined;
        const login_name = try std.fmt.bufPrint(&id, "channel{d}", .{state.channel_count});
        _ = try addResolvedChannel(&state, "2", login_name, "Channel");
    }
    try std.testing.expectError(error.ChannelLimitReached, addResolvedChannel(&state, "3", "other", "Other"));
}

test "each channel keeps an isolated bounded deduplicated timeline" {
    var state: State = .{};
    const first = try addResolvedChannel(&state, "1", "one", "One");
    const second = try addResolvedChannel(&state, "2", "two", "Two");
    try std.testing.expect(try appendMessage(first, "a", "viewer", "Viewer", "hello", .received));
    try std.testing.expect(!try appendMessage(first, "a", "viewer", "Viewer", "hello", .received));
    try std.testing.expect(try appendMessage(second, "a", "viewer", "Viewer", "other room", .received));
    try std.testing.expectEqual(@as(usize, 1), first.message_count);
    try std.testing.expectEqual(@as(usize, 1), second.message_count);
}
