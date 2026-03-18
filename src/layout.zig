const std = @import("std");

pub const Geometry = struct {
    x: i16,
    y: i16,
    w: u16,
    h: u16,
};

/// Compute master+stack tiling positions.
///
/// - 0 clients: returns empty slice
/// - 1 client: fills entire monitor (no gap, no border)
/// - 2+ clients: master area on left, stack on right
///
/// `buf` must have at least `client_count` elements.
pub fn tile(
    client_count: u32,
    mon: Geometry,
    master_count: u8,
    master_factor: f32,
    gap: u16,
    border: u16,
    buf: []Geometry,
) []Geometry {
    if (client_count == 0) return buf[0..0];

    const n: u32 = @min(client_count, @as(u32, @intCast(buf.len)));

    // Single client fills entire monitor
    if (n == 1) {
        buf[0] = .{
            .x = mon.x,
            .y = mon.y,
            .w = mon.w,
            .h = mon.h,
        };
        return buf[0..1];
    }

    const total_border: u16 = border * 2;
    const mc: u32 = @min(@as(u32, master_count), n);
    const sc: u32 = n -| mc; // stack count

    // Master area width
    const master_w: u16 = if (sc == 0)
        mon.w
    else
        @intFromFloat(@as(f32, @floatFromInt(mon.w -| gap)) * master_factor);

    // Stack area width
    const stack_w: u16 = if (sc == 0) 0 else (mon.w -| master_w -| gap);

    // Place master windows
    if (mc > 0) {
        const base_h: u16 = (mon.h -| (gap *| @as(u16, @intCast(mc -| 1)))) / @as(u16, @intCast(mc));
        for (0..mc) |i| {
            const idx: u16 = @intCast(i);
            buf[i] = .{
                .x = @intCast(@as(i32, mon.x) + @as(i32, gap)),
                .y = @intCast(@as(i32, mon.y) + @as(i32, gap) + @as(i32, idx) * (@as(i32, base_h) + @as(i32, gap))),
                .w = master_w -| total_border -| gap,
                .h = base_h -| total_border,
            };
        }
    }

    // Place stack windows
    if (sc > 0) {
        const sc16: u16 = @intCast(sc);
        const base_h: u16 = (mon.h -| (gap *| (sc16 -| 1))) / sc16;
        const stack_x: i16 = @intCast(@as(i32, mon.x) + @as(i32, master_w) + @as(i32, gap));
        for (0..sc) |i| {
            const idx: u16 = @intCast(i);
            buf[mc + i] = .{
                .x = stack_x,
                .y = @intCast(@as(i32, mon.y) + @as(i32, gap) + @as(i32, idx) * (@as(i32, base_h) + @as(i32, gap))),
                .w = stack_w -| total_border -| gap,
                .h = base_h -| total_border,
            };
        }
    }

    return buf[0..n];
}

// ===================== TESTS =====================

test "zero clients returns empty" {
    var buf: [4]Geometry = undefined;
    const mon = Geometry{ .x = 0, .y = 0, .w = 1000, .h = 800 };
    const result = tile(0, mon, 1, 0.5, 0, 0, &buf);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "single client fills entire monitor" {
    var buf: [4]Geometry = undefined;
    const mon = Geometry{ .x = 0, .y = 0, .w = 720, .h = 720 };
    const result = tile(1, mon, 1, 0.55, 0, 0, &buf);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(Geometry{ .x = 0, .y = 0, .w = 720, .h = 720 }, result[0]);
}

test "two clients: master left, stack right" {
    var buf: [4]Geometry = undefined;
    const mon = Geometry{ .x = 0, .y = 0, .w = 1000, .h = 800 };
    const result = tile(2, mon, 1, 0.5, 0, 0, &buf);
    try std.testing.expectEqual(@as(usize, 2), result.len);

    // Master: left half
    try std.testing.expectEqual(@as(i16, 0), result[0].x);
    try std.testing.expectEqual(@as(u16, 500), result[0].w);
    try std.testing.expectEqual(@as(u16, 800), result[0].h);

    // Stack: right half
    try std.testing.expectEqual(@as(i16, 500), result[1].x);
    try std.testing.expectEqual(@as(u16, 500), result[1].w);
    try std.testing.expectEqual(@as(u16, 800), result[1].h);
}

test "four clients: 1 master + 3 stack" {
    var buf: [4]Geometry = undefined;
    const mon = Geometry{ .x = 0, .y = 0, .w = 1000, .h = 900 };
    const result = tile(4, mon, 1, 0.5, 0, 0, &buf);
    try std.testing.expectEqual(@as(usize, 4), result.len);

    // Master takes full height
    try std.testing.expectEqual(@as(u16, 500), result[0].w);
    try std.testing.expectEqual(@as(u16, 900), result[0].h);

    // 3 stack windows each get 300px height
    try std.testing.expectEqual(@as(u16, 300), result[1].h);
    try std.testing.expectEqual(@as(u16, 300), result[2].h);
    try std.testing.expectEqual(@as(u16, 300), result[3].h);
    try std.testing.expectEqual(@as(i16, 500), result[1].x);
}

test "two clients with gap and border" {
    var buf: [4]Geometry = undefined;
    const mon = Geometry{ .x = 0, .y = 0, .w = 1000, .h = 800 };
    const result = tile(2, mon, 1, 0.5, 10, 2, &buf);
    try std.testing.expectEqual(@as(usize, 2), result.len);

    // With gap=10, border=2 (total_border=4):
    // master_w = (1000-10)*0.5 = 495
    // Master: x=gap=10, w=495-4-10=481, h=800-4=796
    const master = result[0];
    try std.testing.expectEqual(@as(i16, 10), master.x);
    try std.testing.expectEqual(@as(i16, 10), master.y);
    try std.testing.expectEqual(@as(u16, 481), master.w);
    try std.testing.expectEqual(@as(u16, 796), master.h);

    // Stack: x=495+10=505, w=(1000-495-10)-4-10=481, h=800-4=796
    const stack = result[1];
    try std.testing.expectEqual(@as(i16, 505), stack.x);
    try std.testing.expectEqual(@as(i16, 10), stack.y);
    try std.testing.expectEqual(@as(u16, 481), stack.w);
    try std.testing.expectEqual(@as(u16, 796), stack.h);
}
