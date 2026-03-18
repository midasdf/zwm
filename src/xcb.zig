const std = @import("std");

pub const c = @cImport({
    @cInclude("xcb/xcb.h");
    @cInclude("xcb/xcb_keysyms.h");
    @cInclude("xcb/randr.h");
});

// Type aliases
pub const Window = c.xcb_window_t;
pub const Connection = c.xcb_connection_t;
pub const Screen = c.xcb_screen_t;
pub const Atom = c.xcb_atom_t;
pub const Keycode = c.xcb_keycode_t;
pub const Keysym = c.xcb_keysym_t;
pub const Timestamp = c.xcb_timestamp_t;
pub const GenericEvent = c.xcb_generic_event_t;
pub const GenericError = c.xcb_generic_error_t;

// Event type constants (response_type & ~0x80)
pub const MAP_REQUEST = c.XCB_MAP_REQUEST;
pub const UNMAP_NOTIFY = c.XCB_UNMAP_NOTIFY;
pub const DESTROY_NOTIFY = c.XCB_DESTROY_NOTIFY;
pub const KEY_PRESS = c.XCB_KEY_PRESS;
pub const ENTER_NOTIFY = c.XCB_ENTER_NOTIFY;
pub const CONFIGURE_REQUEST = c.XCB_CONFIGURE_REQUEST;
pub const PROPERTY_NOTIFY = c.XCB_PROPERTY_NOTIFY;
pub const BUTTON_PRESS = c.XCB_BUTTON_PRESS;
pub const BUTTON_RELEASE = c.XCB_BUTTON_RELEASE;
pub const MOTION_NOTIFY = c.XCB_MOTION_NOTIFY;

// Helper functions

pub fn connect(display: ?[*:0]const u8, screen: ?*c_int) ?*Connection {
    return c.xcb_connect(display, screen);
}

pub fn disconnect(conn: *Connection) void {
    c.xcb_disconnect(conn);
}

pub fn flush(conn: *Connection) c_int {
    return c.xcb_flush(conn);
}

pub fn waitForEvent(conn: *Connection) ?*GenericEvent {
    return c.xcb_wait_for_event(conn);
}

pub fn eventType(event: *GenericEvent) u8 {
    return event.response_type & ~@as(u8, 0x80);
}

pub fn internAtom(conn: *Connection, only_if_exists: bool, name: []const u8) c.xcb_intern_atom_cookie_t {
    return c.xcb_intern_atom(
        conn,
        @intFromBool(only_if_exists),
        @intCast(name.len),
        name.ptr,
    );
}

pub fn internAtomReply(conn: *Connection, cookie: c.xcb_intern_atom_cookie_t) ?*c.xcb_intern_atom_reply_t {
    return c.xcb_intern_atom_reply(conn, cookie, null);
}

pub fn generateId(conn: *Connection) Window {
    return c.xcb_generate_id(conn);
}
