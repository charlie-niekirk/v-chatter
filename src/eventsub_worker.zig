//! Small process boundary around the vendored WebSocket client. The Native SDK
//! effects channel owns this process and turns its newline-delimited frames
//! into UI-loop messages; no worker thread mutates the app model directly.

const std = @import("std");
const websocket = @import("websocket");

const twitch_host = "eventsub.wss.twitch.tv";
const prefix = "wss://eventsub.wss.twitch.tv";

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const url = args.next() orelse return error.MissingUrl;
    if (!std.mem.startsWith(u8, url, prefix)) return error.UntrustedEventSubUrl;
    const path = url[prefix.len..];
    if (path.len == 0 or path[0] != '/') return error.InvalidEventSubUrl;

    var client = try websocket.Client.init(init.io, init.gpa, .{
        .host = twitch_host,
        .port = 443,
        .tls = true,
        .max_size = 128 * 1024,
    });
    defer client.deinit();
    try client.handshake(path, .{ .headers = "Host: eventsub.wss.twitch.tv" });

    while (try client.read()) |message| {
        defer client.done(message);
        switch (message.type) {
            .text, .binary => {
                try std.Io.File.stdout().writeStreamingAll(init.io, message.data);
                try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
            },
            .ping => try client.writePong(message.data),
            .pong => {},
            .close => {
                try client.close(.{});
                return;
            },
        }
    }
}
