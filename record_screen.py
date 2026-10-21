#!/usr/bin/env python3
"""
Screen Recording Generator for ASCII Eye
Renders a simulated terminal session at 1280x720 30 FPS with:
- TrueColor ASCII character rendering
- Live mouse cursor movement across the terminal
- Mouse click triggers with pulse ripple (blink animation)
- Spacebar glance & blink triggers
- Synced Billie Eilish - CHIHIRO audio track
Outputs: demo.mp4 and updated preview.gif
"""

import math
import subprocess
import time
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

import eye

def make_cursor_image():
    """Create a crisp 32x32 RGBA mouse cursor with shadow."""
    c_img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(c_img)
    shadow_pts = [(2, 2), (2, 23), (7, 18), (12, 27), (16, 25), (11, 16), (18, 16)]
    pts = [(0, 0), (0, 21), (5, 16), (10, 25), (14, 23), (9, 14), (16, 14)]
    d.polygon(shadow_pts, fill=(0, 0, 0, 110))
    d.polygon(pts, fill=(255, 255, 255, 255), outline=(15, 15, 20, 255))
    return c_img

def main():
    print("Initializing screen recording engine...")
    w, h = 128, 40
    char_w, char_h = 10, 18
    win_w = w * char_w
    win_h = h * char_h
    fps = 30
    duration_sec = 12.0
    total_frames = int(fps * duration_sec)

    renderer = eye.EyeRenderer(w=w, h=h, scale=1.65)
    controller = eye.EyeController()

    try:
        font = ImageFont.truetype("/usr/share/fonts/TTF/DejaVuSansMono.ttf", 15)
    except Exception:
        font = ImageFont.load_default()

    # Pre-render glyph bitmap cache
    glyphs = {}
    for code in range(32, 127):
        ch = chr(code)
        img = Image.new("L", (char_w, char_h), 0)
        d = ImageDraw.Draw(img)
        d.text((0, 0), ch, fill=255, font=font)
        glyphs[ch] = np.array(img, dtype=np.float32) / 255.0

    cursor_sprite = make_cursor_image()

    # Setup ffmpeg pipe for MP4 video encoding
    output_mp4 = "demo.mp4"
    audio_path = Path("audio/chihiro.mp3")

    ffmpeg_cmd = [
        "ffmpeg", "-y",
        "-f", "rawvideo",
        "-vcodec", "rawvideo",
        "-s", f"{win_w}x{win_h}",
        "-pix_fmt", "rgb24",
        "-r", str(fps),
        "-i", "-",  # Video from stdin pipe
    ]

    if audio_path.exists():
        ffmpeg_cmd.extend([
            "-ss", "00:00:10",  # Start audio at beat drop
            "-i", str(audio_path),
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-preset", "fast",
            "-crf", "22",
            "-c:a", "aac",
            "-b:a", "192k",
            "-t", str(duration_sec),
            output_mp4
        ])
    else:
        ffmpeg_cmd.extend([
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-preset", "fast",
            "-crf", "22",
            "-t", str(duration_sec),
            output_mp4
        ])

    proc = subprocess.Popen(ffmpeg_cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Keyframe timeline for mouse movement & interaction
    # Trajectory of mouse cursor across the terminal:
    # 0s - 2s: Center hover
    # 2s - 4.5s: Move to top-right (gx > 0, gy < 0)
    # 4.5s: Click -> blink!
    # 5.5s - 8s: Swoop down-left (gx < 0, gy > 0)
    # 8s: Click -> blink!
    # 8.5s - 10.5s: Move to top-left, then center
    # 10.5s - 12s: Center settle
    gif_frames = []

    print(f"Rendering {total_frames} frames at {win_w}x{win_h} (30 FPS)...")

    for f in range(total_frames):
        t = f / fps

        # Compute mouse position (screen coordinates)
        if t < 2.0:
            mx = win_w * 0.50 + math.sin(t * 1.5) * 20.0
            my = win_h * 0.50 + math.cos(t * 1.2) * 15.0
            clicking = False
        elif t < 4.5:
            p = (t - 2.0) / 2.5
            p_smooth = p * p * (3.0 - 2.0 * p)
            mx = (win_w * 0.50) + p_smooth * (win_w * 0.35)
            my = (win_h * 0.50) - p_smooth * (win_h * 0.30)
            clicking = False
        elif t < 5.0:
            mx = win_w * 0.85
            my = win_h * 0.20
            clicking = (t < 4.7)
            if f == int(4.5 * fps):
                controller.trigger_blink()
        elif t < 7.5:
            p = (t - 5.0) / 2.5
            p_smooth = p * p * (3.0 - 2.0 * p)
            mx = (win_w * 0.85) - p_smooth * (win_w * 0.65)
            my = (win_h * 0.20) + p_smooth * (win_h * 0.58)
            clicking = False
        elif t < 8.2:
            mx = win_w * 0.20
            my = win_h * 0.78
            clicking = (t < 7.8)
            if f == int(7.6 * fps):
                controller.trigger_blink()
        elif t < 10.5:
            p = (t - 8.2) / 2.3
            p_smooth = p * p * (3.0 - 2.0 * p)
            mx = (win_w * 0.20) + p_smooth * (win_w * 0.30)
            my = (win_h * 0.78) - p_smooth * (win_h * 0.28)
            clicking = False
        else:
            mx = win_w * 0.50 + math.sin(t * 2.0) * 15.0
            my = win_h * 0.50 + math.cos(t * 1.8) * 10.0
            clicking = False

        # Convert cursor position to normalized gaze
        norm_x = (mx / win_w) * 2.0 - 1.0
        norm_y = (my / win_h) * 2.0 - 1.0  # -1 is top, +1 is bottom
        controller.set_mouse_gaze(norm_x, norm_y)
        controller.update()

        col, chars = renderer.render(
            ou=controller.ou,
            gx=controller.gx,
            gy=controller.gy,
            tick=f,
            pupil_r=controller.pupil_radius
        )

        # Draw ASCII grid into pixel buffer
        buf = np.zeros((win_h, win_w, 3), dtype=np.uint8)
        colors_u8 = (col * 255.0).astype(np.uint8)

        for row in range(renderer.h):
            y0 = row * char_h
            y1 = y0 + char_h
            for col_idx in range(renderer.w):
                x0 = col_idx * char_w
                x1 = x0 + char_w
                mask = glyphs.get(chars[row][col_idx])
                if mask is not None:
                    rgb = colors_u8[row, col_idx]
                    buf[y0:y1, x0:x1] = (mask[..., None] * rgb).astype(np.uint8)

        frame_img = Image.fromarray(buf, mode="RGB")
        draw = ImageDraw.Draw(frame_img)

        # Draw click pulse ripple
        if clicking:
            click_progress = (t % 0.3) / 0.3
            r_ring = int(6 + click_progress * 22)
            draw.ellipse(
                (int(mx - r_ring), int(my - r_ring), int(mx + r_ring), int(my + r_ring)),
                outline=(240, 200, 100, 200),
                width=2
            )

        # Composite mouse cursor arrow
        frame_img.paste(cursor_sprite, (int(mx), int(my)), cursor_sprite)

        # Write to ffmpeg pipe
        proc.stdin.write(frame_img.tobytes())

        # Save sample frames for README GIF (1 out of every 3 frames = 10 FPS preview)
        if f % 3 == 0 and t >= 2.0 and t <= 8.5:
            # Scale down for lightweight GIF preview
            gif_frame = frame_img.resize((640, 360), Image.Resampling.BILINEAR)
            gif_frames.append(gif_frame)

        if f % 60 == 0:
            print(f"Rendered frame {f}/{total_frames} ({(f/total_frames)*100:.1f}%)")

    proc.stdin.close()
    proc.wait()
    print("Video encoding completed: demo.mp4")

    # Save animated GIF preview
    if gif_frames:
        print("Generating preview.gif for README...")
        gif_frames[0].save(
            "preview.gif",
            save_all=True,
            append_images=gif_frames[1:],
            duration=100,  # 10 fps
            loop=0,
            optimize=True
        )
        print("Updated preview.gif successfully!")

if __name__ == '__main__':
    main()
