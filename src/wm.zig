const std = @import("std");
const xcb = @import("xcb.zig");
const layout = @import("layout.zig");
const config = @import("config.zig");
const monitor_mod = @import("monitor.zig");

const c = xcb.c;
const Allocator = std.mem.Allocator;

// ===================== Client =====================

pub const Client = struct {
    window: xcb.Window,
    x: i16 = 0,
    y: i16 = 0,
    w: u16 = 0,
    h: u16 = 0,
    old_x: i16 = 0,
    old_y: i16 = 0,
    old_w: u16 = 0,
    old_h: u16 = 0,
    tags: u9 = 1,
    is_floating: bool = false,
    is_fullscreen: bool = false,
    monitor: *Monitor = undefined,
    prev: ?*Client = null,
    next: ?*Client = null,
};

// ===================== ClientList =====================

pub const ClientList = struct {
    head: ?*Client = null,
    tail: ?*Client = null,

    pub fn append(self: *ClientList, client: *Client) void {
        client.prev = self.tail;
        client.next = null;
        if (self.tail) |tail| {
            tail.next = client;
        } else {
            self.head = client;
        }
        self.tail = client;
    }

    pub fn remove(self: *ClientList, client: *Client) void {
        if (client.prev) |prev| {
            prev.next = client.next;
        } else {
            self.head = client.next;
        }
        if (client.next) |next_c| {
            next_c.prev = client.prev;
        } else {
            self.tail = client.prev;
        }
        client.prev = null;
        client.next = null;
    }

    pub fn insertHead(self: *ClientList, client: *Client) void {
        client.prev = null;
        client.next = self.head;
        if (self.head) |head| {
            head.prev = client;
        } else {
            self.tail = client;
        }
        self.head = client;
    }

    pub fn countVisible(self: *const ClientList, selected_tags: u9) u32 {
        var count: u32 = 0;
        var it = self.head;
        while (it) |client| : (it = client.next) {
            if ((client.tags & selected_tags) != 0 and !client.is_floating and !client.is_fullscreen) {
                count += 1;
            }
        }
        return count;
    }
};

// ===================== Monitor =====================

pub const Monitor = struct {
    x: i16 = 0,
    y: i16 = 0,
    w: u16 = 0,
    h: u16 = 0,
    selected_tags: u9 = 1,
    master_factor: f32 = config.master_factor,
    master_count: u8 = 1,
    clients: ClientList = .{},
    prev: ?*Monitor = null,
    next: ?*Monitor = null,
};

// ===================== Grab Type =====================

pub const GrabType = enum {
    none,
    move,
    resize,
};

// ===================== Wm =====================

