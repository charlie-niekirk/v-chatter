const build_options = @import("v_chatter_build_options");

/// Twitch client IDs are public identifiers, but an empty value keeps local
/// debug builds from accidentally impersonating the production application.
pub const twitch_client_id: []const u8 = build_options.twitch_client_id;

pub fn hasTwitchClientId() bool {
    return twitch_client_id.len > 0;
}
