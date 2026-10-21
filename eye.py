#!/usr/bin/env python3
"""
ASCII Eye Animation & Interaction Engine
Replication of buildmeri's 'in your eyes' with Python (ANSI Terminal + Tkinter + NumPy)

Features:
- Responsive Fullscreen Terminal Mode: dynamically adapts to 100% of the terminal dimensions.
- Full aspect-ratio preservation: eye is never distorted, with skin and vignette covering the rest.
- Large, commanding eye scale: fills the central view with rich iris and lash detail.
- Natural Live Mouse Tracking: moving mouse UP looks UP, moving mouse DOWN looks DOWN.
- Interactive triggers: Left click to blink, Spacebar to glance & blink, Arrow keys for manual gaze.
- M key toggles background Billie Eilish - CHIHIRO sound integration.
- Desktop Tkinter GUI mode available via `--gui`.
"""

import sys
import os
import time
import math
import random
import argparse
import subprocess
import signal
import re
import shutil
from pathlib import Path
import numpy as np

# Try importing GUI libraries
try:
    import tkinter as tk
    from PIL import Image, ImageTk, ImageDraw, ImageFont
    HAS_GUI = True
except ImportError:
    HAS_GUI = False

# Try importing terminal control libraries
try:
    import tty
    import termios
    import select
    HAS_TERMIOS = True
except ImportError:
    HAS_TERMIOS = False


