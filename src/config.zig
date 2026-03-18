const std = @import("std");

// ===================== X11 Keysyms =====================

pub const XK = struct {
    pub const Return: u32 = 0xff0d;
    pub const Tab: u32 = 0xff09;
    pub const space: u32 = 0x0020;
    pub const q: u32 = 0x0071;
    pub const j: u32 = 0x006a;
    pub const k: u32 = 0x006b;
    pub const h: u32 = 0x0068;
    pub const l: u32 = 0x006c;
    pub const i: u32 = 0x0069;
    pub const d: u32 = 0x0064;
    pub const p: u32 = 0x0070;
    pub const c: u32 = 0x0063;
    pub const t: u32 = 0x0074;
    pub const f: u32 = 0x0066;
    pub const m: u32 = 0x006d;
    pub const comma: u32 = 0x002c;
    pub const period: u32 = 0x002e;
    pub const @"1": u32 = 0x0031;
    pub const @"2": u32 = 0x0032;
    pub const @"3": u32 = 0x0033;
    pub const @"4": u32 = 0x0034;
    pub const @"5": u32 = 0x0035;
    pub const @"6": u32 = 0x0036;
    pub const @"7": u32 = 0x0037;
    pub const @"8": u32 = 0x0038;
    pub const @"9": u32 = 0x0039;
};

/// Return the keysym for number key "1" through "9" (0-indexed: 0 -> "1", 8 -> "9")
pub fn numKeysym(n: u4) u32 {
    return @as(u32, 0x0031) + @as(u32, n);
}

// ===================== Modifier Enum =====================

pub const Modifier = enum(u16) {
    mod1 = 1 << 3, // Alt
    mod4 = 1 << 6, // Super

    pub fn toMask(self: Modifier) u16 {
        return @intFromEnum(self);
    }
};

pub const shift_mask: u16 = 1 << 0;

// ===================== Action Enum =====================

pub const Action = enum {
    spawn,
    focus_next,
    focus_prev,
    adjust_master_factor,
    adjust_master_count,
    zoom,
    kill_client,
    toggle_floating,
    toggle_fullscreen,
    focus_monitor,
    send_to_monitor,
    view_tag,
    tag_client,
    quit,
};

// ===================== Key Binding =====================

pub const Key = struct {
    mod: u16,
    keysym: u32,
    action: Action,
    int_arg: i8 = 0,
    float_arg: f32 = 0.0,
    str_args: ?[*:0]const u8 = null,
};

// ===================== Configuration Constants =====================

pub const mod_key: u16 = Modifier.mod4.toMask();
pub const mod_shift: u16 = mod_key | shift_mask;

pub const master_factor: f32 = 0.55;
pub const gap_px: u16 = 0;
pub const border_px: u16 = 1;
pub const border_color: u32 = 0x444444;
pub const border_focus_color: u32 = 0xBBBBBB;
pub const snap_px: u16 = 16;

// ===================== Key Bindings =====================

fn tagKeys() [9 * 2]Key {
    var result: [9 * 2]Key = undefined;
    for (0..9) |tag_i| {
        const tag: i8 = @intCast(tag_i);
        // Mod+N → view_tag
        result[tag_i * 2] = .{
            .mod = mod_key,
            .keysym = numKeysym(@intCast(tag_i)),
            .action = .view_tag,
            .int_arg = tag,
        };
        // Mod+Shift+N → tag_client
        result[tag_i * 2 + 1] = .{
            .mod = mod_shift,
            .keysym = numKeysym(@intCast(tag_i)),
            .action = .tag_client,
            .int_arg = tag,
        };
    }
    return result;
}

const base_keys = [_]Key{
    // Launch terminal
    .{ .mod = mod_key, .keysym = XK.Return, .action = .spawn, .str_args = "st" },
    // Launch dmenu/rofi
    .{ .mod = mod_key, .keysym = XK.p, .action = .spawn, .str_args = "rofi -show drun" },

    // Focus navigation
    .{ .mod = mod_key, .keysym = XK.j, .action = .focus_next },
    .{ .mod = mod_key, .keysym = XK.k, .action = .focus_prev },

    // Master factor
    .{ .mod = mod_key, .keysym = XK.h, .action = .adjust_master_factor, .float_arg = -0.05 },
    .{ .mod = mod_key, .keysym = XK.l, .action = .adjust_master_factor, .float_arg = 0.05 },

    // Master count
    .{ .mod = mod_key, .keysym = XK.i, .action = .adjust_master_count, .int_arg = 1 },
    .{ .mod = mod_key, .keysym = XK.d, .action = .adjust_master_count, .int_arg = -1 },

    // Zoom (swap with master)
    .{ .mod = mod_key, .keysym = XK.space, .action = .zoom },

    // Kill client
    .{ .mod = mod_shift, .keysym = XK.c, .action = .kill_client },

    // Toggle floating
    .{ .mod = mod_shift, .keysym = XK.space, .action = .toggle_floating },

    // Toggle fullscreen
    .{ .mod = mod_key, .keysym = XK.f, .action = .toggle_fullscreen },

    // Monitor focus
    .{ .mod = mod_key, .keysym = XK.comma, .action = .focus_monitor, .int_arg = -1 },
    .{ .mod = mod_key, .keysym = XK.period, .action = .focus_monitor, .int_arg = 1 },

    // Send to monitor
    .{ .mod = mod_shift, .keysym = XK.comma, .action = .send_to_monitor, .int_arg = -1 },
    .{ .mod = mod_shift, .keysym = XK.period, .action = .send_to_monitor, .int_arg = 1 },

    // Quit
    .{ .mod = mod_shift, .keysym = XK.q, .action = .quit },
};

const tag_keys_array = tagKeys();

pub const keys: []const Key = &(base_keys ++ tag_keys_array);

// ===================== Comptime Validation =====================

comptime {
    if (master_factor <= 0.05 or master_factor >= 0.95) {
        @compileError("master_factor must be between 0.05 and 0.95");
    }
    if (keys.len == 0) {
        @compileError("keys array must not be empty");
    }
}
