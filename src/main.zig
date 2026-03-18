const std = @import("std");
const xcb = @import("xcb.zig");
const layout = @import("layout.zig");
const config = @import("config.zig");
const wm_mod = @import("wm.zig");
const monitor_mod = @import("monitor.zig");

const c = xcb.c;
const Wm = wm_mod.Wm;

var running: bool = true;
var restart: bool = false;
var saved_argv: [*:null]const ?[*:0]const u8 = undefined;

fn sigHandler(sig: c_int) callconv(.c) void {
    switch (sig) {
        std.posix.SIG.TERM, std.posix.SIG.INT => {
            running = false;
        },
        std.posix.SIG.HUP => {
            running = false;
            restart = true;
        },
        else => {},
    }
}

pub fn main() !void {
    // Save argv for restart (the underlying C argv is null-terminated)
    saved_argv = @ptrCast(std.os.argv.ptr);

    std.debug.print("zwm starting\n", .{});

    // Setup signal handlers
    const sa = std.posix.Sigaction{
        .handler = .{ .handler = sigHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    const sa_ign = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.TERM, &sa, null);
    std.posix.sigaction(std.posix.SIG.INT, &sa, null);
    std.posix.sigaction(std.posix.SIG.HUP, &sa, null);
    std.posix.sigaction(std.posix.SIG.CHLD, &sa_ign, null);

    // Connect to X server
    var screen_num: c_int = 0;
    const conn = c.xcb_connect(null, &screen_num) orelse {
        std.debug.print("zwm: cannot open display\n", .{});
        return error.NoDisplay;
    };
    defer c.xcb_disconnect(conn);

    if (c.xcb_connection_has_error(conn) != 0) {
        std.debug.print("zwm: X connection error\n", .{});
        return error.ConnectionError;
    }

    // Get screen
    const setup = c.xcb_get_setup(conn);
    var iter = c.xcb_setup_roots_iterator(setup);
    // Advance to the requested screen
    var si: c_int = 0;
    while (si < screen_num) : (si += 1) {
        c.xcb_screen_next(&iter);
    }
    const screen: *c.xcb_screen_t = iter.data orelse {
        std.debug.print("zwm: cannot get screen\n", .{});
        return error.NoScreen;
    };

    // Try to become the window manager (SubstructureRedirect)
    const values = [_]u32{
        c.XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT |
            c.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY |
            c.XCB_EVENT_MASK_STRUCTURE_NOTIFY |
            c.XCB_EVENT_MASK_ENTER_WINDOW |
            c.XCB_EVENT_MASK_PROPERTY_CHANGE |
            c.XCB_EVENT_MASK_BUTTON_PRESS,
    };
    const cookie = c.xcb_change_window_attributes_checked(
        conn,
        screen.root,
        c.XCB_CW_EVENT_MASK,
        &values,
    );
    const err = c.xcb_request_check(conn, cookie);
    if (err != null) {
        std.c.free(err);
        std.debug.print("zwm: another window manager is already running\n", .{});
        return error.WmAlreadyRunning;
    }

    _ = c.xcb_flush(conn);

    std.debug.print("zwm: connected to X, screen {}x{}\n", .{ screen.width_in_pixels, screen.height_in_pixels });

    // Initialize WM state
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var wm = Wm.init(conn, screen, alloc, &running);
    defer wm.deinit();

    wm.grabKeys();
    wm.grabButtons();

    // Subscribe to RandR screen change events
    monitor_mod.subscribeScreenChange(conn, screen);

    // Query RandR event base for screen change detection
    const randr_cookie = c.xcb_query_extension(conn, 5, "RANDR");
    const randr_reply: ?*c.xcb_query_extension_reply_t = c.xcb_query_extension_reply(conn, randr_cookie, null);
    const randr_event_base: u8 = if (randr_reply) |r| blk: {
        defer std.c.free(@as(?*anyopaque, @ptrCast(r)));
        break :blk r.first_event;
    } else 0;

    // Detect monitors via XRandR
    wm.updateMonitors();

    // Scan existing windows
    wm.scanExisting();

    // Event loop
    while (running) {
        const event = c.xcb_wait_for_event(conn) orelse {
            // Connection broken
            break;
        };
        defer std.c.free(event);

        const event_type = xcb.eventType(event);
        switch (event_type) {
            xcb.MAP_REQUEST => {
                const ev: *c.xcb_map_request_event_t = @ptrCast(@alignCast(event));
                wm.manage(ev.window);
            },
            xcb.UNMAP_NOTIFY => {
                const ev: *c.xcb_unmap_notify_event_t = @ptrCast(@alignCast(event));
                wm.unmanage(ev.window);
            },
            xcb.DESTROY_NOTIFY => {
                const ev: *c.xcb_destroy_notify_event_t = @ptrCast(@alignCast(event));
                wm.unmanage(ev.window);
            },
            xcb.KEY_PRESS => {
                const ev: *c.xcb_key_press_event_t = @ptrCast(@alignCast(event));
                wm.handleKeyPress(ev);
            },
            xcb.BUTTON_PRESS => {
                const ev: *c.xcb_button_press_event_t = @ptrCast(@alignCast(event));
                wm.handleButtonPress(ev);
            },
            xcb.BUTTON_RELEASE => {
                wm.handleButtonRelease();
            },
            xcb.MOTION_NOTIFY => {
                const ev: *c.xcb_motion_notify_event_t = @ptrCast(@alignCast(event));
                wm.handleMotionNotify(ev);
            },
            xcb.ENTER_NOTIFY => {
                const ev: *c.xcb_enter_notify_event_t = @ptrCast(@alignCast(event));
                wm.handleEnterNotify(ev);
            },
            xcb.CONFIGURE_REQUEST => {
                const ev: *c.xcb_configure_request_event_t = @ptrCast(@alignCast(event));
                wm.handleConfigureRequest(ev);
            },
            xcb.PROPERTY_NOTIFY => {
                const ev: *c.xcb_property_notify_event_t = @ptrCast(@alignCast(event));
                wm.handlePropertyNotify(ev);
            },
            else => {
                // Check for RandR screen change event
                if (randr_event_base != 0 and event_type == randr_event_base + c.XCB_RANDR_SCREEN_CHANGE_NOTIFY) {
                    wm.handleScreenChange();
                }
            },
        }
    }

    std.debug.print("zwm: shutting down\n", .{});

    // Restart if requested
    if (restart) {
        std.debug.print("zwm: restarting...\n", .{});
        const self_path: [*:0]const u8 = "/proc/self/exe";
        std.posix.execveZ(self_path, saved_argv, std.c.environ) catch {
            std.debug.print("zwm: restart failed\n", .{});
        };
    }
}

comptime {
    _ = xcb;
    _ = config;
    _ = wm_mod;
    _ = monitor_mod;
}

test {
    _ = layout;
}
