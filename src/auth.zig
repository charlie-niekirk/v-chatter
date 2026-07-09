//! Twitch device-code protocol helpers. These routines deliberately operate
//! on caller-owned buffers so an OAuth token never needs to enter a log,
//! preferences document, or heap-allocated request object.

const std = @import("std");

pub const scopes = "user:read:chat user:write:chat";
pub const encoded_scopes = "user%3Aread%3Achat+user%3Awrite%3Achat";

pub const device_endpoint = "https://id.twitch.tv/oauth2/device";
pub const token_endpoint = "https://id.twitch.tv/oauth2/token";
pub const validate_endpoint = "https://id.twitch.tv/oauth2/validate";
pub const users_endpoint = "https://api.twitch.tv/helix/users";
pub const revoke_endpoint = "https://id.twitch.tv/oauth2/revoke";

pub const TokenFailure = enum {
    pending,
    slow_down,
    denied,
    expired,
    invalid,
    unexpected,
};

pub fn deviceRequestBody(buffer: []u8, client_id: []const u8) ![]const u8 {
    // Twitch client IDs are public identifiers. Validate their conservative
    // character set before placing one in an x-www-form-urlencoded body.
    if (!isClientId(client_id)) return error.InvalidClientId;
    return std.fmt.bufPrint(buffer, "client_id={s}&scopes={s}", .{ client_id, encoded_scopes });
}

pub fn deviceTokenRequestBody(buffer: []u8, client_id: []const u8, device_code: []const u8) ![]const u8 {
    if (!isClientId(client_id) or device_code.len == 0) return error.InvalidRequest;
    return std.fmt.bufPrint(
        buffer,
        "client_id={s}&scopes={s}&device_code={s}&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code",
        .{ client_id, encoded_scopes, device_code },
    );
}

pub fn refreshRequestBody(buffer: []u8, client_id: []const u8, refresh_token: []const u8) ![]const u8 {
    if (!isClientId(client_id) or !isOpaqueToken(refresh_token)) return error.InvalidRequest;
    return std.fmt.bufPrint(
        buffer,
        "client_id={s}&grant_type=refresh_token&refresh_token={s}",
        .{ client_id, refresh_token },
    );
}

pub fn revokeRequestBody(buffer: []u8, client_id: []const u8, access_token: []const u8) ![]const u8 {
    if (!isClientId(client_id) or !isOpaqueToken(access_token)) return error.InvalidRequest;
    return std.fmt.bufPrint(buffer, "client_id={s}&token={s}", .{ client_id, access_token });
}

pub fn classifyTokenFailure(status: u16, response: []const u8) TokenFailure {
    if (status != 400 and status != 401) return .unexpected;

    const Payload = struct { message: []const u8 = "" };
    var parsed = std.json.parseFromSlice(Payload, std.heap.page_allocator, response, .{ .ignore_unknown_fields = true }) catch return .unexpected;
    defer parsed.deinit();

    const message = parsed.value.message;
    if (std.mem.eql(u8, message, "authorization_pending")) return .pending;
    if (std.mem.eql(u8, message, "slow_down")) return .slow_down;
    if (std.mem.eql(u8, message, "access_denied")) return .denied;
    if (std.mem.eql(u8, message, "expired_token")) return .expired;
    if (std.mem.indexOf(u8, message, "Invalid") != null or std.mem.indexOf(u8, message, "invalid") != null) return .invalid;
    return .unexpected;
}

pub fn containsOnlyRequestedScopes(returned_scopes: []const []const u8) bool {
    if (returned_scopes.len != 2) return false;
    var read = false;
    var write = false;
    for (returned_scopes) |scope| {
        if (std.mem.eql(u8, scope, "user:read:chat")) read = true
        else if (std.mem.eql(u8, scope, "user:write:chat")) write = true
        else return false;
    }
    return read and write;
}

fn isClientId(value: []const u8) bool {
    if (value.len == 0 or value.len > 128) return false;
    for (value) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '-') return false;
    }
    return true;
}

fn isOpaqueToken(value: []const u8) bool {
    if (value.len == 0 or value.len > 1024) return false;
    for (value) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '-') return false;
    }
    return true;
}

test "device request asks for only chat read and write" {
    var buffer: [256]u8 = undefined;
    const body = try deviceRequestBody(&buffer, "public-client-id");
    try std.testing.expectEqualStrings("client_id=public-client-id&scopes=user%3Aread%3Achat+user%3Awrite%3Achat", body);
}

test "device token failure states are deterministic" {
    try std.testing.expectEqual(TokenFailure.pending, classifyTokenFailure(400, "{\"message\":\"authorization_pending\"}"));
    try std.testing.expectEqual(TokenFailure.denied, classifyTokenFailure(400, "{\"message\":\"access_denied\"}"));
    try std.testing.expectEqual(TokenFailure.expired, classifyTokenFailure(400, "{\"message\":\"expired_token\"}"));
}

test "returned scopes reject overbroad access" {
    try std.testing.expect(containsOnlyRequestedScopes(&.{ "user:read:chat", "user:write:chat" }));
    try std.testing.expect(!containsOnlyRequestedScopes(&.{ "user:read:chat", "chat:edit" }));
}
