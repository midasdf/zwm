# zwm

> **Work in progress.** Core functionality is implemented but not yet battle-tested. Expect rough edges.

A window manager that gets out of your way.

37KB of Zig. No Xlib. No bar. No opinions. Just windows on a screen, exactly where you put them.

Built for a [HackberryPi Zero](https://github.com/ZitaoTech/Hackberry-Pi_Zero) — a 720x720 screen, 4GB of RAM, and a keyboard that fits in your palm. If it runs there, it runs anywhere.

## Why

Most window managers carry the weight of features you'll never touch. zwm carries nothing. One layout. Nine tags. A border that changes color when you look at it. That's the whole thing.

The configuration lives in Zig source. Change a constant, rebuild in under a second. No parser, no runtime, no surprises. The compiler catches your mistakes before the window manager ever runs.

## What you get

- **xcb direct** — talks to the X server without Xlib in between
- **Master+stack** — one window leads, the rest follow
- **9 tags** — bitmask, not workspaces. A window can live in two places at once
- **Multi-monitor** — XRandR. Plug in a screen, it appears
- **Floating** — dialogs know what they are. Mod+drag for everything else
- **EWMH** — your status bar still works

## Build

```sh
git clone https://github.com/midasdf/zwm.git
cd zwm
zig build
```

That's it. For the smallest possible binary:

```sh
zig build -Doptimize=ReleaseSmall   # → 37KB
```

### Dependencies

Zig 0.15+ and three libraries the X server already has:

```sh
# Arch
sudo pacman -S zig libxcb xcb-util-keysyms xcb-util-renderutil

# Debian/Ubuntu
sudo apt install zig libxcb1-dev libxcb-keysyms1-dev libxcb-randr0-dev
```

## Install

```sh
sudo cp zig-out/bin/zwm /usr/local/bin/
```

```sh
# ~/.xinitrc
exec zwm
```

## Keys

Everything is `Mod` (Super) plus something.

| Key | What it does |
|-----|-------------|
| `Return` | Open a terminal |
| `p` | Open rofi |
| `j` / `k` | Focus next / previous |
| `h` / `l` | Shrink / grow master |
| `Space` | Swap with master |
| `Shift+Space` | Float / unfloat |
| `f` | Fullscreen |
| `Shift+c` | Close window |
| `i` / `d` | More / fewer masters |
| `1`–`9` | View tag |
| `Shift+1`–`9` | Send to tag |
| `,` / `.` | Previous / next monitor |
| `Shift+,` / `.` | Send to monitor |
| `Shift+q` | Quit |

Floating windows: `Mod+Button1` to move, `Mod+Button3` to resize.

## Configure

There is no config file. There is `src/config.zig`:

```zig
pub const master_factor: f32 = 0.55;
pub const gap_px: u16 = 0;
pub const border_px: u16 = 1;
pub const border_color: u32 = 0x444444;
pub const border_focus_color: u32 = 0xBBBBBB;
```

Change it. Rebuild. The compiler will tell you if you did something wrong.

## Develop

Test without touching your running session:

```sh
Xephyr -br -ac -noreset -screen 720x720 :1 &
DISPLAY=:1 zig-out/bin/zwm
```

Run the test suite:

```sh
zig build test
```

## Inside

```
src/
├── main.zig       where it starts and where it loops
├── wm.zig         where windows live and die
├── xcb.zig        the thin line between Zig and X11
├── layout.zig     pure math, no side effects
├── monitor.zig    screens come and go
└── config.zig     the only file you should edit
```

Six files. ~2100 lines. Nothing is hidden.

### vs dwm

|  | dwm | zwm |
|--|-----|-----|
| Written in | C | Zig |
| Talks to X via | Xlib | xcb |
| Config language | C preprocessor | Zig comptime |
| Layouts | 3 | 1 |
| Has a bar | Yes | No |
| Binary | ~40KB | ~37KB |

### Tags

Nine bits. Each window has them. Each monitor shows some of them.

A window can wear tag 1 and tag 3. Show both tags, see the window. Show just tag 2, it's gone. Simple as set intersection.

### Status bar

zwm has no bar. It speaks EWMH — `_NET_CURRENT_DESKTOP`, `_NET_ACTIVE_WINDOW`, `_NET_WM_STRUT_PARTIAL` — so any bar that listens will hear it.

i3blocks, polybar, lemonbar. They all work.

## License

[MIT](LICENSE)
