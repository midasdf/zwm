const std = @import("std");
const xcb = @import("xcb.zig");
const c = xcb.c;

pub const MonitorInfo = struct {
    x: i16,
    y: i16,
    w: u16,
    h: u16,
};

/// Query XRandR for active CRTCs and return monitor geometries.
/// Skips disabled CRTCs (w/h == 0). Falls back to full screen if none found.
pub fn detectMonitors(
    conn: *c.xcb_connection_t,
    screen: *c.xcb_screen_t,
    buf: []MonitorInfo,
) []MonitorInfo {
    if (buf.len == 0) return buf[0..0];

    const res_cookie = c.xcb_randr_get_screen_resources(conn, screen.root);
    const res_reply: ?*c.xcb_randr_get_screen_resources_reply_t =
        c.xcb_randr_get_screen_resources_reply(conn, res_cookie, null);

    if (res_reply) |res| {
        defer std.c.free(@ptrCast(res));

        const num_crtcs = c.xcb_randr_get_screen_resources_crtcs_length(res);
        if (num_crtcs > 0) {
            const crtcs: [*]c.xcb_randr_crtc_t = c.xcb_randr_get_screen_resources_crtcs(res);
            const crtc_count: usize = @intCast(num_crtcs);

            var count: usize = 0;
            for (0..crtc_count) |i| {
                if (count >= buf.len) break;

                const crtc_cookie = c.xcb_randr_get_crtc_info(conn, crtcs[i], 0);
                const crtc_reply: ?*c.xcb_randr_get_crtc_info_reply_t =
                    c.xcb_randr_get_crtc_info_reply(conn, crtc_cookie, null);

                if (crtc_reply) |crtc| {
                    defer std.c.free(@ptrCast(crtc));

                    // Skip disabled CRTCs
                    if (crtc.width == 0 or crtc.height == 0) continue;

                    buf[count] = .{
                        .x = crtc.x,
                        .y = crtc.y,
                        .w = crtc.width,
                        .h = crtc.height,
                    };
                    count += 1;
                }
            }

            if (count > 0) return buf[0..count];
        }
    }

    // Fallback: single monitor = full screen
    buf[0] = .{
        .x = 0,
        .y = 0,
        .w = screen.width_in_pixels,
        .h = screen.height_in_pixels,
    };
    return buf[0..1];
}

/// Subscribe to RandR screen change notifications.
pub fn subscribeScreenChange(conn: *c.xcb_connection_t, screen: *c.xcb_screen_t) void {
    _ = c.xcb_randr_select_input(
        conn,
        screen.root,
        c.XCB_RANDR_NOTIFY_MASK_SCREEN_CHANGE,
    );
    _ = c.xcb_flush(conn);
}
