const state = @import("app_state.zig");

pub const max_active_channels: usize = 10;

pub fn canActivate(current: []const state.ActiveChannel) bool {
    return current.len < max_active_channels;
}