def ss(e0, e1, x):
    """Smoothstep function with zero-division safeguard."""
    t = np.clip((x - e0) / (e1 - e0 + 1e-7), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def make_noise(h, w, fx, fy, seed=42):
    """Generate smooth bilinear procedural noise texture with PIL and NumPy fallback."""
    rng = np.random.RandomState(seed)
    gw = max(4, int(w * fx))
    gh = max(4, int(h * fy))
    grid = rng.uniform(0.0, 1.0, (gh, gw)).astype(np.float32)
    if HAS_GUI:
        try:
            img = Image.fromarray(grid).resize((w, h), Image.Resampling.BILINEAR)
            return np.array(img, dtype=np.float32)
        except Exception:
            pass
    # Pure numpy bilinear interpolation fallback
    y_idx = np.linspace(0, gh - 1, h, dtype=np.float32)
    x_idx = np.linspace(0, gw - 1, w, dtype=np.float32)
    y0 = np.floor(y_idx).astype(int)
    y1 = np.clip(y0 + 1, 0, gh - 1)
    x0 = np.floor(x_idx).astype(int)
    x1 = np.clip(x0 + 1, 0, gw - 1)
    wy = (y_idx - y0)[:, None]
    wx = (x_idx - x0)[None, :]
    top = grid[y0[:, None], x0[None, :]] * (1.0 - wx) + grid[y0[:, None], x1[None, :]] * wx
    bot = grid[y1[:, None], x0[None, :]] * (1.0 - wx) + grid[y1[:, None], x1[None, :]] * wx
    return (top * (1.0 - wy) + bot * wy).astype(np.float32)


def toggle_music(proc=None):
    """Toggle background mpv playback for CHIHIRO."""
    audio_file = Path(__file__).parent / "audio" / "chihiro.mp3"
    if not audio_file.exists():
        return proc

    if proc is None or proc.poll() is not None:
        cmd = ["mpv", "--loop=inf", "--no-video", "--volume=75", str(audio_file)]
        try:
            return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            return None
    else:
        try:
            proc.terminate()
            proc.wait(timeout=0.3)
        except Exception:
            pass
        return None


class EyeRenderer:
    def __init__(self, w=86, h=36, scale=1.65):
        self.char_aspect = 2.05
        self.eye_w = 0.82
        self.scale = max(0.5, float(scale))

        # Character pools matching buildmeri's exact ASCII aesthetic
        self.skin_letters = "vczxunxrjftYXZUJCL"
        self.sclera_letters = "0OQCZJUYXzcvun"
        self.iris_letters = "0OQ8%&B$@WM#*obp"

        self.w = None
        self.h = None
        self.resize(w, h, force=True)

    def resize(self, w, h, force=False):
        """Recompute coordinate grids and noise textures when window size changes."""
        w = max(20, int(w))
        h = max(10, int(h))
        if not force and w == self.w and h == self.h:
            return

        self.w = w
        self.h = h

        # Calculate physical aspect ratio of terminal: w / (h * char_aspect)
        a_phys = self.w / (self.h * self.char_aspect)
        base_factor = 0.52 / self.scale
        if a_phys >= 1.0:
            v_span = base_factor * self.char_aspect
            u_span = v_span * a_phys
        else:
            u_span = base_factor * self.char_aspect
            v_span = u_span / a_phys

        u_lin = np.linspace(-u_span, u_span, self.w, dtype=np.float32)
        v_lin = np.linspace(-v_span, v_span, self.h, dtype=np.float32)
        self.u, self.v = np.meshgrid(u_lin, v_lin)

        # Procedural noise textures
        self.tx_skin = make_noise(self.h, self.w, 0.20, 0.20, seed=10)
        self.tx_detail = make_noise(self.h, self.w, 0.50, 0.50, seed=20)
        self.tx_fibers = make_noise(self.h, self.w, 0.85, 0.85, seed=30)

        # Stable pseudo-random grid for organic letter variation
        rng = np.random.RandomState(1337)
        self.char_hash = rng.randint(0, 10000, (self.h, self.w))

        # Horizontal normalized coordinate
        self.s = self.u / self.eye_w
        self.in_eye_horiz = np.abs(self.s) <= 1.0
        self.arch = np.maximum(0.0, 1.0 - self.s**2)

    def render(self, ou=1.0, gx=0.0, gy=0.0, tick=0):
        """
        Renders a single frame.
        ou: openness (1.0 = wide open, 0.0 = completely shut)
        gx, gy: gaze coordinates (-0.22 to 0.22 for gx, -0.14 to 0.14 for gy)
        tick: animation step counter
        """
        u, v = self.u, self.v
        s = self.s
        arch = self.arch
        in_eye_horiz = self.in_eye_horiz
        h, w = self.h, self.w

        # 1. Eyelid Geometry
        y_up_open = 0.46 * arch * (1.0 - 0.15 * s) + 0.02 * s
        y_dn_open = -0.28 * arch * (1.0 + 0.10 * s) + 0.01 * s
        y_seam = -0.06 * arch + 0.01 * s

        y_up = y_up_open * ou + y_seam * (1.0 - ou)
        y_dn = y_dn_open * (0.2 + 0.8 * ou) + (y_seam - 0.01) * (1.0 - ou)

        du = v - y_up
        dl = y_dn - v
        lid_mid = 0.5 * (y_up + y_dn)
        upper = v >= lid_mid
        inside_eye = in_eye_horiz & (v < y_up) & (v > y_dn) & (y_up > y_dn + 0.02) & (ou > 0.04)

        # 2. Base Skin Tones
        base = np.array([0.62, 0.40, 0.29], dtype=np.float32)
        col = np.ones((h, w, 3), dtype=np.float32) * base * (0.88 + 0.24 * self.tx_skin[..., None])

        # Soft ambient vignette towards outer border
        dist_ctr = np.sqrt((u * 0.8)**2 + (v * 1.1)**2)
        lighting = 1.06 - 0.32 * ss(0.3, 1.15, dist_ctr)
        col *= lighting[..., None]

        # Upper eyelid crease
        cr_pos = 0.14 * (0.65 + 0.35 * ou)
        crease = np.exp(-((du - cr_pos) / 0.028)**2) * upper * in_eye_horiz
        col -= crease[..., None] * np.array([0.24, 0.18, 0.14], dtype=np.float32)

        # Eyelid fold highlight
        fold_hl = np.exp(-((du - (cr_pos + 0.08)) / 0.05)**2) * upper * in_eye_horiz
        col += fold_hl[..., None] * np.array([0.10, 0.07, 0.05], dtype=np.float32)

        # Lower eyelid shadow
        lower_fold = np.exp(-((dl - 0.10) / 0.05)**2) * (~upper) * in_eye_horiz
        col -= lower_fold[..., None] * np.array([0.13, 0.10, 0.08], dtype=np.float32)

        # Waterline along lower eyelid margin
        wl = np.exp(-((dl - 0.014) / 0.007)**2) * (~upper) * in_eye_horiz * (0.3 + 0.7 * ou)
        col = np.where(
            wl[..., None] > 0.12,
            col * (1.0 - wl[..., None] * 0.75) + np.array([0.76, 0.34, 0.30], dtype=np.float32) * (wl[..., None] * 0.75),
            col,
        )

        # Dark eyeliner along lid margins
        line_up = np.exp(-(du / 0.014)**2) * upper * in_eye_horiz
        line_dn = np.exp(-(dl / 0.010)**2) * (~upper) * in_eye_horiz
        lashline = np.maximum(line_up, line_dn)
        col -= lashline[..., None] * np.array([0.48, 0.36, 0.28], dtype=np.float32)

        # 3. Eyeball Sclera
        sclera_col = np.array([0.94, 0.92, 0.90], dtype=np.float32)
        canthus = ss(0.40, 0.95, np.abs(s))
        sclera_col = sclera_col * (1.0 - canthus[..., None]) + np.array([0.84, 0.45, 0.45], dtype=np.float32) * canthus[..., None]
        sclera_col *= (0.92 + 0.16 * self.tx_detail[..., None])

        # Upper lid shadow over sclera
        lid_shadow = ss(0.0, 0.18, y_up - v) * upper
        sclera_col *= (0.50 + 0.50 * lid_shadow[..., None])

        # 4. Iris & Pupil
        cx, cy = gx, gy
        dist_iris = np.sqrt((u - cx)**2 + ((v - cy) * 1.05)**2)
        r_iris = 0.34
        r_pupil = 0.13

        in_iris = (dist_iris < r_iris) & inside_eye
        in_pupil = (dist_iris < r_pupil) & inside_eye

        angle = np.arctan2(v - cy, u - cx)
        iris_norm = dist_iris / r_iris
        radial_spokes = 0.5 + 0.5 * np.cos(angle * 32.0 + self.tx_fibers * 8.0)
        limbal = ss(0.74, 0.98, iris_norm)
        collarette = np.exp(-((iris_norm - 0.45) / 0.15)**2)

        c_limbal = np.array([0.08, 0.18, 0.24], dtype=np.float32)
        c_stroma = np.array([0.30, 0.52, 0.44], dtype=np.float32)  # Hazel-teal
        c_inner = np.array([0.70, 0.54, 0.22], dtype=np.float32)   # Golden amber

        iris_col = c_stroma * (1.0 - collarette[..., None] * 0.6) + c_inner * (collarette[..., None] * 0.6)
        iris_col += (radial_spokes[..., None] - 0.5) * 0.15
        iris_col = iris_col * (1.0 - limbal[..., None] * 0.75) + c_limbal * (limbal[..., None] * 0.75)
        iris_col *= (0.55 + 0.45 * lid_shadow[..., None])

        pupil_col = np.array([0.02, 0.02, 0.02], dtype=np.float32)

        # Corneal Specular Highlights (Catchlights)
        sp1 = np.exp(-((np.sqrt((u - (cx - 0.07))**2 + ((v - (cy + 0.08)) * 1.1)**2)) / 0.030)**2) * 1.8
        sp2 = np.exp(-((np.sqrt((u - (cx + 0.08))**2 + ((v - (cy - 0.05)) * 1.1)**2)) / 0.020)**2) * 0.95
        glint = np.clip(sp1 + sp2, 0.0, 1.0)

        eye_composite = sclera_col
        eye_composite = np.where(in_iris[..., None], iris_col, eye_composite)
        eye_composite = np.where(in_pupil[..., None], pupil_col, eye_composite)
        eye_composite = np.clip(eye_composite + glint[..., None] * np.array([1.0, 0.98, 0.94], dtype=np.float32), 0.0, 1.0)

        col = np.where(inside_eye[..., None], eye_composite, col)

        # 5. Eyelashes
        lash_freq = 28.0
        lash_spikes = np.maximum(0.0, np.cos(u * lash_freq + s * 1.8))**7.0
        lash_len_up = (0.11 + 0.05 * s**2) * (0.35 + 0.65 * ou)
        is_lash_up = (du > 0) & (du < lash_len_up) & in_eye_horiz
        lash_up = lash_spikes * (1.0 - du / np.maximum(1e-4, lash_len_up)) * is_lash_up

        lash_len_dn = 0.05 * (1.0 - 0.4 * s**2)
        is_lash_dn = (dl > 0) & (dl < lash_len_dn) & in_eye_horiz
        lash_dn = np.maximum(0.0, np.cos(u * 24.0))**9.0 * (1.0 - dl / np.maximum(1e-4, lash_len_dn)) * is_lash_dn

        blink_seam = np.exp(-((v - y_seam) / 0.018)**2) * in_eye_horiz * (1.0 - ou) * 0.88
        total_lash = np.clip(lash_up * 1.3 + lash_dn * 0.9 + blink_seam, 0.0, 0.96)
        c_lash = np.array([0.03, 0.02, 0.02], dtype=np.float32)
        col = col * (1.0 - total_lash[..., None]) + c_lash * total_lash[..., None]

        col = np.clip(col, 0.0, 1.0)

        # 6. Character Mapping
        char_matrix = []
        for r in range(h):
            row_chars = []
            for c in range(w):
                h_val = self.char_hash[r, c]
                if total_lash[r, c] > 0.40:
                    if ou < 0.2:
                        ch = '-' if (c % 2 == 0) else '+'
                    elif u[r, c] < -0.15:
                        ch = '/'
                    elif u[r, c] > 0.15:
                        ch = '\\'
                    else:
                        ch = '|'
                elif glint[r, c] > 0.55:
                    ch = '*'
                elif in_pupil[r, c]:
                    ch = '@' if dist_iris[r, c] < r_pupil * 0.65 else '#'
                elif in_iris[r, c]:
                    ch = self.iris_letters[(h_val + tick) % len(self.iris_letters)]
                elif inside_eye[r, c]:
                    ch = self.sclera_letters[h_val % len(self.sclera_letters)]
                elif lashline[r, c] > 0.35:
                    ch = '-' if abs(u[r, c]) < 0.3 else ('/' if u[r, c] < 0 else '\\')
                elif crease[r, c] > 0.35:
                    ch = '(' if (r + c) % 2 == 0 else ')'
                else:
                    ch = self.skin_letters[h_val % len(self.skin_letters)]

                row_chars.append(ch)
            char_matrix.append(row_chars)

        return col, char_matrix


class EyeController:
    """Manages natural saccades, blinks, and interactive triggers."""
    def __init__(self):
        self.ou = 1.0          # Current openness (0.0 = closed, 1.0 = open)
        self.ou_target = 1.0
        self.gx = 0.0          # Current horizontal gaze (-0.22 to 0.22)
        self.gy = 0.0          # Current vertical gaze (-0.14 to 0.14, negative is UP, positive is DOWN)
        self.gx_target = 0.0
        self.gy_target = 0.0

        self.mouse_control = False
        self.last_mouse_time = time.time()
        self.blink_start_time = 0.0
        self.is_blinking = False
        self.next_saccade_time = time.time() + 1.5
        self.next_blink_time = time.time() + 3.0

    def trigger_space_animation(self):
        """Action triggered when Spacebar or Click is pressed."""
        self.gx_target = random.choice([-0.18, 0.0, 0.18])
        self.gy_target = random.choice([-0.06, 0.0, 0.06])
        self.trigger_blink()

    def trigger_blink(self):
        if not self.is_blinking:
            self.is_blinking = True
            self.blink_start_time = time.time()

    def set_mouse_gaze(self, norm_x, norm_y):
        """
        Eye looks towards normalized position:
        norm_x: -1.0 (left) to +1.0 (right)
        norm_y: -1.0 (top/up) to +1.0 (bottom/down)
        """
        self.mouse_control = True
        self.last_mouse_time = time.time()
        self.gx_target = float(np.clip(norm_x * 0.22, -0.22, 0.22))
        self.gy_target = float(np.clip(norm_y * 0.14, -0.14, 0.14))

    def update(self):
        now = time.time()

        # If user stops moving mouse for > 2.5s, resume organic autonomous looking
        if self.mouse_control and (now - self.last_mouse_time > 2.5):
            self.mouse_control = False
            self.next_saccade_time = now + random.uniform(0.6, 1.8)

        # 1. Idle Saccades
        if not self.mouse_control and now > self.next_saccade_time:
            self.gx_target = random.choice([-0.20, -0.10, 0.0, 0.10, 0.20])
            self.gy_target = random.choice([-0.06, 0.0, 0.06])
            self.next_saccade_time = now + random.uniform(1.2, 3.2)

        # 2. Spontaneous Blinks
        if now > self.next_blink_time:
            self.trigger_blink()
            self.next_blink_time = now + random.uniform(3.0, 6.0)

        # 3. Handle Blink Curve (~240ms duration)
        if self.is_blinking:
            elapsed = (now - self.blink_start_time) * 1000.0  # ms
            if elapsed < 90.0:
                t = elapsed / 90.0
                self.ou = 1.0 - (t * t)
            elif elapsed < 130.0:
                self.ou = 0.0
            elif elapsed < 250.0:
                t = (elapsed - 130.0) / 120.0
                self.ou = t * (2.0 - t)  # ease-out
            else:
                self.ou = 1.0
                self.is_blinking = False
        else:
            self.ou = 1.0

        # Smooth Gaze Motion (exponential damping)
        self.gx += (self.gx_target - self.gx) * 0.22
        self.gy += (self.gy_target - self.gy) * 0.22


class GuiEyeApp:
    """Tkinter Desktop Window replicating buildmeri's 'Eye -> Space' setup."""
    def __init__(self, renderer, controller, fps=30, auto_music=False):
        self.renderer = renderer
        self.controller = controller
        self.fps = fps
        self.tick = 0
        self.music_proc = None

        self.root = tk.Tk()
        self.root.title("Eye -> Space")
        self.root.configure(bg="#08080a")

        # Monospace character size
        self.char_w = 10
        self.char_h = 18
        self.win_w = renderer.w * self.char_w
        self.win_h = renderer.h * self.char_h

        # Center window
        sw = self.root.winfo_screenwidth()
        sh = self.root.winfo_screenheight()
        x = (sw - self.win_w) // 2
        y = (sh - self.win_h) // 2
        self.root.geometry(f"{self.win_w}x{self.win_h}+{x}+{y}")
        self.root.resizable(False, False)

        # Pre-render ASCII glyph bitmap cache
        try:
            self.font = ImageFont.truetype("/usr/share/fonts/TTF/DejaVuSansMono.ttf", 15)
        except Exception:
            self.font = ImageFont.load_default()

        self.glyphs = {}
        for code in range(32, 127):
            ch = chr(code)
            img = Image.new("L", (self.char_w, self.char_h), 0)
            d = ImageDraw.Draw(img)
            d.text((0, 0), ch, fill=255, font=self.font)
            self.glyphs[ch] = np.array(img, dtype=np.float32) / 255.0

        # Canvas
        self.canvas = tk.Canvas(self.root, width=self.win_w, height=self.win_h, bg="#08080a", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)

        self.photo = None
        self.canvas_img_id = None

        # Bindings
        self.root.bind("<space>", lambda e: self.controller.trigger_space_animation())
        self.root.bind("<Motion>", self.on_mouse_move)
        self.root.bind("<Button-1>", lambda e: self.controller.trigger_blink())
        self.root.bind("<m>", lambda e: self.toggle_music())
        self.root.bind("<q>", lambda e: self.on_close())
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

        if auto_music:
            self.music_proc = toggle_music(None)

        self.animate()

    def on_mouse_move(self, event):
        norm_x = (event.x / self.win_w) * 2.0 - 1.0
        norm_y = (event.y / self.win_h) * 2.0 - 1.0  # -1 at top, +1 at bottom
        self.controller.set_mouse_gaze(norm_x, norm_y)

    def toggle_music(self):
        self.music_proc = toggle_music(self.music_proc)

    def on_close(self):
        if self.music_proc and self.music_proc.poll() is None:
            try:
                self.music_proc.terminate()
            except Exception:
                pass
        self.root.destroy()
        sys.exit(0)

    def animate(self):
        self.controller.update()
        ou = self.controller.ou
        gx = self.controller.gx
        gy = self.controller.gy

        col, chars = self.renderer.render(ou=ou, gx=gx, gy=gy, tick=self.tick)
        self.tick += 1

        # Fast blit into pixel buffer
        buf = np.zeros((self.win_h, self.win_w, 3), dtype=np.uint8)
        colors_uint8 = (col * 255.0).astype(np.uint8)
        char_h, char_w = self.char_h, self.char_w

        for r in range(self.renderer.h):
            y0 = r * char_h
            y1 = y0 + char_h
            for c in range(self.renderer.w):
                x0 = c * char_w
                x1 = x0 + char_w
                mask = self.glyphs.get(chars[r][c])
                if mask is not None:
                    rgb = colors_uint8[r, c]
                    buf[y0:y1, x0:x1] = (mask[..., None] * rgb).astype(np.uint8)

        img = Image.fromarray(buf, mode="RGB")
        self.photo = ImageTk.PhotoImage(image=img)

        if self.canvas_img_id is None:
            self.canvas_img_id = self.canvas.create_image(0, 0, image=self.photo, anchor="nw")
        else:
            self.canvas.itemconfig(self.canvas_img_id, image=self.photo)

        delay_ms = max(10, int(1000.0 / self.fps))
        self.root.after(delay_ms, self.animate)

    def run(self):
        self.root.mainloop()


def run_terminal_mode(renderer, controller, fps=30, auto_music=False, auto_resize=True):
    """
    Terminal Mode:
    - Automatically covers 100% of the terminal window edge-to-edge.
    - Full dynamic responsive resizing on window resize / SIGWINCH.
    - Big detailed eye scale matching user's requested size.
    - Natural live mouse tracking (moving mouse UP looks UP, moving DOWN looks DOWN).
    - Left Click triggers blink; Right Click triggers glance + blink.
    - Keyboard: Spacebar (glance & blink), Arrow keys (manual gaze), M (toggle music), Q/Ctrl+C (quit).
    - Clean alternate screen buffer restoration with zero terminal pollution.
    """
    if not HAS_TERMIOS or not sys.stdin.isatty():
        # Fallback for non-interactive environments
        col, chars = renderer.render(ou=1.0, gx=0.0, gy=0.0, tick=0)
        print(f"ASCII Eye active ({renderer.w}x{renderer.h})")
        return

    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)

    music_proc = None
    if auto_music:
        music_proc = toggle_music(None)

    # SIGWINCH resize listener for instant window resize detection
    resized = False
    def sigwinch_handler(signum, frame):
        nonlocal resized
        resized = True

    try:
        signal.signal(signal.SIGWINCH, sigwinch_handler)
    except Exception:
        pass

    mouse_pattern = re.compile(r'\x1b\[<(\d+);(\d+);(\d+)([Mm])')
    dt = 1.0 / max(1, fps)
    tick = 0

    try:
        # Switch to raw terminal mode
        tty.setraw(fd)

        # Terminal setup sequence:
        # \033[?1049h: Alternate screen buffer
        # \033[?25l: Hide cursor
        # \033[?7l: Disable line auto-wrap (avoids scroll bounce)
        # \033[?1000h\033[?1002h\033[?1003h\033[?1006h: SGR extended all-motion mouse tracking
        # \033[2J\033[H: Clear screen and move cursor to home
        sys.stdout.write(
            "\033[?1049h\033[?25l\033[?7l"
            "\033[?1000h\033[?1002h\033[?1003h\033[?1006h"
            "\033[2J\033[H"
        )
        sys.stdout.flush()

        while True:
            t_start = time.time()

            # Handle dynamic terminal resize
            if auto_resize and (resized or (tick % 15 == 0)):
                resized = False
                cols, rows = shutil.get_terminal_size((86, 36))
                if cols != renderer.w or rows != renderer.h:
                    renderer.resize(cols, rows)
                    sys.stdout.write("\033[2J")
                    sys.stdout.flush()

            # Non-blocking input read
            rlist, _, _ = select.select([sys.stdin], [], [], 0)
            if rlist:
                try:
                    raw_bytes = os.read(fd, 8192)
                    raw = raw_bytes.decode('utf-8', errors='ignore')
                except Exception:
                    raw = ""

                if raw:
                    # Parse all mouse events
                    mouse_events = mouse_pattern.findall(raw)
                    if mouse_events:
                        last_mx, last_my = None, None
                        for btn_s, col_s, row_s, kind in mouse_events:
                            btn = int(btn_s)
                            col_i = int(col_s)
                            row_i = int(row_s)

                            last_mx, last_my = col_i, row_i

                            # Mouse button triggers
                            if btn == 0 and kind == 'M':  # Left click press
                                controller.trigger_blink()
                            elif btn == 2 and kind == 'M':  # Right click press
                                controller.trigger_space_animation()
                            elif btn == 64:  # Wheel up -> look UP
                                controller.set_mouse_gaze(0.0, -0.9)
                            elif btn == 65:  # Wheel down -> look DOWN
                                controller.set_mouse_gaze(0.0, 0.9)

                        if last_mx is not None and last_my is not None:
                            # In terminal: row 1 is top, row h is bottom
                            # norm_x: -1 (left) to +1 (right)
                            # norm_y: -1 (top row 1) to +1 (bottom row h)
                            norm_x = ((last_mx - 1) / max(1, renderer.w - 1)) * 2.0 - 1.0
                            norm_y = ((last_my - 1) / max(1, renderer.h - 1)) * 2.0 - 1.0
                            controller.set_mouse_gaze(norm_x, norm_y)

                    # Inspect non-mouse keys
                    rem = mouse_pattern.sub('', raw)
                    if rem:
                        # Space or Enter
                        if ' ' in rem or '\r' in rem or '\n' in rem:
                            controller.trigger_space_animation()

                        # Toggle music
                        if 'm' in rem or 'M' in rem:
                            music_proc = toggle_music(music_proc)

                        # Manual blink
                        if 'b' in rem or 'B' in rem:
                            controller.trigger_blink()

                        # Arrow keys for manual gaze
                        if '\x1b[A' in rem:  # Up arrow -> look UP
                            controller.set_mouse_gaze(0.0, -1.0)
                        elif '\x1b[B' in rem:  # Down arrow -> look DOWN
                            controller.set_mouse_gaze(0.0, 1.0)
                        elif '\x1b[D' in rem:  # Left arrow -> look LEFT
                            controller.set_mouse_gaze(-1.0, 0.0)
                        elif '\x1b[C' in rem:  # Right arrow -> look RIGHT
                            controller.set_mouse_gaze(1.0, 0.0)

                        # Quit on 'q', 'Q', Ctrl+C (\x03), or ESC (\x1b)
                        if 'q' in rem or 'Q' in rem or '\x03' in rem or rem == '\x1b':
                            break

            # Update controller state
            controller.update()
            ou = controller.ou
            gx = controller.gx
            gy = controller.gy

            # Render frame
            col, chars = renderer.render(ou=ou, gx=gx, gy=gy, tick=tick)
            tick += 1

            # Build ANSI string with fast vector colors
            col_u8 = (col * 255.0).astype(np.uint8)
            lines = []
            for r in range(renderer.h):
                row_str = []
                last_r, last_g, last_b = -1, -1, -1
                for c in range(renderer.w):
                    cr, cg, cb = col_u8[r, c, 0], col_u8[r, c, 1], col_u8[r, c, 2]
                    if cr != last_r or cg != last_g or cb != last_b:
                        row_str.append(f"\033[38;2;{cr};{cg};{cb}m")
                        last_r, last_g, last_b = cr, cg, cb
                    row_str.append(chars[r][c])
                lines.append("".join(row_str))

            # Home cursor + print lines (joined with \r\n, no trailing newline to avoid bottom scroll)
            frame_str = "\033[H" + "\r\n".join(lines) + "\033[0m"
            sys.stdout.write(frame_str)
            sys.stdout.flush()

            # Maintain target FPS
            t_elapsed = time.time() - t_start
            sleep_time = max(0.001, dt - t_elapsed)
            time.sleep(sleep_time)

    finally:
        # Full terminal restoration
        sys.stdout.write(
            "\033[?1003l\033[?1002l\033[?1000l\033[?1006l"
            "\033[?7h\033[?25h\033[?1049l\033[0m"
        )
        sys.stdout.flush()
        try:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
        except Exception:
            pass

        if music_proc and music_proc.poll() is None:
            try:
                music_proc.terminate()
                music_proc.wait(timeout=0.3)
            except Exception:
                pass


