const std = @import("std");
const native_sdk = @import("native_sdk");
const state = @import("app_state.zig");

pub const current_preferences_version: u32 = 1;
pub const keychain_service = "dev.native_sdk.v-chatter";
const access_token_account = "twitch.access-token";
const refresh_token_account = "twitch.refresh-token";

pub const Theme = enum {
    system,
    dark,
    light,
};

/// This is the only data shape that reaches the local preferences file.
/// It intentionally has no OAuth credential fields.
pub const Preferences = struct {
    version: u32 = current_preferences_version,
    theme: Theme = .system,
    saved_channels: []const state.SavedChannel = &.{},
};

const DiskPreferences = struct {
    version: u32 = 0,
    theme: Theme = .system,
    saved_channels: []const state.SavedChannel = &.{},
};

pub const DecodedPreferences = struct {
    parsed: std.json.Parsed(DiskPreferences),

    pub fn deinit(self: *DecodedPreferences) void {
        self.parsed.deinit();
    }

    pub fn preferences(self: *const DecodedPreferences) Preferences {
        return .{
            .version = current_preferences_version,
            .theme = self.parsed.value.theme,
            .saved_channels = self.parsed.value.saved_channels,
        };
    }
};

pub fn decodePreferences(allocator: std.mem.Allocator, bytes: []const u8) !DecodedPreferences {
    const parsed = try std.json.parseFromSlice(DiskPreferences, allocator, bytes, .{ .ignore_unknown_fields = true });
    if (parsed.value.version > current_preferences_version) {
        var rejected = parsed;
        rejected.deinit();
        return error.UnsupportedPreferencesVersion;
    }
    return .{ .parsed = parsed };
}

pub fn encodePreferences(preferences: Preferences, writer: *std.Io.Writer) !void {
    const disk: DiskPreferences = .{
        .version = current_preferences_version,
        .theme = preferences.theme,
        .saved_channels = preferences.saved_channels,
    };
    try std.json.Stringify.value(disk, .{}, writer);
}

pub const PreferencesFile = struct {
    path: []const u8,

    pub fn load(self: PreferencesFile, allocator: std.mem.Allocator, io: std.Io) !?DecodedPreferences {
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, self.path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return err,
        };
        defer allocator.free(bytes);
        return decodePreferences(allocator, bytes);
    }

    pub fn save(self: PreferencesFile, allocator: std.mem.Allocator, io: std.Io, preferences: Preferences) !void {
        var output: std.Io.Writer.Allocating = .init(allocator);
        defer output.deinit();
        try encodePreferences(preferences, &output.writer);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = self.path, .data = output.written() });
    }
};

/// The Native SDK maps this service to macOS Keychain on the production macOS
/// host. It is intentionally separate from `PreferencesFile`.
pub const KeychainStore = struct {
    services: native_sdk.platform.PlatformServices,
    service: []const u8 = keychain_service,

    pub fn save(self: KeychainStore, credentials: state.AuthCredentials) !void {
        if (credentials.access_token.len == 0 or credentials.refresh_token.len == 0) return error.InvalidCredentials;

        try self.services.setCredential(.{
            .service = self.service,
            .account = access_token_account,
            .secret = credentials.access_token,
        });
        errdefer self.services.deleteCredential(.{ .service = self.service, .account = access_token_account }) catch {};
        try self.services.setCredential(.{
            .service = self.service,
            .account = refresh_token_account,
            .secret = credentials.refresh_token,
        });
    }

    pub fn loadAccessToken(self: KeychainStore, buffer: []u8) ![]const u8 {
        return self.services.getCredential(.{ .service = self.service, .account = access_token_account }, buffer);
    }

    pub fn loadRefreshToken(self: KeychainStore, buffer: []u8) ![]const u8 {
        return self.services.getCredential(.{ .service = self.service, .account = refresh_token_account }, buffer);
    }

    pub fn clear(self: KeychainStore) void {
        _ = self.services.deleteCredential(.{ .service = self.service, .account = access_token_account }) catch {};
        _ = self.services.deleteCredential(.{ .service = self.service, .account = refresh_token_account }) catch {};
    }
};
