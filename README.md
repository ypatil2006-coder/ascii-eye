# ASCII Eye Animation & Interaction Engine 👁️

[![x86_64 Assembly](https://img.shields.io/badge/Assembly-x86__64%20(GAS)-black.svg?logo=gnu)](eye.s)
[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A hyper-realistic parametric mathematical ASCII shader and animation engine replicating [buildmeri's *'in your eyes'*](https://www.instagram.com/reel/DeshX7jIyXP/).

Available in **two complete standalone variants**:
- **⚡ Native x86_64 Assembly (`eye.s`)**: Pure handcrafted assembly, hardware SSE/SIMD math, zero runtime dependencies, ~31 KB binary, sub-millisecond per-frame rasterization.
- **🐍 Python 3 (`eye.py`)**: Fullscreen CLI with NumPy vectorization + Desktop Tkinter GUI mode + *CHIHIRO* audio integration.

![ASCII Eye Preview](preview.gif)

> 🎬 **Full Screen Recording with Sound (1080p HD)**: [**demo.mp4**](https://github.com/ypatil2006-coder/ascii-eye/raw/main/demo.mp4) *(Watch real-time mouse tracking, blinks, and Billie Eilish - CHIHIRO in action)*

---

## ⚡ Quick Start: Choose Your Variant

### Variant 1: Pure x86_64 Assembly (Fastest, Zero Dependencies)

No Python or packages required — compiles directly on Linux x86_64 using GCC:

```bash
git clone https://github.com/ypatil2006-coder/ascii-eye.git
cd ascii-eye

# Build the native binary
make

# Run the eye
./eye_asm
# or
make run
```

### Variant 2: Python 3 Engine (CLI + GUI + Music)

```bash
git clone https://github.com/ypatil2006-coder/ascii-eye.git
cd ascii-eye
pip install -r requirements.txt

# Run in fullscreen terminal
python3 eye.py

# Optional: run with background music (requires mpv)
python3 eye.py --music

# Optional: run in Desktop GUI mode
python3 eye.py --gui
```

---

## 🥊 Variant Comparison

| Feature | ⚡ Pure x86_64 Assembly (`eye.s`) | 🐍 Python 3 (`eye.py`) |
| :--- | :--- | :--- |
| **Language** | Native x86_64 Assembly (GAS Intel syntax) | Python 3.8+ (NumPy + ANSI) |
| **Binary / Footprint** | **~31 KB single executable** | Python runtime + pip wheels |
| **Frame Render Time** | **< 0.2 ms per frame (<0.1% CPU)** | ~12 ms per frame (vectorized NumPy) |
| **Dependencies** | None (Linux syscalls + libc/libm) | NumPy, Pillow (for GUI), mpv (music) |
| **Terminal Mouse Tracking** | Real-time SGR 1006 non-blocking `poll()` | Real-time SGR 1006 non-blocking `select()` |
| **Window Auto-Resizing** | Real-time `SIGWINCH` + `ioctl(TIOCGWINSZ)` | Real-time `SIGWINCH` + `shutil` |
| **Color Protocol** | Delta-compressed ANSI TrueColor | ANSI TrueColor string formatting |
| **Desktop GUI Window** | Terminal-only | Included (Tkinter canvas bitmap font) |
| **Audio Playback** | — | Included (CHIHIRO via `mpv`) |

---

## ✨ Features (Both Variants)

- **Responsive Fullscreen CLI**: Dynamically queries terminal dimensions and fills 100% of your terminal window edge-to-edge.
- **Aspect-Ratio Preservation**: Automatically accounts for the $2.05\times$ vertical character cell ratio so the eye remains perfectly circular and undistorted across standard, ultrawide, and vertical split layouts.
- **Real-Time SGR 1006 Mouse Tracking**: The eye tracks your mouse cursor anywhere across the terminal in real time (moving up looks UP, moving down looks DOWN).
- **Biological Realism**:
  - **Pupillary Hippus**: Continuous autonomic pupil dilation/constriction breathing (~1.5Hz).
  - **3D Corneal Curvature**: Perspective elliptical foreshortening of the iris when glancing off-axis.
  - **Optical Parallax Catchlights**: Stationary external light reflections sliding across the curved cornea.
  - **Scleral Micro-Capillaries**: Delicate branching vascular blood vessels threading from the corners of the eye.
  - **Lacrimal Caruncle**: Fleshy pink mucosal nodule at the inner nasal canthus.
  - **Wet Tear Meniscus**: Glistening specular reflection along the lower eyelid waterline.
  - **Tschermak's Eyelid Lag**: Eyelids follow the vertical orientation of the cornea.
  - **Fixational Eye Movements**: High-frequency physiological tremor (~40Hz) and microsaccadic corrections.

---

## 🕹️ Controls & Interaction

| Control | Action |
| :--- | :--- |
| **Mouse Cursor** | The eye follows your cursor across the terminal |
| **Left Click** | Triggers an immediate natural blink |
| **Right Click** | Triggers a dynamic glance & blink sequence |
| **Spacebar / Enter** | Triggers glance & blink animation sequence |
| **Arrow Keys (<kbd>↑</kbd> <kbd>↓</kbd> <kbd>←</kbd> <kbd>→</kbd>)** | Manually direct gaze |
| **Scroll Wheel (<kbd>↑</kbd> / <kbd>↓</kbd>)** | Tilt gaze up or down |
| **<kbd>B</kbd>** | Trigger blink |
| **<kbd>M</kbd>** *(Python only)* | Toggle background soundtrack (*CHIHIRO*) |
| **<kbd>Q</kbd> / <kbd>Esc</kbd> / <kbd>Ctrl+C</kbd>** | Clean exit (restores terminal state cleanly) |

---

## 🛠️ Assembly Engine Architecture (`eye.s`)

The assembly engine is built from scratch for maximum efficiency:
- **SSE/SSE4.1 Instruction Set**: Hardware `movss`, `mulss`, `addss`, `subss`, `sqrtss`, and `roundss` (floor) instructions eliminate software math overhead.
- **Zero Allocations in Render Loop**: Analytical 2D Value Noise computed mathematically per cell via 64-bit integer hashing (`hash2d`), eliminating texture buffer memory allocations.
- **Delta-Compression Buffer Builder**: Compares current RGB with `last_rgb` and only emits `\033[38;2;R;G;Bm` escape codes when colors change, shrinking frame output from ~150 KB to ~50 KB.
- **Single Syscall Flusher**: Formats the entire frame into a static buffer in `.bss` and writes it with a single `write(1, out_buf, out_len)` syscall.

---

## 📐 How the Mathematical Shader Works

1. **Parametric Mathematical Shader**:
   The eyelid arches, crease lines, lash spikes, sclera, iris spokes, and pupil are defined through continuous mathematical distance functions (`smoothstep`, Gaussian curves, trigonometric wave harmonics, and exponential decay).
2. **Procedural Noise**:
   Smooth bilinear noise textures (`tx_skin`, `tx_detail`, `tx_fibers`) generate organic skin pores and iris striations.
3. **SGR 1006 Terminal Mouse Protocol**:
   Terminal mode enables raw cbreak input alongside `\033[?1003h\033[?1006h` escape sequences, parsing mouse movements and button events without blocking the 30-60 FPS render pipeline.
4. **Flicker-Free Alternate Screen Buffer**:
   Uses `\033[?1049h` and disabled line auto-wrapping (`\033[?7l`), writing full-screen frames into `\033[H` to prevent terminal scroll bounce.

---

## 📄 License

MIT License. Feel free to use, modify, and build upon this engine.