def main():
    parser = argparse.ArgumentParser(description="ASCII Eye Replication ('Eye -> Space')")
    parser.add_argument("--cli", action="store_true", help="Run in Terminal ANSI mode")
    parser.add_argument("--gui", action="store_true", help="Run in Tkinter GUI Desktop Window")
    parser.add_argument("--fps", type=int, default=30, help="Target frames per second (default: 30)")
    parser.add_argument("--scale", type=float, default=1.65, help="Eye scale factor (default: 1.65)")
    parser.add_argument("--music", action="store_true", help="Play CHIHIRO background audio on launch")
    parser.add_argument("--width", type=int, default=None, help="Character columns (default: dynamic terminal width)")
    parser.add_argument("--height", type=int, default=None, help="Character rows (default: dynamic terminal height)")
    args = parser.parse_args()

    # Determine mode: default to CLI if in terminal or no GUI requested
    is_gui = args.gui and HAS_GUI

    if is_gui:
        w = args.width if args.width is not None else 86
        h = args.height if args.height is not None else 36
        renderer = EyeRenderer(w=w, h=h, scale=args.scale)
        controller = EyeController()
        app = GuiEyeApp(renderer, controller, fps=args.fps, auto_music=args.music)
        app.run()
    else:
        cols, rows = shutil.get_terminal_size((86, 36))
        w = args.width if args.width is not None else cols
        h = args.height if args.height is not None else rows
        auto_resize = (args.width is None and args.height is None)
        renderer = EyeRenderer(w=w, h=h, scale=args.scale)
        controller = EyeController()
        run_terminal_mode(renderer, controller, fps=args.fps, auto_music=args.music, auto_resize=auto_resize)


if __name__ == "__main__":
    main()
