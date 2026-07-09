const config = @import("config.zig");

/// The network client is introduced in the authentication milestone. Keeping
/// this small surface separate prevents UI code from owning credentials or
/// HTTP details.
pub const Client = struct {
    client_id: []const u8 = config.twitch_client_id,

    pub fn isConfigured(self: Client) bool {
        return self.client_id.len > 0;
    }
};