pub const Wm = struct {
    conn: *c.xcb_connection_t,
    screen: *c.xcb_screen_t,
    alloc: Allocator,
    monitors: ?*Monitor = null,
    sel_monitor: *Monitor = undefined,
    focused: ?*Client = null,
    running: *bool,

    // Mouse grab state (Task 9)
    grab_type: GrabType = .none,
    grab_window: ?*Client = null,
    grab_start_x: i16 = 0,
    grab_start_y: i16 = 0,
    grab_client_x: i16 = 0,
    grab_client_y: i16 = 0,
    grab_client_w: u16 = 0,
    grab_client_h: u16 = 0,

    // EWMH atoms
    wm_protocols: xcb.Atom = 0,
    wm_delete_window: xcb.Atom = 0,
    wm_take_focus: xcb.Atom = 0,
    net_supported: xcb.Atom = 0,
    net_wm_state: xcb.Atom = 0,
    net_wm_state_fullscreen: xcb.Atom = 0,
    net_active_window: xcb.Atom = 0,
    net_wm_name: xcb.Atom = 0,
    net_current_desktop: xcb.Atom = 0,
    net_number_of_desktops: xcb.Atom = 0,
    net_wm_strut_partial: xcb.Atom = 0,
    wm_transient_for: xcb.Atom = 0,
    wm_normal_hints: xcb.Atom = 0,

    pub fn init(
        conn: *c.xcb_connection_t,
        screen: *c.xcb_screen_t,
        alloc: Allocator,
        running_flag: *bool,
    ) Wm {
        var wm = Wm{
            .conn = conn,
            .screen = screen,
            .alloc = alloc,
            .running = running_flag,
        };

        // Intern EWMH atoms
        wm.wm_protocols = wm.getAtom("WM_PROTOCOLS");
        wm.wm_delete_window = wm.getAtom("WM_DELETE_WINDOW");
        wm.wm_take_focus = wm.getAtom("WM_TAKE_FOCUS");
        wm.net_supported = wm.getAtom("_NET_SUPPORTED");
        wm.net_wm_state = wm.getAtom("_NET_WM_STATE");
        wm.net_wm_state_fullscreen = wm.getAtom("_NET_WM_STATE_FULLSCREEN");
        wm.net_active_window = wm.getAtom("_NET_ACTIVE_WINDOW");
        wm.net_wm_name = wm.getAtom("_NET_WM_NAME");
        wm.net_current_desktop = wm.getAtom("_NET_CURRENT_DESKTOP");
        wm.net_number_of_desktops = wm.getAtom("_NET_NUMBER_OF_DESKTOPS");
        wm.net_wm_strut_partial = wm.getAtom("_NET_WM_STRUT_PARTIAL");
        wm.wm_transient_for = wm.getAtom("WM_TRANSIENT_FOR");
        wm.wm_normal_hints = wm.getAtom("WM_NORMAL_HINTS");

        // Set _NET_SUPPORTED on root
        const supported = [_]xcb.Atom{
            wm.net_supported,
            wm.net_wm_state,
            wm.net_wm_state_fullscreen,
            wm.net_active_window,
            wm.net_wm_name,
            wm.net_current_desktop,
            wm.net_number_of_desktops,
        };
        _ = c.xcb_change_property(
            conn,
            c.XCB_PROP_MODE_REPLACE,
            screen.root,
            wm.net_supported,
            c.XCB_ATOM_ATOM,
            32,
            supported.len,
            &supported,
        );

        // Set _NET_NUMBER_OF_DESKTOPS = 9
        const num_desktops: u32 = 9;
        _ = c.xcb_change_property(
            conn,
            c.XCB_PROP_MODE_REPLACE,
            screen.root,
            wm.net_number_of_desktops,
            c.XCB_ATOM_CARDINAL,
            32,
            1,
            &num_desktops,
        );

        // Create default monitor
        const mon = alloc.create(Monitor) catch @panic("OOM");
        mon.* = .{
            .w = screen.width_in_pixels,
            .h = screen.height_in_pixels,
        };
        wm.monitors = mon;
        wm.sel_monitor = mon;

        _ = c.xcb_flush(conn);
        return wm;
    }

    pub fn deinit(self: *Wm) void {
        // Free all clients and monitors
        var mon = self.monitors;
        while (mon) |m| {
            var client = m.clients.head;
            while (client) |cl| {
                const next = cl.next;
                self.alloc.destroy(cl);
                client = next;
            }
            const next_mon = m.next;
            self.alloc.destroy(m);
            mon = next_mon;
        }
        self.monitors = null;
    }

    fn getAtom(self: *Wm, name: []const u8) xcb.Atom {
        const cookie = xcb.internAtom(self.conn, false, name);
        const reply = xcb.internAtomReply(self.conn, cookie) orelse return 0;
        defer std.c.free(reply);
        return reply.atom;
    }

    pub fn manage(self: *Wm, window: xcb.Window) void {
        // Don't manage if already managed
        if (self.findClient(window) != null) return;

        const client = self.alloc.create(Client) catch return;
        client.* = .{
            .window = window,
            .tags = self.sel_monitor.selected_tags,
            .monitor = self.sel_monitor,
        };

        // Get window geometry
        const geom_cookie = c.xcb_get_geometry(self.conn, window);
        const geom_reply: ?*c.xcb_get_geometry_reply_t = c.xcb_get_geometry_reply(self.conn, geom_cookie, null);
        if (geom_reply) |geom| {
            client.x = geom.x;
            client.y = geom.y;
            client.w = geom.width;
            client.h = geom.height;
            client.old_x = geom.x;
            client.old_y = geom.y;
            client.old_w = geom.width;
            client.old_h = geom.height;
            std.c.free(geom);
        }

        // Auto-float detection (Task 12)
        // Check WM_TRANSIENT_FOR
        const transient_cookie = c.xcb_get_property(
            self.conn,
            0,
            window,
            self.wm_transient_for,
            c.XCB_ATOM_WINDOW,
            0,
            1,
        );
        const transient_reply: ?*c.xcb_get_property_reply_t =
            c.xcb_get_property_reply(self.conn, transient_cookie, null);
        if (transient_reply) |tr| {
            defer std.c.free(@as(?*anyopaque, @ptrCast(tr)));
            if (c.xcb_get_property_value_length(tr) >= @as(c_int, @sizeOf(u32))) {
                client.is_floating = true;
                client.old_x = client.x;
                client.old_y = client.y;
                client.old_w = client.w;
                client.old_h = client.h;
            }
        }

        // Check WM_NORMAL_HINTS for fixed-size windows
        const hints_cookie = c.xcb_get_property(
            self.conn,
            0,
            window,
            self.wm_normal_hints,
            c.XCB_ATOM_ANY, // Accept any property type
            0,
            18, // XSizeHints has up to 18 longs
        );
        const hints_reply: ?*c.xcb_get_property_reply_t =
            c.xcb_get_property_reply(self.conn, hints_cookie, null);
        if (hints_reply) |hr| {
            defer std.c.free(@as(?*anyopaque, @ptrCast(hr)));
            const hints_len = c.xcb_get_property_value_length(hr);
            // Need at least flags + up to max_size fields (9 u32s minimum for PMinSize+PMaxSize)
            if (hints_len >= @as(c_int, 9 * @sizeOf(u32))) {
                const hints_data: ?[*]const u32 = @ptrCast(@alignCast(c.xcb_get_property_value(hr)));
                if (hints_data) |hd| {
                    const flags = hd[0];
                    // PMinSize = 1 << 4, PMaxSize = 1 << 5
                    const p_min_size: u32 = 1 << 4;
                    const p_max_size: u32 = 1 << 5;
                    if ((flags & p_min_size) != 0 and (flags & p_max_size) != 0) {
                        // min_width=hd[5], min_height=hd[6], max_width=hd[7], max_height=hd[8]
                        const min_w = hd[5];
                        const min_h = hd[6];
                        const max_w = hd[7];
                        const max_h = hd[8];
                        if (min_w == max_w and min_h == max_h and min_w > 0 and min_h > 0) {
                            client.is_floating = true;
                            client.w = @intCast(@min(min_w, 65535));
                            client.h = @intCast(@min(min_h, 65535));
                            client.old_x = client.x;
                            client.old_y = client.y;
                            client.old_w = client.w;
                            client.old_h = client.h;
                        }
                    }
                }
            }
        }

        self.sel_monitor.clients.append(client);

        // Set border width and unfocused color
        const border_values = [_]u32{config.border_px};
        _ = c.xcb_configure_window(
            self.conn,
            window,
            c.XCB_CONFIG_WINDOW_BORDER_WIDTH,
            &border_values,
        );
        const border_color_values = [_]u32{config.border_color};
        _ = c.xcb_change_window_attributes(
            self.conn,
            window,
            c.XCB_CW_BORDER_PIXEL,
            &border_color_values,
        );

        // Map the window
        _ = c.xcb_map_window(self.conn, window);

        // Subscribe to events on this window
        const event_values = [_]u32{
            c.XCB_EVENT_MASK_ENTER_WINDOW |
                c.XCB_EVENT_MASK_STRUCTURE_NOTIFY |
                c.XCB_EVENT_MASK_PROPERTY_CHANGE,
        };
        _ = c.xcb_change_window_attributes(
            self.conn,
            window,
            c.XCB_CW_EVENT_MASK,
            &event_values,
        );

        self.focused = client;
        self.arrange(self.sel_monitor);
        self.updateFocus();
        self.updateEwmh();
        _ = c.xcb_flush(self.conn);
    }

    pub fn unmanage(self: *Wm, window: xcb.Window) void {
        const client = self.findClient(window) orelse return;
        const mon = client.monitor;

        if (self.focused == client) {
            // Focus the next visible client, or prev, or null
            self.focused = self.nextVisible(client) orelse self.prevVisible(client);
        }

        mon.clients.remove(client);
        self.alloc.destroy(client);
        self.arrange(mon);
        self.updateFocus();
        self.updateEwmh();
        _ = c.xcb_flush(self.conn);
    }

    pub fn findClient(self: *Wm, window: xcb.Window) ?*Client {
        var mon = self.monitors;
        while (mon) |m| : (mon = m.next) {
            var it = m.clients.head;
            while (it) |client| : (it = client.next) {
                if (client.window == window) return client;
            }
        }
        return null;
    }

    pub fn arrange(self: *Wm, mon: *Monitor) void {
        // Map/unmap windows based on tag visibility
        var it = mon.clients.head;
        while (it) |client| : (it = client.next) {
            if ((client.tags & mon.selected_tags) != 0) {
                _ = c.xcb_map_window(self.conn, client.window);
            } else {
                _ = c.xcb_unmap_window(self.conn, client.window);
            }
        }

        const visible_count = mon.clients.countVisible(mon.selected_tags);
        if (visible_count == 0) return;

        var buf: [64]layout.Geometry = undefined;
        const mon_geom = layout.Geometry{
            .x = mon.x,
            .y = mon.y,
            .w = mon.w,
            .h = mon.h,
        };
        const geometries = layout.tile(
            visible_count,
            mon_geom,
            mon.master_count,
            mon.master_factor,
            config.gap_px,
            config.border_px,
            &buf,
        );

        // Apply geometries to visible, non-floating, non-fullscreen clients
        var ci: usize = 0;
        it = mon.clients.head;
        while (it) |client| : (it = client.next) {
            if ((client.tags & mon.selected_tags) != 0 and !client.is_floating and !client.is_fullscreen) {
                if (ci < geometries.len) {
                    const geom = geometries[ci];
                    client.x = geom.x;
                    client.y = geom.y;
                    client.w = geom.w;
                    client.h = geom.h;
                    self.applyGeometry(client);
                    ci += 1;
                }
            }
        }

        _ = c.xcb_flush(self.conn);
    }

    fn applyGeometry(self: *Wm, client: *const Client) void {
        const values = [_]u32{
            @bitCast(@as(i32, client.x)),
            @bitCast(@as(i32, client.y)),
            @as(u32, client.w),
            @as(u32, client.h),
        };
        _ = c.xcb_configure_window(
            self.conn,
            client.window,
            c.XCB_CONFIG_WINDOW_X |
                c.XCB_CONFIG_WINDOW_Y |
                c.XCB_CONFIG_WINDOW_WIDTH |
                c.XCB_CONFIG_WINDOW_HEIGHT,
            &values,
        );
    }

    pub fn updateFocus(self: *Wm) void {
        // Unfocus all clients across all monitors
        var mon = self.monitors;
        while (mon) |m| : (mon = m.next) {
            var it = m.clients.head;
            while (it) |client| : (it = client.next) {
                const border = [_]u32{config.border_color};
                _ = c.xcb_change_window_attributes(
                    self.conn,
                    client.window,
                    c.XCB_CW_BORDER_PIXEL,
                    &border,
                );
            }
        }

        if (self.focused) |client| {
            // Focus border color
            const border = [_]u32{config.border_focus_color};
            _ = c.xcb_change_window_attributes(
                self.conn,
                client.window,
                c.XCB_CW_BORDER_PIXEL,
                &border,
            );
            _ = c.xcb_set_input_focus(
                self.conn,
                c.XCB_INPUT_FOCUS_POINTER_ROOT,
                client.window,
                c.XCB_CURRENT_TIME,
            );

            // Update _NET_ACTIVE_WINDOW
            const win = [_]u32{client.window};
            _ = c.xcb_change_property(
                self.conn,
                c.XCB_PROP_MODE_REPLACE,
                self.screen.root,
                self.net_active_window,
                c.XCB_ATOM_WINDOW,
                32,
                1,
                &win,
            );
        } else {
            _ = c.xcb_set_input_focus(
                self.conn,
                c.XCB_INPUT_FOCUS_POINTER_ROOT,
                self.screen.root,
                c.XCB_CURRENT_TIME,
            );
            _ = c.xcb_delete_property(self.conn, self.screen.root, self.net_active_window);
        }
        _ = c.xcb_flush(self.conn);
    }

    pub fn updateEwmh(self: *Wm) void {
        // Update _NET_CURRENT_DESKTOP
        const tags = self.sel_monitor.selected_tags;
        var desktop: u32 = 0;
        var i: u4 = 0;
        while (i < 9) : (i += 1) {
            if ((tags & (@as(u9, 1) << i)) != 0) {
                desktop = i;
                break;
            }
        }
        _ = c.xcb_change_property(
            self.conn,
            c.XCB_PROP_MODE_REPLACE,
            self.screen.root,
            self.net_current_desktop,
            c.XCB_ATOM_CARDINAL,
            32,
            1,
            &desktop,
        );
        _ = c.xcb_flush(self.conn);
    }

    // Helper: find next visible client from a given client
    fn nextVisible(self: *Wm, from: *Client) ?*Client {
        const tags = from.monitor.selected_tags;
        var it = from.next;
        while (it) |client| : (it = client.next) {
            if ((client.tags & tags) != 0) return client;
        }
        // Wrap around from head
        it = from.monitor.clients.head;
        while (it) |client| : (it = client.next) {
            if (client == from) return null;
            if ((client.tags & tags) != 0) return client;
        }
        _ = self;
        return null;
    }

    fn prevVisible(self: *Wm, from: *Client) ?*Client {
        const tags = from.monitor.selected_tags;
        var it = from.prev;
        while (it) |client| : (it = client.prev) {
            if ((client.tags & tags) != 0) return client;
        }
        // Wrap around from tail
        it = from.monitor.clients.tail;
        while (it) |client| : (it = client.prev) {
            if (client == from) return null;
            if ((client.tags & tags) != 0) return client;
        }
        _ = self;
        return null;
    }

    pub fn firstVisibleClient(self: *Wm, mon: *Monitor) ?*Client {
        _ = self;
        var it = mon.clients.head;
        while (it) |client| : (it = client.next) {
            if ((client.tags & mon.selected_tags) != 0) return client;
        }
        return null;
    }

    // ===================== Key Grabbing (Task 7) =====================

    pub fn grabKeys(self: *Wm) void {
        // Ungrab all keys first
        _ = c.xcb_ungrab_key(self.conn, c.XCB_GRAB_ANY, self.screen.root, c.XCB_MOD_MASK_ANY);

        const syms = c.xcb_key_symbols_alloc(self.conn) orelse return;
        defer c.xcb_key_symbols_free(syms);

        for (config.keys) |key| {
            const keycodes: ?[*]xcb.Keycode = c.xcb_key_symbols_get_keycode(syms, key.keysym);
            if (keycodes) |kcs| {
                defer std.c.free(kcs);
                var i: usize = 0;
                while (kcs[i] != 0) : (i += 1) {
                    // Grab with and without NumLock/CapsLock
                    const modifiers = [_]u16{ 0, numlock_mask, capslock_mask, numlock_mask | capslock_mask };
                    for (modifiers) |extra| {
                        _ = c.xcb_grab_key(
                            self.conn,
                            1, // owner_events
                            self.screen.root,
                            key.mod | extra,
                            kcs[i],
                            c.XCB_GRAB_MODE_ASYNC,
                            c.XCB_GRAB_MODE_ASYNC,
                        );
                    }
                }
            }
        }
        _ = c.xcb_flush(self.conn);
    }

    pub fn handleKeyPress(self: *Wm, event: *c.xcb_key_press_event_t) void {
        const syms = c.xcb_key_symbols_alloc(self.conn) orelse return;
        defer c.xcb_key_symbols_free(syms);

        const keysym = c.xcb_key_symbols_get_keysym(syms, event.detail, 0);
        const clean_state = event.state & clean_mask;

        for (config.keys) |key| {
            if (keysym == key.keysym and clean_state == key.mod) {
                self.executeAction(key);
                return;
            }
        }
    }

    fn executeAction(self: *Wm, key: config.Key) void {
        switch (key.action) {
            .spawn => self.spawn(key.str_args),
            .focus_next => self.focusNext(),
            .focus_prev => self.focusPrev(),
            .adjust_master_factor => self.adjustMasterFactor(key.float_arg),
            .adjust_master_count => self.adjustMasterCount(key.int_arg),
            .zoom => self.zoomClient(),
            .kill_client => self.killClient(),
            .toggle_floating => self.toggleFloating(),
            .toggle_fullscreen => self.toggleFullscreen(),
            .view_tag => self.viewTag(key.int_arg),
            .tag_client => self.tagClient(key.int_arg),
            .focus_monitor => self.focusMonitor(key.int_arg),
            .send_to_monitor => self.sendToMonitor(key.int_arg),
            .quit => {
                self.running.* = false;
            },
        }
    }

    // ===================== Mouse Handling (Task 9) =====================

    pub fn grabButtons(self: *Wm) void {
        // Ungrab all buttons first
        _ = c.xcb_ungrab_button(self.conn, c.XCB_BUTTON_INDEX_ANY, self.screen.root, c.XCB_MOD_MASK_ANY);

        // Grab Mod+Button1 (move) and Mod+Button3 (resize) on root
        const modifiers = [_]u16{ 0, numlock_mask, capslock_mask, numlock_mask | capslock_mask };
        for (modifiers) |extra| {
            // Mod+Button1
            _ = c.xcb_grab_button(
                self.conn,
                0, // owner_events
                self.screen.root,
                c.XCB_EVENT_MASK_BUTTON_PRESS | c.XCB_EVENT_MASK_BUTTON_RELEASE | c.XCB_EVENT_MASK_POINTER_MOTION,
                c.XCB_GRAB_MODE_ASYNC,
                c.XCB_GRAB_MODE_ASYNC,
                c.XCB_NONE,
                c.XCB_NONE,
                1, // Button1
                config.mod_key | extra,
            );
            // Mod+Button3
            _ = c.xcb_grab_button(
                self.conn,
                0,
                self.screen.root,
                c.XCB_EVENT_MASK_BUTTON_PRESS | c.XCB_EVENT_MASK_BUTTON_RELEASE | c.XCB_EVENT_MASK_POINTER_MOTION,
                c.XCB_GRAB_MODE_ASYNC,
                c.XCB_GRAB_MODE_ASYNC,
                c.XCB_NONE,
                c.XCB_NONE,
                3, // Button3
                config.mod_key | extra,
            );
        }
        _ = c.xcb_flush(self.conn);
    }

    pub fn handleButtonPress(self: *Wm, event: *c.xcb_button_press_event_t) void {
        // Find client by the window the event occurred on
        const client = self.findClient(event.child) orelse return;

        // Focus the clicked client
        self.focused = client;
        self.sel_monitor = client.monitor;
        self.updateFocus();

        // Check if Mod is held for floating operations
        const clean_state = event.state & clean_mask;
        if ((clean_state & config.mod_key) == 0) return;

        // Only operate on floating windows
        if (!client.is_floating) return;

        if (event.detail == 1) {
            // Mod+Button1 = move
            self.grab_type = .move;
        } else if (event.detail == 3) {
            // Mod+Button3 = resize
            self.grab_type = .resize;
        } else {
            return;
        }

        self.grab_window = client;
        self.grab_start_x = event.root_x;
        self.grab_start_y = event.root_y;
        self.grab_client_x = client.x;
        self.grab_client_y = client.y;
        self.grab_client_w = client.w;
        self.grab_client_h = client.h;

        // Grab pointer for smooth dragging
        _ = c.xcb_grab_pointer(
            self.conn,
            0, // owner_events
            self.screen.root,
            c.XCB_EVENT_MASK_BUTTON_RELEASE | c.XCB_EVENT_MASK_POINTER_MOTION,
            c.XCB_GRAB_MODE_ASYNC,
            c.XCB_GRAB_MODE_ASYNC,
            c.XCB_NONE,
            c.XCB_NONE,
            c.XCB_CURRENT_TIME,
        );
        _ = c.xcb_flush(self.conn);
    }

    pub fn handleMotionNotify(self: *Wm, event: *c.xcb_motion_notify_event_t) void {
        const client = self.grab_window orelse return;
        if (self.grab_type == .none) return;

        const dx: i16 = event.root_x - self.grab_start_x;
        const dy: i16 = event.root_y - self.grab_start_y;

        switch (self.grab_type) {
            .move => {
                var new_x = self.grab_client_x + dx;
                var new_y = self.grab_client_y + dy;
                const mon = client.monitor;

                // Snap to edges
                if (@abs(new_x - mon.x) < config.snap_px) {
                    new_x = mon.x;
                } else if (@abs((new_x + @as(i16, @intCast(client.w))) - (mon.x + @as(i16, @intCast(mon.w)))) < config.snap_px) {
                    new_x = mon.x + @as(i16, @intCast(mon.w)) - @as(i16, @intCast(client.w));
                }
                if (@abs(new_y - mon.y) < config.snap_px) {
                    new_y = mon.y;
                } else if (@abs((new_y + @as(i16, @intCast(client.h))) - (mon.y + @as(i16, @intCast(mon.h)))) < config.snap_px) {
                    new_y = mon.y + @as(i16, @intCast(mon.h)) - @as(i16, @intCast(client.h));
                }

                client.x = new_x;
                client.y = new_y;
                self.applyGeometry(client);
            },
            .resize => {
                const new_w_raw: i32 = @as(i32, self.grab_client_w) + @as(i32, dx);
                const new_h_raw: i32 = @as(i32, self.grab_client_h) + @as(i32, dy);
                const new_w: u16 = if (new_w_raw < 100) 100 else @intCast(new_w_raw);
                const new_h: u16 = if (new_h_raw < 100) 100 else @intCast(new_h_raw);

                client.w = new_w;
                client.h = new_h;
                self.applyGeometry(client);
            },
            .none => {},
        }
        _ = c.xcb_flush(self.conn);
    }

    pub fn handleButtonRelease(self: *Wm) void {
        self.grab_type = .none;
        self.grab_window = null;
        _ = c.xcb_ungrab_pointer(self.conn, c.XCB_CURRENT_TIME);
        _ = c.xcb_flush(self.conn);
    }

    // ===================== Action Handlers =====================

    fn spawn(_: *Wm, cmd_str: ?[*:0]const u8) void {
        const cmd = cmd_str orelse return;

        const pid = std.c.fork();
        if (pid == 0) {
            // Child process — detach from WM's process group
            _ = std.c.setsid();

            const sh_argv = [_:null]?[*:0]const u8{
                "/bin/sh",
                "-c",
                cmd,
            };
            _ = std.c.execve("/bin/sh", &sh_argv, std.c.environ);
            std.c._exit(1);
        }
    }

    fn focusNext(self: *Wm) void {
        const client = self.focused orelse return;
        const next = self.nextVisible(client) orelse return;
        self.focused = next;
        self.updateFocus();
    }

    fn focusPrev(self: *Wm) void {
        const client = self.focused orelse return;
        const prev_c = self.prevVisible(client) orelse return;
        self.focused = prev_c;
        self.updateFocus();
    }

    fn adjustMasterFactor(self: *Wm, delta: f32) void {
        const mon = self.sel_monitor;
        const new_factor = mon.master_factor + delta;
        if (new_factor < 0.1 or new_factor > 0.9) return;
        mon.master_factor = new_factor;
        self.arrange(mon);
    }

    fn adjustMasterCount(self: *Wm, delta: i8) void {
        const mon = self.sel_monitor;
        const new_count: i16 = @as(i16, mon.master_count) + @as(i16, delta);
        if (new_count < 1 or new_count > 10) return;
        mon.master_count = @intCast(@as(u16, @intCast(new_count)));
        self.arrange(mon);
    }

    fn zoomClient(self: *Wm) void {
        const client = self.focused orelse return;
        const mon = client.monitor;

        // If already head, swap with next visible
        if (mon.clients.head == client) {
            const next = self.nextVisible(client) orelse return;
            self.focused = next;
            // Move next to head
            mon.clients.remove(next);
            mon.clients.insertHead(next);
        } else {
            // Move focused to head
            mon.clients.remove(client);
            mon.clients.insertHead(client);
        }
        self.arrange(mon);
        self.updateFocus();
    }

    fn killClient(self: *Wm) void {
        const client = self.focused orelse return;

        if (self.supportsProtocol(client.window, self.wm_delete_window)) {
            // Send WM_DELETE_WINDOW client message
            var ev: c.xcb_client_message_event_t = std.mem.zeroes(c.xcb_client_message_event_t);
            ev.response_type = c.XCB_CLIENT_MESSAGE;
            ev.window = client.window;
            ev.type = self.wm_protocols;
            ev.format = 32;
            ev.data.data32[0] = self.wm_delete_window;
            ev.data.data32[1] = c.XCB_CURRENT_TIME;

            _ = c.xcb_send_event(
                self.conn,
                0,
                client.window,
                c.XCB_EVENT_MASK_NO_EVENT,
                @ptrCast(&ev),
            );
        } else {
            _ = c.xcb_kill_client(self.conn, client.window);
        }
        _ = c.xcb_flush(self.conn);
    }

    fn supportsProtocol(self: *Wm, window: xcb.Window, proto: xcb.Atom) bool {
        const cookie = c.xcb_get_property(
            self.conn,
            0,
            window,
            self.wm_protocols,
            c.XCB_ATOM_ATOM,
            0,
            64,
        );
        const reply: ?*c.xcb_get_property_reply_t = c.xcb_get_property_reply(self.conn, cookie, null);
        if (reply) |r| {
            defer std.c.free(r);
            const atoms_ptr: ?[*]const xcb.Atom = @ptrCast(@alignCast(c.xcb_get_property_value(r)));
            if (atoms_ptr) |atoms| {
                const len = @divTrunc(c.xcb_get_property_value_length(r), @as(c_int, @sizeOf(xcb.Atom)));
                const count: usize = if (len > 0) @intCast(len) else 0;
                for (0..count) |i| {
                    if (atoms[i] == proto) return true;
                }
            }
        }
        return false;
    }

    fn toggleFloating(self: *Wm) void {
        const client = self.focused orelse return;
        client.is_floating = !client.is_floating;
        if (client.is_floating) {
            // Restore old geometry
            client.x = client.old_x;
            client.y = client.old_y;
            client.w = client.old_w;
            client.h = client.old_h;
            self.applyGeometry(client);
            // Raise floating window
            const stack_values = [_]u32{c.XCB_STACK_MODE_ABOVE};
            _ = c.xcb_configure_window(
                self.conn,
                client.window,
                c.XCB_CONFIG_WINDOW_STACK_MODE,
                &stack_values,
            );
        }
        self.arrange(client.monitor);
    }

    fn toggleFullscreen(self: *Wm) void {
        const client = self.focused orelse return;
        client.is_fullscreen = !client.is_fullscreen;
        const mon = client.monitor;

        if (client.is_fullscreen) {
            // Save current geometry
            client.old_x = client.x;
            client.old_y = client.y;
            client.old_w = client.w;
            client.old_h = client.h;

            // Set fullscreen geometry (monitor bounds, no border)
            client.x = mon.x;
            client.y = mon.y;
            client.w = mon.w;
            client.h = mon.h;

            const border_values = [_]u32{0};
            _ = c.xcb_configure_window(
                self.conn,
                client.window,
                c.XCB_CONFIG_WINDOW_BORDER_WIDTH,
                &border_values,
            );
            self.applyGeometry(client);

            // Raise
            const stack_values = [_]u32{c.XCB_STACK_MODE_ABOVE};
            _ = c.xcb_configure_window(
                self.conn,
                client.window,
                c.XCB_CONFIG_WINDOW_STACK_MODE,
                &stack_values,
            );

            // Set EWMH fullscreen state
            const fs_atom = [_]u32{self.net_wm_state_fullscreen};
            _ = c.xcb_change_property(
                self.conn,
                c.XCB_PROP_MODE_REPLACE,
                client.window,
                self.net_wm_state,
                c.XCB_ATOM_ATOM,
                32,
                1,
                &fs_atom,
            );
        } else {
            // Restore border
            const border_values = [_]u32{config.border_px};
            _ = c.xcb_configure_window(
                self.conn,
                client.window,
                c.XCB_CONFIG_WINDOW_BORDER_WIDTH,
                &border_values,
            );

            // Clear EWMH fullscreen state
            _ = c.xcb_change_property(
                self.conn,
                c.XCB_PROP_MODE_REPLACE,
                client.window,
                self.net_wm_state,
                c.XCB_ATOM_ATOM,
                32,
                0,
                null,
            );

            self.arrange(mon);
        }
        _ = c.xcb_flush(self.conn);
    }

    fn viewTag(self: *Wm, index: i8) void {
        if (index < 0 or index > 8) return;
        const tag_mask: u9 = @as(u9, 1) << @intCast(index);
        const mon = self.sel_monitor;
        if (mon.selected_tags == tag_mask) return;

        mon.selected_tags = tag_mask;
        self.arrange(mon);
        self.focused = self.firstVisibleClient(mon);
        self.updateFocus();
        self.updateEwmh();
    }

    fn tagClient(self: *Wm, index: i8) void {
        if (index < 0 or index > 8) return;
        const client = self.focused orelse return;
        const tag_mask: u9 = @as(u9, 1) << @intCast(index);
        client.tags = tag_mask;

        const mon = client.monitor;
        // If client is no longer visible, unmap and refocus
        if ((client.tags & mon.selected_tags) == 0) {
            _ = c.xcb_unmap_window(self.conn, client.window);
            self.focused = self.firstVisibleClient(mon);
        }
        self.arrange(mon);
        self.updateFocus();
    }

    // ===================== Scan Existing + EWMH + Struts (Task 11) =====================

    /// Scan existing windows on root and manage them.
    pub fn scanExisting(self: *Wm) void {
        const cookie = c.xcb_query_tree(self.conn, self.screen.root);
        const reply: ?*c.xcb_query_tree_reply_t = c.xcb_query_tree_reply(self.conn, cookie, null);
        if (reply) |r| {
            defer std.c.free(@as(?*anyopaque, @ptrCast(r)));

            const num_children = c.xcb_query_tree_children_length(r);
            if (num_children <= 0) return;
            const children: [*]xcb.Window = c.xcb_query_tree_children(r);
            const count: usize = @intCast(num_children);

            for (0..count) |i| {
                const win = children[i];

                // Get window attributes to check override_redirect and map_state
                const attr_cookie = c.xcb_get_window_attributes(self.conn, win);
                const attr_reply: ?*c.xcb_get_window_attributes_reply_t =
                    c.xcb_get_window_attributes_reply(self.conn, attr_cookie, null);

                if (attr_reply) |attr| {
                    defer std.c.free(@as(?*anyopaque, @ptrCast(attr)));

                    if (attr.override_redirect != 0) {
                        // Check struts on override_redirect windows (bars)
                        self.applyStrut(win);
                        continue;
                    }

                    // Skip unmapped windows
                    if (attr.map_state != c.XCB_MAP_STATE_VIEWABLE) continue;

                    // Manage this window
                    self.manage(win);
                }
            }
        }
    }

    /// Read _NET_WM_STRUT_PARTIAL and adjust monitor geometry for bars.
    pub fn applyStrut(self: *Wm, window: xcb.Window) void {
        const cookie = c.xcb_get_property(
            self.conn,
            0,
            window,
            self.net_wm_strut_partial,
            c.XCB_ATOM_CARDINAL,
            0,
            12, // 12 u32 values in _NET_WM_STRUT_PARTIAL
        );
        const reply: ?*c.xcb_get_property_reply_t = c.xcb_get_property_reply(self.conn, cookie, null);
        if (reply) |r| {
            defer std.c.free(@as(?*anyopaque, @ptrCast(r)));

            const len = c.xcb_get_property_value_length(r);
            // _NET_WM_STRUT_PARTIAL has 12 values, _NET_WM_STRUT has 4
            if (len < @as(c_int, 4 * @sizeOf(u32))) return;

            const strut_ptr: ?[*]const u32 = @ptrCast(@alignCast(c.xcb_get_property_value(r)));
            if (strut_ptr) |strut| {
                // strut[0] = left, [1] = right, [2] = top, [3] = bottom
                const top = strut[2];
                const bottom = strut[3];

                // Adjust all monitors (simplified: apply to all)
                var mon = self.monitors;
                while (mon) |m| : (mon = m.next) {
                    if (top > 0) {
                        const top16: u16 = @intCast(@min(top, m.h));
                        if (m.y < @as(i16, @intCast(top16))) {
                            const adjust: u16 = @intCast(@as(i16, @intCast(top16)) - m.y);
                            m.y = @intCast(top16);
                            m.h -|= adjust;
                        }
                    }
                    if (bottom > 0) {
                        const bottom16: u16 = @intCast(@min(bottom, m.h));
                        m.h -|= bottom16;
                    }
                }
            }
        }
    }

    /// Handle property changes (strut updates).
    pub fn handlePropertyNotify(self: *Wm, event: *c.xcb_property_notify_event_t) void {
        if (event.atom == self.net_wm_strut_partial) {
            // Re-apply struts: reset monitor geometry and re-scan
            self.updateMonitors();
            // Re-apply struts from all override_redirect windows
            const cookie = c.xcb_query_tree(self.conn, self.screen.root);
            const reply: ?*c.xcb_query_tree_reply_t = c.xcb_query_tree_reply(self.conn, cookie, null);
            if (reply) |r| {
                defer std.c.free(@as(?*anyopaque, @ptrCast(r)));
                const num_children = c.xcb_query_tree_children_length(r);
                if (num_children <= 0) return;
                const children: [*]xcb.Window = c.xcb_query_tree_children(r);
                const count: usize = @intCast(num_children);
                for (0..count) |i| {
                    const attr_cookie = c.xcb_get_window_attributes(self.conn, children[i]);
                    const attr_reply: ?*c.xcb_get_window_attributes_reply_t =
                        c.xcb_get_window_attributes_reply(self.conn, attr_cookie, null);
                    if (attr_reply) |attr| {
                        defer std.c.free(@as(?*anyopaque, @ptrCast(attr)));
                        if (attr.override_redirect != 0) {
                            self.applyStrut(children[i]);
                        }
                    }
                }
            }
            // Re-arrange all monitors with new geometry
            var m = self.monitors;
            while (m) |mon| : (m = mon.next) {
                self.arrange(mon);
            }
        }
    }

    /// Handle RandR screen change: re-detect monitors and re-arrange.
    pub fn handleScreenChange(self: *Wm) void {
        self.updateMonitors();
    }

    // ===================== Sloppy Focus + ConfigureRequest (Task 10) =====================

    pub fn handleEnterNotify(self: *Wm, event: *c.xcb_enter_notify_event_t) void {
        // Skip during mouse grab
        if (self.grab_type != .none) return;

        // Skip non-NORMAL mode (e.g., grab/ungrab notifications)
        if (event.mode != c.XCB_NOTIFY_MODE_NORMAL) return;

        const client = self.findClient(event.event) orelse return;

        // Set focus and sel_monitor
        self.focused = client;
        self.sel_monitor = client.monitor;
        self.updateFocus();
    }

    pub fn handleConfigureRequest(self: *Wm, event: *c.xcb_configure_request_event_t) void {
        const mask = event.value_mask;

        if (self.findClient(event.window)) |client| {
            if (client.is_floating) {
                // Floating managed window: honor the request
                if ((mask & c.XCB_CONFIG_WINDOW_X) != 0) {
                    client.x = event.x;
                }
                if ((mask & c.XCB_CONFIG_WINDOW_Y) != 0) {
                    client.y = event.y;
                }
                if ((mask & c.XCB_CONFIG_WINDOW_WIDTH) != 0) {
                    client.w = event.width;
                }
                if ((mask & c.XCB_CONFIG_WINDOW_HEIGHT) != 0) {
                    client.h = event.height;
                }
                self.applyGeometry(client);
                _ = c.xcb_flush(self.conn);
            } else {
                // Tiled managed window: send current geometry back
                self.sendConfigureNotify(client);
            }
        } else {
            // Unmanaged window: forward request directly
            var i: usize = 0;
            var values: [7]u32 = undefined;
            if ((mask & c.XCB_CONFIG_WINDOW_X) != 0) {
                values[i] = @bitCast(@as(i32, event.x));
                i += 1;
            }
            if ((mask & c.XCB_CONFIG_WINDOW_Y) != 0) {
                values[i] = @bitCast(@as(i32, event.y));
                i += 1;
            }
            if ((mask & c.XCB_CONFIG_WINDOW_WIDTH) != 0) {
                values[i] = @as(u32, event.width);
                i += 1;
            }
            if ((mask & c.XCB_CONFIG_WINDOW_HEIGHT) != 0) {
                values[i] = @as(u32, event.height);
                i += 1;
            }
            if ((mask & c.XCB_CONFIG_WINDOW_BORDER_WIDTH) != 0) {
                values[i] = @as(u32, event.border_width);
                i += 1;
            }
            if ((mask & c.XCB_CONFIG_WINDOW_SIBLING) != 0) {
                values[i] = event.sibling;
                i += 1;
            }
            if ((mask & c.XCB_CONFIG_WINDOW_STACK_MODE) != 0) {
                values[i] = event.stack_mode;
                i += 1;
            }
            _ = c.xcb_configure_window(self.conn, event.window, mask, &values);
            _ = c.xcb_flush(self.conn);
        }
    }

    fn sendConfigureNotify(self: *Wm, client: *const Client) void {
        var ev: c.xcb_configure_notify_event_t = std.mem.zeroes(c.xcb_configure_notify_event_t);
        ev.response_type = c.XCB_CONFIGURE_NOTIFY;
        ev.event = client.window;
        ev.window = client.window;
        ev.x = client.x;
        ev.y = client.y;
        ev.width = client.w;
        ev.height = client.h;
        ev.border_width = config.border_px;
        ev.above_sibling = c.XCB_NONE;
        ev.override_redirect = 0;

        _ = c.xcb_send_event(
            self.conn,
            0,
            client.window,
            c.XCB_EVENT_MASK_STRUCTURE_NOTIFY,
            @ptrCast(&ev),
        );
        _ = c.xcb_flush(self.conn);
    }

    // ===================== Multi-Monitor (Task 8) =====================

    /// Return the last monitor in the linked list.
    pub fn lastMonitor(self: *Wm) ?*Monitor {
        var mon = self.monitors;
        while (mon) |m| {
            if (m.next == null) return m;
            mon = m.next;
        }
        return null;
    }

    /// Return adjacent monitor in the given direction (wrapping).
    /// dir > 0 => next, dir < 0 => prev.
    pub fn adjacentMonitor(self: *Wm, mon: *Monitor, dir: i8) ?*Monitor {
        if (dir > 0) {
            // Next, wrapping to first
            return mon.next orelse self.monitors;
        } else if (dir < 0) {
            // Prev, wrapping to last
            return mon.prev orelse self.lastMonitor();
        }
        return null;
    }

    fn focusMonitor(self: *Wm, dir: i8) void {
        const target = self.adjacentMonitor(self.sel_monitor, dir) orelse return;
        if (target == self.sel_monitor) return;

        self.sel_monitor = target;
        self.focused = self.firstVisibleClient(target);
        self.updateFocus();
        self.updateEwmh();
    }

    fn sendToMonitor(self: *Wm, dir: i8) void {
        const client = self.focused orelse return;
        const target = self.adjacentMonitor(self.sel_monitor, dir) orelse return;
        if (target == self.sel_monitor) return;

        const src = client.monitor;

        // Remove from source monitor
        src.clients.remove(client);

        // Update focus on source monitor before moving
        if (self.focused == client) {
            self.focused = self.firstVisibleClient(src);
        }

        // Add to target monitor
        client.monitor = target;
        client.tags = target.selected_tags;
        target.clients.append(client);

        // Re-arrange both monitors
        self.arrange(src);
        self.arrange(target);
        self.updateFocus();
        self.updateEwmh();
    }

    /// Re-detect monitors from XRandR and rebuild monitor list.
    pub fn updateMonitors(self: *Wm) void {
        var info_buf: [16]monitor_mod.MonitorInfo = undefined;
        const infos = monitor_mod.detectMonitors(self.conn, self.screen, &info_buf);

        // Update existing monitors or create new ones
        // Simple approach: walk both lists in parallel
        var prev_mon: ?*Monitor = null;
        var cur_mon = self.monitors;
        for (infos) |info| {
            if (cur_mon) |m| {
                // Update existing monitor geometry
                m.x = info.x;
                m.y = info.y;
                m.w = info.w;
                m.h = info.h;
                prev_mon = m;
                cur_mon = m.next;
            } else {
                // Create new monitor
                const new_mon = self.alloc.create(Monitor) catch continue;
                new_mon.* = .{
                    .x = info.x,
                    .y = info.y,
                    .w = info.w,
                    .h = info.h,
                };
                new_mon.prev = prev_mon;
                if (prev_mon) |pm| {
                    pm.next = new_mon;
                } else {
                    self.monitors = new_mon;
                }
                prev_mon = new_mon;
                cur_mon = null;
            }
        }

        // Remove excess monitors (move their clients to last valid monitor)
        if (cur_mon) |extra_start| {
            const last_valid = prev_mon orelse return;
            var extra = extra_start;
            while (true) {
                // Move all clients to last valid monitor
                var cl = extra.clients.head;
                while (cl) |client| {
                    const next_cl = client.next;
                    extra.clients.remove(client);
                    client.monitor = last_valid;
                    last_valid.clients.append(client);
                    cl = next_cl;
                }
                const next_extra = extra.next;
                if (self.sel_monitor == extra) {
                    self.sel_monitor = last_valid;
                }
                self.alloc.destroy(extra);
                if (next_extra) |ne| {
                    extra = ne;
                } else break;
            }
            if (prev_mon) |pm| {
                pm.next = null;
            }
        }

        // Re-arrange all monitors
        var m = self.monitors;
        while (m) |mon| : (m = mon.next) {
            self.arrange(mon);
        }
    }
};

// ===================== Constants =====================

const numlock_mask: u16 = 1 << 4; // Mod2
const capslock_mask: u16 = 1 << 1; // Lock
const clean_mask: u16 = 0xff & ~numlock_mask & ~capslock_mask;
