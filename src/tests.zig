const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const app_state = @import("app_state.zig");
const chat = @import("chat.zig");
const config = @import("config.zig");
const storage = @import("storage.zig");
const twitch = @import("twitch.zig");

const canvas = native_sdk.canvas;
const testing = std.testing;

const AppUi = main.AppUi;
const Model = main.Model;
const Msg = main.Msg;

const AppMarkup = canvas.MarkupView(Model, Msg);

fn buildTree(arena: std.mem.Allocator, model: *const Model) !AppUi.Tree {
    var view = try AppMarkup.init(arena, main.app_markup);
    var ui = AppUi.init(arena);
    const node = view.build(&ui, model) catch |err| {
        // Name the app.native position instead of leaving a bare error
        // trace: the usual causes are a binding without a matching
        // Model field or an on-* message without a Msg arm.
        if (err == error.MarkupBuild) {
            std.debug.print("app.native:{d}:{d}: {s}\n", .{ view.diagnostic.line, view.diagnostic.column, view.diagnostic.message });
        }
        return err;
    };
    return ui.finalize(node);
}

fn findByText(widget: canvas.Widget, kind: canvas.WidgetKind, text: []const u8) ?canvas.Widget {
    if (widget.kind == kind and std.mem.eql(u8, widget.text, text)) return widget;
    for (widget.children) |child| {
        if (findByText(child, kind, text)) |found| return found;
    }
    return null;
}

/// A miss fails the test with the mismatch spelled out instead of a
/// null-unwrap panic: the usual cause is app.native and this test
/// drifting apart after an edit.
fn expectByText(widget: canvas.Widget, kind: canvas.WidgetKind, text: []const u8) !canvas.Widget {
    return findByText(widget, kind, text) orelse {
        std.debug.print("no {t} with text \"{s}\" in the view - if you changed app.native, update this test to match\n", .{ kind, text });
        return error.WidgetNotFound;
    };
}

test "the signed-out shell is deterministic and excludes anonymous chat" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const model = main.initialModel();

    const tree = try buildTree(arena, &model);
    _ = try expectByText(tree.root, .text, "Sign in to Twitch");
    _ = try expectByText(tree.root, .text, "Twitch authentication will open in your default browser. V Chatter does not provide anonymous chat.");
    _ = try expectByText(tree.root, .status_bar, "Offline · Authentication opens in your default browser.");
    try testing.expectEqual(app_state.AuthState.signed_out, model.auth_state);
}

test "the view lays out through the canvas engine" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();

    const model = main.initialModel();
    const tree = try buildTree(arena_state.allocator(), &model);

    var nodes: [64]canvas.WidgetLayoutNode = undefined;
    const layout = try canvas.layoutWidgetTree(tree.root, native_sdk.geometry.RectF.init(0, 0, 960, 640), &nodes);
    try testing.expect(layout.nodes.len > 0);

    const title = try expectByText(tree.root, .text, "V Chatter");
    var saw_title = false;
    for (layout.nodes) |node| {
        if (node.widget.id == title.id) saw_title = true;
    }
    try testing.expect(saw_title);
}

test "preferences migrate version zero and never serialize credentials" {
    var loaded = try storage.decodePreferences(testing.allocator, "{\"theme\":\"dark\",\"saved_channels\":[]}");
    defer loaded.deinit();

    const migrated = loaded.preferences();
    try testing.expectEqual(storage.current_preferences_version, migrated.version);
    try testing.expectEqual(storage.Theme.dark, migrated.theme);

    const channels = [_]app_state.SavedChannel{.{ .broadcaster_id = "1", .login = "twitch", .display_name = "Twitch" }};
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try storage.encodePreferences(.{ .saved_channels = &channels }, &output.writer);

    const encoded = output.written();
    try testing.expect(std.mem.indexOf(u8, encoded, "access_token") == null);
    try testing.expect(std.mem.indexOf(u8, encoded, "refresh_token") == null);
    try testing.expect(std.mem.indexOf(u8, encoded, "Twitch") != null);
}

test "foundation boundaries expose an unconfigured Twitch client and channel cap" {
    try testing.expect(!config.hasTwitchClientId());
    const client: twitch.Client = .{};
    try testing.expect(!client.isConfigured());
    try testing.expect(chat.canActivate(&.{}));

    const full = [_]app_state.ActiveChannel{.{}} ** chat.max_active_channels;
    try testing.expect(!chat.canActivate(&full));
}
