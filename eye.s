# ==============================================================================
# ASCII Eye Animation & Interaction Engine in Pure x86_64 Assembly
# Target: Linux x86_64 (GNU as / GCC Intel Syntax)
# Architecture: SSE / SSE4.1 SIMD Math + SGR 1006 Mouse Tracking + ANSI TrueColor
# ==============================================================================

.intel_syntax noprefix

.global main

# ------------------------------------------------------------------------------
# Macro Definitions
# ------------------------------------------------------------------------------

# 2D Integer Hash for procedural noise and character selection
.macro HASH2D x_reg, y_reg, seed_reg, out_xmm
    mov eax, \x_reg
    imul eax, eax, 374761393
    mov r11d, \y_reg
    imul r11d, r11d, 668265263
    xor eax, r11d
    xor eax, \seed_reg
    mov r11d, eax
    shr r11d, 13
    xor eax, r11d
    imul eax, eax, 1274126177
    mov r11d, eax
    shr r11d, 16
    xor eax, r11d
    and eax, 0x00ffffff
    cvtsi2ss \out_xmm, eax
    mulss \out_xmm, [rip + c_inv_16m]
.endm

# Memory SSE math helpers
.macro MUL_MEM mem, src_reg
    movss xmm8, \mem
    mulss xmm8, \src_reg
    movss \mem, xmm8
.endm

.macro ADD_MEM mem, src_reg
    movss xmm8, \mem
    addss xmm8, \src_reg
    movss \mem, xmm8
.endm

.macro SUB_MEM mem, src_reg
    movss xmm8, \mem
    subss xmm8, \src_reg
    movss \mem, xmm8
.endm

# ------------------------------------------------------------------------------
# Text Section
# ------------------------------------------------------------------------------
.text

# ==============================================================================
# fast_noise2d: 2D procedural value noise with smoothstep interpolation
# In:  xmm0 = x, xmm1 = y, edi = seed
# Out: xmm0 = noise (0.0 to 1.0)
# ==============================================================================
fast_noise2d:
    mov r8d, edi              # seed
    roundss xmm2, xmm0, 1     # x0 = floor(x)
    roundss xmm3, xmm1, 1     # y0 = floor(y)
    cvttss2si ecx, xmm2       # x0 int
    cvttss2si edx, xmm3       # y0 int

    subss xmm0, xmm2          # fx = x - x0
    subss xmm1, xmm3          # fy = y - y0

    # wx = fx * fx * (3.0 - 2.0 * fx)
    movss xmm4, [rip + c_3_0]
    movss xmm5, [rip + c_2_0]
    mulss xmm5, xmm0
    subss xmm4, xmm5
    mulss xmm4, xmm0
    mulss xmm4, xmm0          # wx in xmm4

    # wy = fy * fy * (3.0 - 2.0 * fy)
    movss xmm6, [rip + c_3_0]
    movss xmm7, [rip + c_2_0]
    mulss xmm7, xmm1
    subss xmm6, xmm7
    mulss xmm6, xmm1
    mulss xmm6, xmm1          # wy in xmm6

    lea r9d, [rcx + 1]        # x1
    lea r10d, [rdx + 1]       # y1

    HASH2D ecx, edx, r8d, xmm2   # n00
    HASH2D r9d, edx, r8d, xmm3   # n10
    HASH2D ecx, r10d, r8d, xmm8  # n01
    HASH2D r9d, r10d, r8d, xmm9  # n11

    # top = n00 * (1.0 - wx) + n10 * wx
    movss xmm10, [rip + c_1_0]
    subss xmm10, xmm4         # 1.0 - wx
    mulss xmm2, xmm10
    mulss xmm3, xmm4
    addss xmm2, xmm3          # top in xmm2

    # bot = n01 * (1.0 - wx) + n11 * wx
    mulss xmm8, xmm10
    mulss xmm9, xmm4
    addss xmm8, xmm9          # bot in xmm8

    # result = top * (1.0 - wy) + bot * wy
    movss xmm11, [rip + c_1_0]
    subss xmm11, xmm6         # 1.0 - wy
    mulss xmm2, xmm11
    mulss xmm8, xmm6
    addss xmm2, xmm8
    movaps xmm0, xmm2
    ret

# ==============================================================================
# ss_func: Smoothstep function
# In:  xmm0 = e0, xmm1 = e1, xmm2 = x
# Out: xmm0 = smoothstep result (0.0 to 1.0)
# ==============================================================================
ss_func:
    movaps xmm3, xmm1
    subss xmm3, xmm0
    addss xmm3, [rip + c_eps]
    movaps xmm4, xmm2
    subss xmm4, xmm0
    divss xmm4, xmm3
    maxss xmm4, [rip + c_0_0]
    minss xmm4, [rip + c_1_0]
    movss xmm0, [rip + c_3_0]
    movss xmm5, [rip + c_2_0]
    mulss xmm5, xmm4
    subss xmm0, xmm5
    mulss xmm0, xmm4
    mulss xmm0, xmm4
    ret

# ==============================================================================
# rand64: 64-bit Xorshift Pseudo-Random Generator
# Out: rax = random 64-bit unsigned integer
# ==============================================================================
rand64:
    mov rax, [rip + rng_state]
    mov rdx, rax
    shl rdx, 13
    xor rax, rdx
    mov rdx, rax
    shr rdx, 7
    xor rax, rdx
    mov rdx, rax
    shl rdx, 17
    xor rax, rdx
    mov [rip + rng_state], rax
    ret

# ==============================================================================
# rand_uniform: Random float between min_v (xmm0) and max_v (xmm1)
# Out: xmm0 = random float
# ==============================================================================
rand_uniform:
    push rbx
    sub rsp, 16
    movss [rsp], xmm0
    movss [rsp + 4], xmm1
    call rand64
    mov edx, eax
    and edx, 0x00ffffff
    cvtsi2ss xmm2, edx
    mulss xmm2, [rip + c_inv_16m]
    movss xmm0, [rsp]
    movss xmm1, [rsp + 4]
    subss xmm1, xmm0
    mulss xmm2, xmm1
    addss xmm0, xmm2
    add rsp, 16
    pop rbx
    ret

# ==============================================================================
# get_time_sec: Get current system epoch time in seconds
# Out: xmm0 = double timestamp (seconds)
# ==============================================================================
get_time_sec:
    sub rsp, 24
    lea rdi, [rsp]
    xor esi, esi
    call gettimeofday
    cvtsi2sd xmm0, qword ptr [rsp]
    cvtsi2sd xmm1, qword ptr [rsp + 8]
    mulsd xmm1, [rip + c_inv_1m_d]
    addsd xmm0, xmm1
    add rsp, 24
    ret

# ==============================================================================
# append_u8_fast: Ultra-fast 0..255 integer to ASCII decimal formatter
# In:  esi = value (0..255), r12 = output buffer pointer
# Out: r12 advanced to next write position
# ==============================================================================
append_u8_fast:
    cmp esi, 100
    jb .Lless100
    mov eax, esi
    mov ecx, 100
    xor edx, edx
    div ecx
    add al, '0'
    mov [r12], al
    inc r12
    mov eax, edx
    mov ecx, 10
    xor edx, edx
    div ecx
    add al, '0'
    mov [r12], al
    inc r12
    add dl, '0'
    mov [r12], dl
    inc r12
    ret
.Lless100:
    cmp esi, 10
    jb .Lless10
    mov eax, esi
    mov ecx, 10
    xor edx, edx
    div ecx
    add al, '0'
    mov [r12], al
    inc r12
    add dl, '0'
    mov [r12], dl
    inc r12
    ret
.Lless10:
    add sil, '0'
    mov [r12], sil
    inc r12
    ret

# ==============================================================================
# Signal Handlers
# ==============================================================================
on_sigint:
    mov dword ptr [rip + running], 0
    ret

on_sigwinch:
    mov dword ptr [rip + winch_flag], 1
    ret

# ==============================================================================
# update_winsize: Query terminal dimensions via TIOCGWINSZ ioctl
# ==============================================================================
update_winsize:
    push rbp
    mov rbp, rsp
    sub rsp, 16

    mov edi, 1                # stdout
    mov esi, 0x5413           # TIOCGWINSZ
    lea rdx, [rip + ws]
    call ioctl

    # Check results
    movzx eax, word ptr [rip + ws + 2] # ws_col
    movzx ecx, word ptr [rip + ws]     # ws_row
    test eax, eax
    jnz .Lcol_ok
    mov eax, 86
.Lcol_ok:
    test ecx, ecx
    jnz .Lrow_ok
    mov ecx, 36
.Lrow_ok:
    mov [rip + cols], eax
    mov [rip + rows], ecx

    leave
    ret

# ==============================================================================
# trigger_blink: Start dynamic blink animation
# ==============================================================================
trigger_blink:
    push rbx
    sub rsp, 8
    cmp dword ptr [rip + is_blinking], 0
    jne .Lalready_blinking
    mov dword ptr [rip + is_blinking], 1
    call get_time_sec
    movsd [rip + blink_start_time], xmm0
.Lalready_blinking:
    add rsp, 8
    pop rbx
    ret

# ==============================================================================
# trigger_space_animation: Glance randomly + trigger blink
# ==============================================================================
trigger_space_animation:
    push rbx
    sub rsp, 8

    # Pick gx_target from {-0.18, -0.09, 0.0, 0.09, 0.18}
    call rand64
    xor edx, edx
    mov ecx, 5
    div ecx                   # edx = 0..4
    lea rax, [rip + space_gx_choices]
    movss xmm0, [rax + rdx * 4]
    movss [rip + gx_target], xmm0

    # Pick gy_target from {-0.06, 0.0, 0.06}
    call rand64
    xor edx, edx
    mov ecx, 3
    div ecx                   # edx = 0..2
    lea rax, [rip + space_gy_choices]
    movss xmm0, [rax + rdx * 4]
    movss [rip + gy_target], xmm0

    call trigger_blink

    add rsp, 8
    pop rbx
    ret

# ==============================================================================
# set_mouse_gaze: Set target gaze from normalized coordinates
# In: xmm0 = norm_x (-1.0 to 1.0), xmm1 = norm_y (-1.0 to 1.0)
# ==============================================================================
set_mouse_gaze:
    push rbx
    sub rsp, 8

    mov dword ptr [rip + mouse_control], 1
    movss [rsp], xmm0
    movss [rsp + 4], xmm1
    call get_time_sec
    movsd [rip + last_mouse_time], xmm0
    movss xmm0, [rsp]
    movss xmm1, [rsp + 4]

    # gx = clamp(norm_x * 0.22, -0.22, 0.22)
    mulss xmm0, [rip + c_0_22]
    maxss xmm0, [rip + c_neg_0_22]
    minss xmm0, [rip + c_0_22]
    movss [rip + gx_target], xmm0

    # gy = clamp(norm_y * 0.14, -0.14, 0.14)
    mulss xmm1, [rip + c_0_14]
    maxss xmm1, [rip + c_neg_0_14]
    minss xmm1, [rip + c_0_14]
    movss [rip + gy_target], xmm1

    add rsp, 8
    pop rbx
    ret

# ==============================================================================
# handle_input: Non-blocking stdin poll & SGR mouse parser
# ==============================================================================
handle_input:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40

    # pollfd: fd = 0, events = POLLIN (0x0001)
    mov dword ptr [rsp], 0       # fd = 0
    mov word ptr [rsp + 4], 1    # events = POLLIN
    mov word ptr [rsp + 6], 0    # revents = 0

    lea rdi, [rsp]
    mov esi, 1
    xor edx, edx                 # timeout = 0
    call poll

    cmp eax, 0
    jle .Linput_done

    movzx eax, word ptr [rsp + 6]
    test eax, 1                  # POLLIN?
    jz .Linput_done

    # Read stdin
    xor edi, edi                 # fd = 0
    lea rsi, [rip + in_buf]
    mov edx, 4096
    call read

    cmp eax, 0
    jle .Linput_done

    mov r12d, eax                # bytes read
    lea r13, [rip + in_buf]      # current pointer
    lea r14, [r13 + r12]         # end pointer

.Lscan_input:
    cmp r13, r14
    jae .Linput_done

    movzx eax, byte ptr [r13]

    # Check ESC sequence
    cmp al, 0x1b
    jne .Lcheck_regular_key

    # Check if we have at least 3 chars: \033[<
    lea rbx, [r13 + 3]
    cmp rbx, r14
    ja .Lcheck_escape_alone

    cmp byte ptr [r13 + 1], '['
    jne .Lcheck_escape_alone

    cmp byte ptr [r13 + 2], '<'
    je .Lparse_sgr_mouse

    # Arrow key: \033[A, B, C, D
    movzx ecx, byte ptr [r13 + 2]
    cmp cl, 'A'
    je .Lkey_arrow_up
    cmp cl, 'B'
    je .Lkey_arrow_down
    cmp cl, 'C'
    je .Lkey_arrow_right
    cmp cl, 'D'
    je .Lkey_arrow_left
    add r13, 3
    jmp .Lscan_input

.Lkey_arrow_up:
    xorps xmm0, xmm0
    movss xmm1, [rip + c_neg_1_0]
    call set_mouse_gaze
    add r13, 3
    jmp .Lscan_input

.Lkey_arrow_down:
    xorps xmm0, xmm0
    movss xmm1, [rip + c_1_0]
    call set_mouse_gaze
    add r13, 3
    jmp .Lscan_input

.Lkey_arrow_right:
    movss xmm0, [rip + c_1_0]
    xorps xmm1, xmm1
    call set_mouse_gaze
    add r13, 3
    jmp .Lscan_input

.Lkey_arrow_left:
    movss xmm0, [rip + c_neg_1_0]
    xorps xmm1, xmm1
    call set_mouse_gaze
    add r13, 3
    jmp .Lscan_input

.Lcheck_escape_alone:
    # If single escape at end of stream, exit
    cmp r13, r14
    je .Lexit_key
    inc r13
    jmp .Lscan_input

.Lparse_sgr_mouse:
    # \033[<btn;col;row[Mm]
    add r13, 3

    # Parse btn
    xor ecx, ecx
.Lp_btn:
    cmp r13, r14
    jae .Linput_done
    movzx eax, byte ptr [r13]
    cmp al, ';'
    je .Lbtn_fin
    sub al, '0'
    imul ecx, ecx, 10
    movzx eax, al
    add ecx, eax
    inc r13
    jmp .Lp_btn
.Lbtn_fin:
    inc r13                      # skip ';'
    mov r15d, ecx                # r15d = btn

    # Parse col
    xor ecx, ecx
.Lp_col:
    cmp r13, r14
    jae .Linput_done
    movzx eax, byte ptr [r13]
    cmp al, ';'
    je .Lcol_fin
    sub al, '0'
    imul ecx, ecx, 10
    movzx eax, al
    add ecx, eax
    inc r13
    jmp .Lp_col
.Lcol_fin:
    inc r13                      # skip ';'
    mov ebx, ecx                 # ebx = col

    # Parse row
    xor ecx, ecx
.Lp_row:
    cmp r13, r14
    jae .Linput_done
    movzx eax, byte ptr [r13]
    cmp al, 'M'
    je .Lrow_fin_M
    cmp al, 'm'
    je .Lrow_fin_m
    sub al, '0'
    imul ecx, ecx, 10
    movzx eax, al
    add ecx, eax
    inc r13
    jmp .Lp_row

.Lrow_fin_M:
    inc r13
    # Button press or motion (type 'M')
    # r15d = btn, ebx = col (1-based), ecx = row (1-based)
    cmp r15d, 0                  # Left click
    jne .Lcheck_right_click
    call trigger_blink
    jmp .Lupdate_mouse_coords
.Lcheck_right_click:
    cmp r15d, 2                  # Right click
    jne .Lcheck_wheel_up
    call trigger_space_animation
    jmp .Lupdate_mouse_coords
.Lcheck_wheel_up:
    cmp r15d, 64                 # Scroll up
    jne .Lcheck_wheel_down
    xorps xmm0, xmm0
    movss xmm1, [rip + c_neg_0_9]
    call set_mouse_gaze
    jmp .Lscan_input
.Lcheck_wheel_down:
    cmp r15d, 65                 # Scroll down
    jne .Lupdate_mouse_coords
    xorps xmm0, xmm0
    movss xmm1, [rip + c_0_9]
    call set_mouse_gaze
    jmp .Lscan_input

.Lupdate_mouse_coords:
    # norm_x = ((col - 1) / (cols - 1)) * 2.0 - 1.0
    dec ebx
    cvtsi2ss xmm0, ebx
    mov eax, [rip + cols]
    dec eax
    cmp eax, 1
    jge .Lcol_max1
    mov eax, 1
.Lcol_max1:
    cvtsi2ss xmm2, eax
    divss xmm0, xmm2
    mulss xmm0, [rip + c_2_0]
    subss xmm0, [rip + c_1_0]

    # norm_y = ((row - 1) / (rows - 1)) * 2.0 - 1.0
    dec ecx
    cvtsi2ss xmm1, ecx
    mov eax, [rip + rows]
    dec eax
    cmp eax, 1
    jge .Lrow_max1
    mov eax, 1
.Lrow_max1:
    cvtsi2ss xmm2, eax
    divss xmm1, xmm2
    mulss xmm1, [rip + c_2_0]
    subss xmm1, [rip + c_1_0]

    call set_mouse_gaze
    jmp .Lscan_input

.Lrow_fin_m:
    inc r13
    # Mouse release event - still update gaze
    jmp .Lupdate_mouse_coords

.Lcheck_regular_key:
    # Quit: 'q', 'Q', Ctrl+C (0x03)
    cmp al, 'q'
    je .Lexit_key
    cmp al, 'Q'
    je .Lexit_key
    cmp al, 0x03
    je .Lexit_key

    # Space or Enter
    cmp al, ' '
    je .Lkey_space
    cmp al, '\r'
    je .Lkey_space
    cmp al, '\n'
    je .Lkey_space

    # Manual blink: 'b', 'B'
    cmp al, 'b'
    je .Lkey_blink
    cmp al, 'B'
    je .Lkey_blink

    inc r13
    jmp .Lscan_input

.Lkey_space:
    call trigger_space_animation
    inc r13
    jmp .Lscan_input

.Lkey_blink:
    call trigger_blink
    inc r13
    jmp .Lscan_input

.Lexit_key:
    mov dword ptr [rip + running], 0
    inc r13
    jmp .Linput_done

.Linput_done:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

# ==============================================================================
# controller_update: Autonomic Saccades, Blinks, Tremor & Pupillary Hippus
# ==============================================================================
controller_update:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 56

    call get_time_sec
    movsd [rsp], xmm0            # now (double)

    # 1. Idle mouse timeout (> 2.5s)
    cmp dword ptr [rip + mouse_control], 0
    jz .Lcheck_saccade
    movsd xmm1, [rip + last_mouse_time]
    movsd xmm2, [rsp]
    subsd xmm2, xmm1             # now - last_mouse_time
    ucomisd xmm2, [rip + c_2_5_d]
    jbe .Lcheck_saccade

    # Re-enable autonomous saccades
    mov dword ptr [rip + mouse_control], 0
    movss xmm0, [rip + c_0_6]
    movss xmm1, [rip + c_1_8]
    call rand_uniform
    cvtss2sd xmm0, xmm0
    addsd xmm0, [rsp]
    movsd [rip + next_saccade_time], xmm0

.Lcheck_saccade:
    cmp dword ptr [rip + mouse_control], 0
    jnz .Lcheck_blink
    movsd xmm0, [rsp]
    ucomisd xmm0, [rip + next_saccade_time]
    jbe .Lcheck_microsaccade

    # Pick gx_target from {-0.20, -0.10, 0.0, 0.10, 0.20}
    call rand64
    xor edx, edx
    mov ecx, 5
    div ecx
    lea rax, [rip + saccade_gx_choices]
    movss xmm0, [rax + rdx * 4]
    movss [rip + gx_target], xmm0

    # Pick gy_target from {-0.06, -0.02, 0.0, 0.03, 0.06}
    call rand64
    xor edx, edx
    mov ecx, 5
    div ecx
    lea rax, [rip + saccade_gy_choices]
    movss xmm0, [rax + rdx * 4]
    movss [rip + gy_target], xmm0

    movss xmm0, [rip + c_1_2]
    movss xmm1, [rip + c_3_2]
    call rand_uniform
    cvtss2sd xmm0, xmm0
    addsd xmm0, [rsp]
    movsd [rip + next_saccade_time], xmm0

.Lcheck_microsaccade:
    cmp dword ptr [rip + is_blinking], 0
    jnz .Lcheck_blink
    movsd xmm0, [rsp]
    ucomisd xmm0, [rip + next_microsaccade_time]
    jbe .Lcheck_blink

    movss xmm0, [rip + c_neg_0_015]
    movss xmm1, [rip + c_0_015]
    call rand_uniform
    addss xmm0, [rip + gx_target]
    movss [rip + gx_target], xmm0

    movss xmm0, [rip + c_neg_0_009]
    movss xmm1, [rip + c_0_009]
    call rand_uniform
    addss xmm0, [rip + gy_target]
    movss [rip + gy_target], xmm0

    movss xmm0, [rip + c_0_8]
    movss xmm1, [rip + c_1_8]
    call rand_uniform
    cvtss2sd xmm0, xmm0
    addsd xmm0, [rsp]
    movsd [rip + next_microsaccade_time], xmm0

.Lcheck_blink:
    movsd xmm0, [rsp]
    ucomisd xmm0, [rip + next_blink_time]
    jbe .Lhandle_blink_curve

    call trigger_blink
    movss xmm0, [rip + c_3_0]
    movss xmm1, [rip + c_6_0]
    call rand_uniform
    cvtss2sd xmm0, xmm0
    addsd xmm0, [rsp]
    movsd [rip + next_blink_time], xmm0

.Lhandle_blink_curve:
    cmp dword ptr [rip + is_blinking], 0
    jz .Lnot_blinking

    movsd xmm0, [rsp]
    subsd xmm0, [rip + blink_start_time]
    mulsd xmm0, [rip + c_1000_d]   # elapsed ms in xmm0

    ucomisd xmm0, [rip + c_85_d]
    ja .Lblink_p2
    # elapsed < 85: ou = 1.0 - (t * t)
    divsd xmm0, [rip + c_85_d]
    cvtsd2ss xmm1, xmm0
    mulss xmm1, xmm1
    movss xmm0, [rip + c_1_0]
    subss xmm0, xmm1
    movss [rip + ou], xmm0
    jmp .Lsmooth_gaze

.Lblink_p2:
    ucomisd xmm0, [rip + c_125_d]
    ja .Lblink_p3
    # 85 <= elapsed < 125: ou = 0.0
    xorps xmm0, xmm0
    movss [rip + ou], xmm0
    jmp .Lsmooth_gaze

.Lblink_p3:
    ucomisd xmm0, [rip + c_240_d]
    ja .Lblink_finish
    # 125 <= elapsed < 240: t = (elapsed - 125) / 115; ou = t * (2 - t)
    subsd xmm0, [rip + c_125_d]
    divsd xmm0, [rip + c_115_d]
    cvtsd2ss xmm1, xmm0          # t
    movss xmm2, [rip + c_2_0]
    subss xmm2, xmm1             # 2.0 - t
    mulss xmm1, xmm2             # t * (2.0 - t)
    movss [rip + ou], xmm1
    jmp .Lsmooth_gaze

.Lblink_finish:
    movss xmm0, [rip + c_1_0]
    movss [rip + ou], xmm0
    mov dword ptr [rip + is_blinking], 0
    movsd xmm0, [rsp]
    movsd [rip + last_blink_end_time], xmm0
    jmp .Lsmooth_gaze

.Lnot_blinking:
    movss xmm0, [rip + c_1_0]
    movss [rip + ou], xmm0

.Lsmooth_gaze:
    # gx_smooth += (gx_target - gx_smooth) * 0.22
    movss xmm0, [rip + gx_target]
    subss xmm0, [rip + gx_smooth]
    mulss xmm0, [rip + c_0_22]
    addss xmm0, [rip + gx_smooth]
    movss [rip + gx_smooth], xmm0

    # gy_smooth += (gy_target - gy_smooth) * 0.22
    movss xmm0, [rip + gy_target]
    subss xmm0, [rip + gy_smooth]
    mulss xmm0, [rip + c_0_22]
    addss xmm0, [rip + gy_smooth]
    movss [rip + gy_smooth], xmm0

    # Physiological tremor
    # tremor_x = sinf(now * 34.0) * 0.0022 + cosf(now * 48.0) * 0.0014
    cvtsd2ss xmm0, [rsp]
    movss [rsp + 16], xmm0       # now_f
    mulss xmm0, [rip + c_34_0]
    call sinf
    mulss xmm0, [rip + c_0_0022]
    movss [rsp + 20], xmm0

    movss xmm0, [rsp + 16]
    mulss xmm0, [rip + c_48_0]
    call cosf
    mulss xmm0, [rip + c_0_0014]
    addss xmm0, [rsp + 20]
    addss xmm0, [rip + gx_smooth]
    movss [rip + gx], xmm0

    # tremor_y = cosf(now * 30.0) * 0.0018 + sinf(now * 42.0) * 0.0010
    movss xmm0, [rsp + 16]
    mulss xmm0, [rip + c_30_0]
    call cosf
    mulss xmm0, [rip + c_0_0018]
    movss [rsp + 20], xmm0

    movss xmm0, [rsp + 16]
    mulss xmm0, [rip + c_42_0]
    call sinf
    mulss xmm0, [rip + c_0_0010]
    addss xmm0, [rsp + 20]
    addss xmm0, [rip + gy_smooth]
    movss [rip + gy], xmm0

    # Pupillary hippus: sinf(now * 1.5) * 0.012 + sinf(now * 3.2 + 0.8) * 0.006
    movss xmm0, [rsp + 16]
    mulss xmm0, [rip + c_1_5]
    call sinf
    mulss xmm0, [rip + c_0_012]
    movss [rsp + 20], xmm0

    movss xmm0, [rsp + 16]
    mulss xmm0, [rip + c_3_2]
    addss xmm0, [rip + c_0_8]
    call sinf
    mulss xmm0, [rip + c_0_006]
    addss xmm0, [rsp + 20]
    movss [rsp + 24], xmm0       # hippus

    # Post-blink pupil reflex: 0.022 * max(0.0, 1.0 - (now - last_blink_end_time) / 0.7)
    movsd xmm0, [rsp]
    subsd xmm0, [rip + last_blink_end_time]
    cvtsd2ss xmm0, xmm0
    divss xmm0, [rip + c_0_7]
    movss xmm1, [rip + c_1_0]
    subss xmm1, xmm0
    maxss xmm1, [rip + c_0_0]
    mulss xmm1, [rip + c_0_022]

    # pupil_radius = 0.125 + hippus + post_blink
    addss xmm1, [rsp + 24]
    addss xmm1, [rip + c_0_125]
    movss [rip + pupil_radius], xmm1

    add rsp, 56
    pop rbx
    leave
    ret

# ==============================================================================
# render_frame: Mathematical TrueColor ASCII Rasterizer
# ==============================================================================
render_frame:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    # Allocate stack space for frame variables (176 bytes, 16-byte aligned)
    sub rsp, 176

    # 1. Compute span and aspect coordinates
    # a_phys = cols / (rows * 2.05)
    cvtsi2ss xmm0, dword ptr [rip + cols]
    cvtsi2ss xmm1, dword ptr [rip + rows]
    mulss xmm1, [rip + c_char_aspect]
    divss xmm0, xmm1             # a_phys in xmm0
    movss [rsp], xmm0            # [rsp] = a_phys

    # base_factor = 0.52 / scale
    movss xmm1, [rip + c_0_52]
    divss xmm1, [rip + c_scale]  # base_factor in xmm1

    # if (a_phys >= 1.0)
    ucomiss xmm0, [rip + c_1_0]
    jb .Lvert_aspect

    # v_span = base_factor * char_aspect
    # u_span = v_span * a_phys
    mulss xmm1, [rip + c_char_aspect] # v_span
    movss [rsp + 8], xmm1        # v_span
    mulss xmm1, xmm0             # u_span
    movss [rsp + 4], xmm1        # u_span
    jmp .Lcalc_steps

.Lvert_aspect:
    # u_span = base_factor * char_aspect
    # v_span = u_span / a_phys
    mulss xmm1, [rip + c_char_aspect] # u_span
    movss [rsp + 4], xmm1        # u_span
    divss xmm1, xmm0             # v_span
    movss [rsp + 8], xmm1        # v_span

.Lcalc_steps:
    # du_step = 2.0 * u_span / (cols > 1 ? cols - 1 : 1)
    movss xmm0, [rsp + 4]
    mulss xmm0, [rip + c_2_0]
    mov eax, [rip + cols]
    dec eax
    cmp eax, 1
    jge .Lcol_max2
    mov eax, 1
.Lcol_max2:
    cvtsi2ss xmm1, eax
    divss xmm0, xmm1
    movss [rsp + 12], xmm0       # du_step

    # dv_step = 2.0 * v_span / (rows > 1 ? rows - 1 : 1)
    movss xmm0, [rsp + 8]
    mulss xmm0, [rip + c_2_0]
    mov eax, [rip + rows]
    dec eax
    cmp eax, 1
    jge .Lrow_max2
    mov eax, 1
.Lrow_max2:
    cvtsi2ss xmm1, eax
    divss xmm0, xmm1
    movss [rsp + 16], xmm0       # dv_step

    # Precompute frame invariants:
    # cos_theta = max(0.65, cosf(gx * 1.6))
    movss xmm0, [rip + gx]
    mulss xmm0, [rip + c_1_6]
    call cosf
    maxss xmm0, [rip + c_0_65]
    movss [rsp + 20], xmm0       # cos_theta

    # glint_cx = gx * 0.32 - 0.055
    movss xmm0, [rip + gx]
    mulss xmm0, [rip + c_0_32]
    subss xmm0, [rip + c_0_055]
    movss [rsp + 24], xmm0       # glint_cx

    # glint_cy = gy * 0.32 + 0.065
    movss xmm0, [rip + gy]
    mulss xmm0, [rip + c_0_32]
    addss xmm0, [rip + c_0_065]
    movss [rsp + 28], xmm0       # glint_cy

    # cr_pos = 0.14 * (0.65 + 0.35 * ou)
    movss xmm0, [rip + ou]
    mulss xmm0, [rip + c_0_35]
    addss xmm0, [rip + c_0_65]
    mulss xmm0, [rip + c_0_14]
    movss [rsp + 32], xmm0       # cr_pos

    # lid_lag = gy * 0.20 * ou
    movss xmm0, [rip + gy]
    mulss xmm0, [rip + c_0_20]
    mulss xmm0, [rip + ou]
    movss [rsp + 36], xmm0       # lid_lag

    # Initialize buffer write pointer in r12
    lea r12, [rip + out_buf]

    # Home cursor: "\033[H"
    mov word ptr [r12], 0x5b1b   # "\033["
    mov byte ptr [r12 + 2], 'H'
    add r12, 3

    # Reset delta color tracking
    mov dword ptr [rsp + 40], -1  # last_r
    mov dword ptr [rsp + 44], -1  # last_g
    mov dword ptr [rsp + 48], -1  # last_b

    # Loop rows: r13d from 0 to rows - 1
    xor r13d, r13d

.Lrow_loop:
    mov eax, [rip + rows]
    cmp r13d, eax
    jae .Lend_rows

    # v = -v_span + r * dv_step
    cvtsi2ss xmm0, r13d
    mulss xmm0, [rsp + 16]       # r * dv_step
    subss xmm0, [rsp + 8]        # - v_span
    movss [rsp + 52], xmm0       # v

    # Loop columns: r14d from 0 to cols - 1
    xor r14d, r14d

.Lcol_loop:
    mov eax, [rip + cols]
    cmp r14d, eax
    jae .Lend_cols

    # u = -u_span + c * du_step
    cvtsi2ss xmm0, r14d
    mulss xmm0, [rsp + 12]       # c * du_step
    subss xmm0, [rsp + 4]        # - u_span
    movss [rsp + 56], xmm0       # u

    # Clear per-cell masks
    mov dword ptr [rsp + 124], 0 # dist_iris
    mov dword ptr [rsp + 128], 0 # in_iris
    mov dword ptr [rsp + 132], 0 # in_pupil
    mov dword ptr [rsp + 136], 0 # glint
    mov dword ptr [rsp + 140], 0 # vessel_mask
    mov dword ptr [rsp + 144], 0 # caruncle
    mov dword ptr [rsp + 148], 0 # total_lash
    mov dword ptr [rsp + 152], 0 # lashline
    mov dword ptr [rsp + 156], 0 # crease
    mov dword ptr [rsp + 160], 0 # meniscus

    # --------------------------------------------------------------------------
    # Cell Math Shader
    # --------------------------------------------------------------------------
    # s = u / eye_w
    movss xmm1, xmm0
    divss xmm1, [rip + c_eye_w]
    movss [rsp + 60], xmm1       # s

    # arch = max(0.0, 1.0 - s * s)
    movss xmm2, [rip + c_1_0]
    movaps xmm3, xmm1
    mulss xmm3, xmm3
    subss xmm2, xmm3
    maxss xmm2, [rip + c_0_0]
    movss [rsp + 64], xmm2       # arch

    # y_up_open = 0.46 * arch * (1.0 - 0.15 * s) + 0.02 * s + lid_lag
    movss xmm3, [rip + c_1_0]
    movaps xmm4, xmm1
    mulss xmm4, [rip + c_0_15]
    subss xmm3, xmm4             # 1.0 - 0.15 * s
    mulss xmm3, xmm2             # arch * (...)
    mulss xmm3, [rip + c_0_46]   # 0.46 * arch * (...)
    movaps xmm4, xmm1
    mulss xmm4, [rip + c_0_02]   # 0.02 * s
    addss xmm3, xmm4
    addss xmm3, [rsp + 36]       # + lid_lag
    movss [rsp + 68], xmm3       # y_up_open

    # y_dn_open = -0.28 * arch * (1.0 + 0.10 * s) + 0.01 * s + lid_lag * 0.65
    movss xmm4, [rip + c_1_0]
    movaps xmm5, xmm1
    mulss xmm5, [rip + c_0_10]
    addss xmm4, xmm5             # 1.0 + 0.10 * s
    mulss xmm4, xmm2             # arch * (...)
    mulss xmm4, [rip + c_neg_0_28]
    movaps xmm5, xmm1
    mulss xmm5, [rip + c_0_01]
    addss xmm4, xmm5
    movss xmm5, [rsp + 36]
    mulss xmm5, [rip + c_0_65]
    addss xmm4, xmm5             # y_dn_open
    movss [rsp + 72], xmm4

    # y_seam = -0.06 * arch + 0.01 * s + lid_lag * 0.50
    movaps xmm5, xmm2
    mulss xmm5, [rip + c_neg_0_06]
    movaps xmm6, xmm1
    mulss xmm6, [rip + c_0_01]
    addss xmm5, xmm6
    movss xmm6, [rsp + 36]
    mulss xmm6, [rip + c_0_50]
    addss xmm5, xmm6             # y_seam
    movss [rsp + 76], xmm5

    # y_up = y_up_open * ou + y_seam * (1.0 - ou)
    movss xmm6, [rsp + 68]
    mulss xmm6, [rip + ou]
    movss xmm7, [rip + c_1_0]
    subss xmm7, [rip + ou]
    movaps xmm8, xmm7
    mulss xmm8, xmm5
    addss xmm6, xmm8             # y_up in xmm6
    movss [rsp + 80], xmm6

    # y_dn = y_dn_open * (0.2 + 0.8 * ou) + (y_seam - 0.01) * (1.0 - ou)
    movss xmm8, [rip + ou]
    mulss xmm8, [rip + c_0_8]
    addss xmm8, [rip + c_0_2]
    mulss xmm8, xmm4             # y_dn_open * (...)
    movaps xmm9, xmm5
    subss xmm9, [rip + c_0_01]
    mulss xmm9, xmm7             # (y_seam - 0.01) * (1.0 - ou)
    addss xmm8, xmm9             # y_dn in xmm8
    movss [rsp + 84], xmm8

    # du = v - y_up, dl = y_dn - v
    movss xmm9, [rsp + 52]       # v
    subss xmm9, xmm6             # du in xmm9
    movss [rsp + 88], xmm9
    movss xmm10, xmm8
    subss xmm10, [rsp + 52]      # dl in xmm10
    movss [rsp + 92], xmm10

    # lid_mid = 0.5 * (y_up + y_dn)
    movaps xmm11, xmm6
    addss xmm11, xmm8
    mulss xmm11, [rip + c_0_5]   # lid_mid

    # upper = (v >= lid_mid)
    movss xmm0, [rsp + 52]
    ucomiss xmm0, xmm11
    setae al
    movzx r15d, al               # r15d = upper (1 or 0)

    # in_eye_horiz = (fabs(s) <= 1.0)
    movss xmm0, [rsp + 60]       # s
    andps xmm0, [rip + c_abs_mask]
    ucomiss xmm0, [rip + c_1_0]
    setbe bl
    movzx ebx, bl                # ebx = in_eye_horiz (1 or 0)

    # inside_eye = in_eye_horiz & (v < y_up) & (v > y_dn) & (y_up > y_dn + 0.02) & (ou > 0.04)
    xor edx, edx
    test ebx, ebx
    jz .Lnot_inside_eye
    movss xmm0, [rsp + 52]       # v
    ucomiss xmm0, [rsp + 80]     # v < y_up
    jae .Lnot_inside_eye
    ucomiss xmm0, [rsp + 84]     # v > y_dn
    jbe .Lnot_inside_eye
    movss xmm1, [rsp + 84]
    addss xmm1, [rip + c_0_02]
    movss xmm2, [rsp + 80]
    ucomiss xmm2, xmm1           # y_up > y_dn + 0.02
    jbe .Lnot_inside_eye
    movss xmm3, [rip + ou]
    ucomiss xmm3, [rip + c_0_04] # ou > 0.04
    jbe .Lnot_inside_eye
    mov edx, 1
.Lnot_inside_eye:
    mov [rsp + 96], edx          # inside_eye (1 or 0)

    # --------------------------------------------------------------------------
    # Base Skin Tone & Lighting
    # --------------------------------------------------------------------------
    # tx_skin = fast_noise2d(u * 5.0, v * 5.0, 10)
    movss xmm0, [rsp + 56]
    mulss xmm0, [rip + c_5_0]
    movss xmm1, [rsp + 52]
    mulss xmm1, [rip + c_5_0]
    mov edi, 10
    call fast_noise2d
    mulss xmm0, [rip + c_0_24]
    addss xmm0, [rip + c_0_88]   # skin_mult in xmm0

    # Base color = skin_mult * [0.62, 0.40, 0.29]
    movss xmm1, [rip + c_skin_base_r]
    mulss xmm1, xmm0
    movss [rsp + 100], xmm1      # col_r
    movss xmm2, [rip + c_skin_base_g]
    mulss xmm2, xmm0
    movss [rsp + 104], xmm2      # col_g
    movss xmm3, [rip + c_skin_base_b]
    mulss xmm3, xmm0
    movss [rsp + 108], xmm3      # col_b

    # Lighting vignette: dist_ctr = sqrt((u * 0.8)^2 + (v * 1.1)^2)
    movss xmm0, [rsp + 56]
    mulss xmm0, [rip + c_0_8]
    mulss xmm0, xmm0
    movss xmm1, [rsp + 52]
    mulss xmm1, [rip + c_1_1]
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0            # dist_ctr
    movss xmm2, xmm0             # x
    movss xmm0, [rip + c_0_3]    # e0
    movss xmm1, [rip + c_1_15]   # e1
    call ss_func
    mulss xmm0, [rip + c_0_32]
    movss xmm1, [rip + c_1_06]
    subss xmm1, xmm0             # lighting in xmm1
    MUL_MEM [rsp + 100], xmm1
    MUL_MEM [rsp + 104], xmm1
    MUL_MEM [rsp + 108], xmm1

    # Crease & fold highlight (only if upper && in_eye_horiz)
    xorps xmm10, xmm10           # crease = 0
    test r15d, r15d
    jz .Lcheck_lower_fold
    test ebx, ebx
    jz .Lcheck_lower_fold

    # crease = exp(-((du - cr_pos) / 0.028)^2)
    movss xmm0, [rsp + 88]       # du
    subss xmm0, [rsp + 32]       # du - cr_pos
    divss xmm0, [rip + c_0_028]
    mulss xmm0, xmm0
    xorps xmm0, [rip + c_sign_mask]
    call expf
    movaps xmm10, xmm0           # crease in xmm10
    movss [rsp + 156], xmm10     # save crease
    movaps xmm1, xmm10
    mulss xmm1, [rip + c_0_24]
    SUB_MEM [rsp + 100], xmm1    # col_r -= crease * 0.24
    movaps xmm1, xmm10
    mulss xmm1, [rip + c_0_18]
    SUB_MEM [rsp + 104], xmm1    # col_g -= crease * 0.18
    movaps xmm1, xmm10
    mulss xmm1, [rip + c_0_14]
    SUB_MEM [rsp + 108], xmm1    # col_b -= crease * 0.14

    # fold_hl = exp(-((du - (cr_pos + 0.08)) / 0.05)^2)
    movss xmm0, [rsp + 88]
    movss xmm1, [rsp + 32]
    addss xmm1, [rip + c_0_08]
    subss xmm0, xmm1
    divss xmm0, [rip + c_0_05]
    mulss xmm0, xmm0
    xorps xmm0, [rip + c_sign_mask]
    call expf
    movaps xmm1, xmm0
    mulss xmm1, [rip + c_0_10]
    ADD_MEM [rsp + 100], xmm1
    movaps xmm1, xmm0
    mulss xmm1, [rip + c_0_07]
    ADD_MEM [rsp + 104], xmm1
    movaps xmm1, xmm0
    mulss xmm1, [rip + c_0_05]
    ADD_MEM [rsp + 108], xmm1

.Lcheck_lower_fold:
    # Lower eyelid fold, waterline & meniscus (only if !upper && in_eye_horiz)
    xorps xmm11, xmm11           # meniscus = 0
    test r15d, r15d
    jnz .Lcheck_eyeliner
    test ebx, ebx
    jz .Lcheck_eyeliner

    # lower_fold = exp(-((dl - 0.10) / 0.05)^2)
    movss xmm0, [rsp + 92]       # dl
    subss xmm0, [rip + c_0_10]
    divss xmm0, [rip + c_0_05]
    mulss xmm0, xmm0
    xorps xmm0, [rip + c_sign_mask]
    call expf
    movaps xmm1, xmm0
    mulss xmm1, [rip + c_0_13]
    SUB_MEM [rsp + 100], xmm1
    movaps xmm1, xmm0
    mulss xmm1, [rip + c_0_10]
    SUB_MEM [rsp + 104], xmm1
    movaps xmm1, xmm0
    mulss xmm1, [rip + c_0_08]
    SUB_MEM [rsp + 108], xmm1

    # wl = exp(-((dl - 0.014) / 0.007)^2) * (0.3 + 0.7 * ou)
    movss xmm0, [rsp + 92]
    subss xmm0, [rip + c_0_014]
    divss xmm0, [rip + c_0_007]
    mulss xmm0, xmm0
    xorps xmm0, [rip + c_sign_mask]
    call expf
    movss xmm1, [rip + ou]
    mulss xmm1, [rip + c_0_7]
    addss xmm1, [rip + c_0_3]
    mulss xmm0, xmm1             # wl in xmm0

    ucomiss xmm0, [rip + c_0_10]
    jbe .Lcalc_meniscus
    # Blend waterline pink
    mulss xmm0, [rip + c_0_75]   # wblend in xmm0
    movss xmm1, [rip + c_1_0]
    subss xmm1, xmm0             # 1.0 - wblend

    movss xmm2, [rsp + 100]
    mulss xmm2, xmm1
    movss xmm3, [rip + c_0_76]
    mulss xmm3, xmm0
    addss xmm2, xmm3
    movss [rsp + 100], xmm2

    movss xmm2, [rsp + 104]
    mulss xmm2, xmm1
    movss xmm3, [rip + c_0_34]
    mulss xmm3, xmm0
    addss xmm2, xmm3
    movss [rsp + 104], xmm2

    movss xmm2, [rsp + 108]
    mulss xmm2, xmm1
    movss xmm3, [rip + c_0_30]
    mulss xmm3, xmm0
    addss xmm2, xmm3
    movss [rsp + 108], xmm2

.Lcalc_meniscus:
    # meniscus = exp(-((dl - 0.009) / 0.004)^2) * ou
    movss xmm0, [rsp + 92]
    subss xmm0, [rip + c_0_009]
    divss xmm0, [rip + c_0_004]
    mulss xmm0, xmm0
    xorps xmm0, [rip + c_sign_mask]
    call expf
    mulss xmm0, [rip + ou]
    movaps xmm11, xmm0           # meniscus in xmm11
    movss [rsp + 160], xmm11     # save meniscus
    movaps xmm1, xmm11
    mulss xmm1, [rip + c_0_45]
    ADD_MEM [rsp + 100], xmm1
    movaps xmm1, xmm11
    mulss xmm1, [rip + c_0_40]
    ADD_MEM [rsp + 104], xmm1
    movaps xmm1, xmm11
    mulss xmm1, [rip + c_0_38]
    ADD_MEM [rsp + 108], xmm1

.Lcheck_eyeliner:
    # Lashline (dark eyeliner)
    xorps xmm12, xmm12           # lashline = 0
    test ebx, ebx
    jz .Lcheck_inside_eye

    test r15d, r15d
    jz .Llashline_dn
    # line_up = exp(-(du / 0.014)^2)
    movss xmm0, [rsp + 88]
    divss xmm0, [rip + c_0_014]
    mulss xmm0, xmm0
    xorps xmm0, [rip + c_sign_mask]
    call expf
    movaps xmm12, xmm0
    jmp .Lapply_eyeliner

.Llashline_dn:
    # line_dn = exp(-(dl / 0.010)^2)
    movss xmm0, [rsp + 92]
    divss xmm0, [rip + c_0_010]
    mulss xmm0, xmm0
    xorps xmm0, [rip + c_sign_mask]
    call expf
    movaps xmm12, xmm0

.Lapply_eyeliner:
    movss [rsp + 152], xmm12     # save lashline
    movaps xmm1, xmm12
    mulss xmm1, [rip + c_0_48]
    SUB_MEM [rsp + 100], xmm1
    movaps xmm1, xmm12
    mulss xmm1, [rip + c_0_36]
    SUB_MEM [rsp + 104], xmm1
    movaps xmm1, xmm12
    mulss xmm1, [rip + c_0_28]
    SUB_MEM [rsp + 108], xmm1

.Lcheck_inside_eye:
    # Variables for character mapping
    xorps xmm13, xmm13           # glint = 0
    xorps xmm14, xmm14           # vessel_mask = 0
    xorps xmm15, xmm15           # caruncle = 0
    xor eax, eax                 # in_pupil = 0
    xor ecx, ecx                 # in_iris = 0
    xorps xmm7, xmm7             # dist_iris = 0

    cmp dword ptr [rsp + 96], 0  # inside_eye?
    jz .Lcheck_eyelashes

    # --------------------------------------------------------------------------
    # Sclera, Micro-Vessels, Caruncle & 3D Iris / Pupil
    # --------------------------------------------------------------------------
    # canthus = ss(0.38, 0.95, fabs(s))
    movss xmm2, [rsp + 60]
    andps xmm2, [rip + c_abs_mask]
    movss xmm0, [rip + c_0_38]
    movss xmm1, [rip + c_0_95]
    call ss_func
    movss [rsp + 112], xmm0      # canthus

    # caruncle = ss(-0.55, -0.92, s) * ss(0.20, 0.0, fabs(v - y_seam))
    movss xmm2, [rsp + 60]       # s
    movss xmm0, [rip + c_neg_0_55]
    movss xmm1, [rip + c_neg_0_92]
    call ss_func
    movss [rsp + 116], xmm0

    movss xmm2, [rsp + 52]       # v
    subss xmm2, [rsp + 76]       # v - y_seam
    andps xmm2, [rip + c_abs_mask]
    movss xmm0, [rip + c_0_20]
    xorps xmm1, xmm1             # 0.0
    call ss_func
    mulss xmm0, [rsp + 116]
    movaps xmm15, xmm0           # caruncle in xmm15
    movss [rsp + 144], xmm15     # save caruncle

    # tx_fibers = fast_noise2d(u * 25.0, v * 25.0, 30)
    movss xmm0, [rsp + 56]
    mulss xmm0, [rip + c_25_0]
    movss xmm1, [rsp + 52]
    mulss xmm1, [rip + c_25_0]
    mov edi, 30
    call fast_noise2d
    movss [rsp + 116], xmm0      # tx_fibers

    # vessel_uv = u * 48.0 + sinf(v * 32.0) * 2.2 + tx_fibers * 3.5
    movss xmm0, [rsp + 52]
    mulss xmm0, [rip + c_32_0]
    call sinf
    mulss xmm0, [rip + c_2_2]
    movss xmm1, [rsp + 56]
    mulss xmm1, [rip + c_48_0]
    addss xmm0, xmm1
    movss xmm2, [rsp + 116]
    mulss xmm2, [rip + c_3_5]
    addss xmm0, xmm2             # vessel_uv

    call sinf
    divss xmm0, [rip + c_0_13]
    mulss xmm0, xmm0
    xorps xmm0, [rip + c_sign_mask]
    call expf                    # vessel_line in xmm0

    movss [rsp + 120], xmm0
    movss xmm2, [rsp + 60]
    andps xmm2, [rip + c_abs_mask]
    movss xmm0, [rip + c_0_35]
    movss xmm1, [rip + c_0_88]
    call ss_func
    mulss xmm0, [rip + c_0_42]
    mulss xmm0, [rsp + 120]
    movaps xmm14, xmm0           # vessel_mask in xmm14
    movss [rsp + 140], xmm14     # save vessel_mask

    # Sclera color blending
    # base: [0.94, 0.92, 0.90]
    movss xmm0, [rsp + 112]      # canthus
    mulss xmm0, [rip + c_0_65]   # canthus * 0.65
    movss xmm1, [rip + c_1_0]
    subss xmm1, xmm0

    movss xmm2, [rip + c_0_94]
    mulss xmm2, xmm1
    movss xmm3, [rip + c_0_86]
    mulss xmm3, xmm0
    addss xmm2, xmm3             # sclera_r

    movss xmm4, [rip + c_0_92]
    mulss xmm4, xmm1
    movss xmm5, [rip + c_0_44]
    mulss xmm5, xmm0
    addss xmm4, xmm5             # sclera_g

    movss xmm6, [rip + c_0_90]
    mulss xmm6, xmm1
    movss xmm7, [rip + c_0_42]
    mulss xmm7, xmm0
    addss xmm6, xmm7             # sclera_b

    # Blend vessel
    movss xmm0, [rip + c_1_0]
    subss xmm0, xmm14
    mulss xmm2, xmm0
    movss xmm1, [rip + c_0_76]
    mulss xmm1, xmm14
    addss xmm2, xmm1

    mulss xmm4, xmm0
    movss xmm1, [rip + c_0_28]
    mulss xmm1, xmm14
    addss xmm4, xmm1

    mulss xmm6, xmm0
    mulss xmm1, xmm14
    addss xmm6, xmm1

    # Caruncle override
    ucomiss xmm15, [rip + c_0_15]
    jbe .Lapply_sclera_detail
    mulss xmm2, [rip + c_0_3]
    addss xmm2, [rip + c_0_588]  # 0.84 * 0.7
    mulss xmm4, [rip + c_0_3]
    addss xmm4, [rip + c_0_294]  # 0.42 * 0.7
    mulss xmm6, [rip + c_0_3]
    addss xmm6, [rip + c_0_280]  # 0.40 * 0.7

.Lapply_sclera_detail:
    movss [rsp + 100], xmm2      # eye_r
    movss [rsp + 104], xmm4      # eye_g
    movss [rsp + 108], xmm6      # eye_b

    # tx_detail = fast_noise2d(u * 12.0, v * 12.0, 20)
    movss xmm0, [rsp + 56]
    mulss xmm0, [rip + c_12_0]
    movss xmm1, [rsp + 52]
    mulss xmm1, [rip + c_12_0]
    mov edi, 20
    call fast_noise2d
    mulss xmm0, [rip + c_0_16]
    addss xmm0, [rip + c_0_92]
    MUL_MEM [rsp + 100], xmm0
    MUL_MEM [rsp + 104], xmm0
    MUL_MEM [rsp + 108], xmm0

    # Upper lid shadow: ss(0.0, 0.19, y_up - v) * upper
    movss xmm3, [rip + c_1_0]
    test r15d, r15d
    jz .Lshadow_done
    movss xmm2, [rsp + 80]       # y_up
    subss xmm2, [rsp + 52]       # y_up - v
    xorps xmm0, xmm0
    movss xmm1, [rip + c_0_19]
    call ss_func
    mulss xmm0, [rip + c_0_52]
    addss xmm0, [rip + c_0_48]   # shadow_mult
    movaps xmm3, xmm0
.Lshadow_done:
    movss [rsp + 120], xmm3      # shadow_mult
    MUL_MEM [rsp + 100], xmm3
    MUL_MEM [rsp + 104], xmm3
    MUL_MEM [rsp + 108], xmm3

    # 3D Iris & Pupil distance
    # u_dist = (u - gx) / cos_theta
    movss xmm0, [rsp + 56]
    subss xmm0, [rip + gx]
    divss xmm0, [rsp + 20]       # u_dist
    mulss xmm0, xmm0

    # v_dist = (v - gy) * 1.05
    movss xmm1, [rsp + 52]
    subss xmm1, [rip + gy]
    mulss xmm1, [rip + c_1_05]
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0            # dist_iris in xmm0
    movaps xmm7, xmm0
    movss [rsp + 124], xmm7      # save dist_iris

    # in_iris = (dist_iris < 0.34)
    ucomiss xmm7, [rip + c_0_34]
    jae .Lcheck_pupil_boundary
    mov dword ptr [rsp + 128], 1 # in_iris = 1

    # in_pupil = (dist_iris < pupil_r)
    movss xmm1, [rip + pupil_radius]
    ucomiss xmm7, xmm1
    jae .Lrender_iris_stroma
    mov dword ptr [rsp + 132], 1 # in_pupil = 1

    # Pupil color: [0.015, 0.015, 0.015]
    movss xmm2, [rip + c_0_015]
    movss [rsp + 100], xmm2
    movss [rsp + 104], xmm2
    movss [rsp + 108], xmm2
    jmp .Lrender_catchlights

.Lrender_iris_stroma:
    # Collarette & Limbal Ring & Sphincter
    # iris_norm = dist_iris / 0.34
    movaps xmm0, xmm7
    divss xmm0, [rip + c_0_34]
    movss [rsp + 112], xmm0      # iris_norm

    # collarette = exp(-((iris_norm - 0.42) / 0.14)^2)
    subss xmm0, [rip + c_0_42]
    divss xmm0, [rip + c_0_14]
    mulss xmm0, xmm0
    xorps xmm0, [rip + c_sign_mask]
    call expf                    # collarette in xmm0
    mulss xmm0, [rip + c_0_6]    # collarette * 0.6
    movss xmm1, [rip + c_1_0]
    subss xmm1, xmm0             # 1.0 - collarette * 0.6

    # Base stroma + collarette blend
    movss xmm2, [rip + c_0_30]
    mulss xmm2, xmm1
    movss xmm3, [rip + c_0_72]
    mulss xmm3, xmm0
    addss xmm2, xmm3             # ir_r

    movss xmm4, [rip + c_0_52]
    mulss xmm4, xmm1
    movss xmm5, [rip + c_0_55]
    mulss xmm5, xmm0
    addss xmm4, xmm5             # ir_g

    movss xmm6, [rip + c_0_44]
    mulss xmm6, xmm1
    movss xmm7, [rip + c_0_22]
    mulss xmm7, xmm0
    addss xmm6, xmm7             # ir_b

    # limbal = ss(0.72, 0.98, iris_norm)
    movss xmm2, [rsp + 112]
    movss xmm0, [rip + c_0_72]
    movss xmm1, [rip + c_0_98]
    call ss_func
    mulss xmm0, [rip + c_0_78]   # limbal * 0.78
    movss xmm1, [rip + c_1_0]
    subss xmm1, xmm0

    mulss xmm2, xmm1
    movss xmm3, [rip + c_0_06]
    mulss xmm3, xmm0
    addss xmm2, xmm3
    movss [rsp + 100], xmm2

    mulss xmm4, xmm1
    movss xmm3, [rip + c_0_14]
    mulss xmm3, xmm0
    addss xmm4, xmm3
    movss [rsp + 104], xmm4

    mulss xmm6, xmm1
    movss xmm3, [rip + c_0_20]
    mulss xmm3, xmm0
    addss xmm6, xmm3
    movss [rsp + 108], xmm6

    # Apply shadow to iris
    movss xmm0, [rsp + 120]
    MUL_MEM [rsp + 100], xmm0
    MUL_MEM [rsp + 104], xmm0
    MUL_MEM [rsp + 108], xmm0
    jmp .Lrender_catchlights

.Lcheck_pupil_boundary:
    # Not inside iris or pupil
    jmp .Lrender_catchlights

.Lrender_catchlights:
    # Specular glints / catchlights
    # d1 = sqrt((u - glint_cx)^2 + ((v - glint_cy) * 1.1)^2)
    movss xmm0, [rsp + 56]
    subss xmm0, [rsp + 24]       # u - glint_cx
    mulss xmm0, xmm0
    movss xmm1, [rsp + 52]
    subss xmm1, [rsp + 28]       # v - glint_cy
    mulss xmm1, [rip + c_1_1]
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    divss xmm0, [rip + c_0_030]
    mulss xmm0, xmm0
    xorps xmm0, [rip + c_sign_mask]
    call expf
    mulss xmm0, [rip + c_1_8]
    movaps xmm13, xmm0           # glint in xmm13
    movss [rsp + 136], xmm13     # save glint

    # Add glint to eye color
    movaps xmm1, xmm13
    mulss xmm1, [rip + c_1_0]
    ADD_MEM [rsp + 100], xmm1
    movaps xmm1, xmm13
    mulss xmm1, [rip + c_0_98]
    ADD_MEM [rsp + 104], xmm1
    movaps xmm1, xmm13
    mulss xmm1, [rip + c_0_94]
    ADD_MEM [rsp + 108], xmm1

.Lcheck_eyelashes:
    # --------------------------------------------------------------------------
    # Eyelashes & Blink Seam
    # --------------------------------------------------------------------------
    xorps xmm8, xmm8             # total_lash = 0
    test ebx, ebx
    jz .Lclamp_colors

    # blink_seam = exp(-((v - y_seam) / 0.018)^2) * (1.0 - ou) * 0.88
    movss xmm0, [rsp + 52]       # v
    subss xmm0, [rsp + 76]       # v - y_seam
    divss xmm0, [rip + c_0_018]
    mulss xmm0, xmm0
    xorps xmm0, [rip + c_sign_mask]
    call expf
    movss xmm1, [rip + c_1_0]
    subss xmm1, [rip + ou]
    mulss xmm0, xmm1
    mulss xmm0, [rip + c_0_88]
    movaps xmm8, xmm0            # total_lash in xmm8
    movss [rsp + 148], xmm8      # save total_lash

    # Blend eyelash dark tone
    minss xmm8, [rip + c_0_96]
    movss xmm0, [rip + c_1_0]
    subss xmm0, xmm8
    MUL_MEM [rsp + 100], xmm0
    movss xmm1, [rip + c_0_03]
    mulss xmm1, xmm8
    ADD_MEM [rsp + 100], xmm1

    MUL_MEM [rsp + 104], xmm0
    movss xmm1, [rip + c_0_02]
    mulss xmm1, xmm8
    ADD_MEM [rsp + 104], xmm1

    MUL_MEM [rsp + 108], xmm0
    ADD_MEM [rsp + 108], xmm1

.Lclamp_colors:
    # Clamp final RGB to [0.0, 1.0]
    movss xmm0, [rsp + 100]
    maxss xmm0, [rip + c_0_0]
    minss xmm0, [rip + c_1_0]
    movss [rsp + 100], xmm0

    movss xmm1, [rsp + 104]
    maxss xmm1, [rip + c_0_0]
    minss xmm1, [rip + c_1_0]
    movss [rsp + 104], xmm1

    movss xmm2, [rsp + 108]
    maxss xmm2, [rip + c_0_0]
    minss xmm2, [rip + c_1_0]
    movss [rsp + 108], xmm2

    # --------------------------------------------------------------------------
    # Character Selection
    # --------------------------------------------------------------------------
    # Hash for character selection
    mov eax, r14d                # c
    imul eax, eax, 374761393
    mov edx, r13d                # r
    imul edx, edx, 668265263
    xor eax, edx
    xor eax, 1337
    mov edx, eax
    shr edx, 13
    xor eax, edx
    imul eax, eax, 1274126177
    mov edx, eax
    shr edx, 16
    xor eax, edx
    and eax, 0x7fffffff
    mov ebx, eax                 # ebx = h_val

    # Character rules
    movss xmm0, [rsp + 148]      # total_lash
    ucomiss xmm0, [rip + c_0_38] # total_lash > 0.38?
    jbe .Lch_check_glint
    movss xmm0, [rip + ou]
    ucomiss xmm0, [rip + c_0_2]
    jae .Lch_lash_open
    test r14d, 1
    mov dl, '-'
    jnz .Lch_lash_set
    mov dl, '+'
    jmp .Lch_lash_set
.Lch_lash_open:
    movss xmm0, [rsp + 56]
    ucomiss xmm0, [rip + c_neg_0_15]
    jb .Lch_lash_slash
    ucomiss xmm0, [rip + c_0_15]
    ja .Lch_lash_bslash
    mov dl, '|'
    jmp .Lch_lash_set
.Lch_lash_slash:
    mov dl, '/'
    jmp .Lch_lash_set
.Lch_lash_bslash:
    mov dl, '\\'
.Lch_lash_set:
    jmp .Lwrite_cell_output

.Lch_check_glint:
    movss xmm0, [rsp + 136]      # glint
    ucomiss xmm0, [rip + c_0_50]
    jbe .Lch_check_pupil
    ucomiss xmm0, [rip + c_0_75]
    mov dl, '+'
    jbe .Lwrite_cell_output
    mov dl, '*'
    jmp .Lwrite_cell_output

.Lch_check_pupil:
    cmp dword ptr [rsp + 132], 0 # in_pupil?
    jz .Lch_check_iris
    movss xmm0, [rip + pupil_radius]
    mulss xmm0, [rip + c_0_65]
    movss xmm1, [rsp + 124]      # dist_iris
    ucomiss xmm1, xmm0           # dist_iris < pupil_r * 0.65?
    mov dl, '#'
    jae .Lwrite_cell_output
    mov dl, '@'
    jmp .Lwrite_cell_output

.Lch_check_iris:
    cmp dword ptr [rsp + 128], 0 # in_iris?
    jz .Lch_check_meniscus
    mov eax, ebx
    add eax, [rip + tick]
    and eax, 15
    lea rdx, [rip + iris_letters]
    movzx edx, byte ptr [rdx + rax]
    jmp .Lwrite_cell_output

.Lch_check_meniscus:
    movss xmm0, [rsp + 160]      # meniscus
    ucomiss xmm0, [rip + c_0_40]
    jbe .Lch_check_caruncle
    mov dl, '='
    jmp .Lwrite_cell_output

.Lch_check_caruncle:
    movss xmm0, [rsp + 144]      # caruncle
    ucomiss xmm0, [rip + c_0_35]
    jbe .Lch_check_sclera
    lea eax, [r13 + r14]
    test eax, 1
    mov dl, '%'
    jnz .Lwrite_cell_output
    mov dl, '&'
    jmp .Lwrite_cell_output

.Lch_check_sclera:
    cmp dword ptr [rsp + 96], 0  # inside_eye?
    jz .Lch_check_lashline
    movss xmm0, [rsp + 140]      # vessel_mask
    ucomiss xmm0, [rip + c_0_22]
    jbe .Lch_sclera_plain
    test r14d, 1
    mov dl, ';'
    jnz .Lwrite_cell_output
    mov dl, '~'
    jmp .Lwrite_cell_output

.Lch_sclera_plain:
    xor edx, edx
    mov eax, ebx
    mov ecx, 14
    div ecx
    lea rax, [rip + sclera_letters]
    movzx edx, byte ptr [rax + rdx]
    jmp .Lwrite_cell_output

.Lch_check_lashline:
    movss xmm0, [rsp + 152]      # lashline
    ucomiss xmm0, [rip + c_0_35]
    jbe .Lch_check_crease
    movss xmm0, [rsp + 56]
    andps xmm0, [rip + c_abs_mask]
    ucomiss xmm0, [rip + c_0_3]
    mov dl, '-'
    jb .Lwrite_cell_output
    movss xmm0, [rsp + 56]
    ucomiss xmm0, [rip + c_0_0]
    mov dl, '/'
    jb .Lwrite_cell_output
    mov dl, '\\'
    jmp .Lwrite_cell_output

.Lch_check_crease:
    movss xmm0, [rsp + 156]      # crease
    ucomiss xmm0, [rip + c_0_35]
    jbe .Lch_skin
    lea eax, [r13 + r14]
    test eax, 1
    mov dl, ')'
    jnz .Lwrite_cell_output
    mov dl, '('
    jmp .Lwrite_cell_output

.Lch_skin:
    xor edx, edx
    mov eax, ebx
    mov ecx, 18
    div ecx
    lea rax, [rip + skin_letters]
    movzx edx, byte ptr [rax + rdx]

.Lwrite_cell_output:
    # dl has character to emit
    # Convert RGB float (0..1) to integer (0..255)
    movss xmm0, [rsp + 100]
    mulss xmm0, [rip + c_255_0]
    cvttss2si ecx, xmm0          # ir in ecx

    movss xmm1, [rsp + 104]
    mulss xmm1, [rip + c_255_0]
    cvttss2si r8d, xmm1          # ig in r8d

    movss xmm2, [rsp + 108]
    mulss xmm2, [rip + c_255_0]
    cvttss2si r9d, xmm2          # ib in r9d

    # Delta color comparison:
    cmp ecx, [rsp + 40]          # last_r
    jne .Lemit_color_change
    cmp r8d, [rsp + 44]          # last_g
    jne .Lemit_color_change
    cmp r9d, [rsp + 48]          # last_b
    je .Lemit_char_only

.Lemit_color_change:
    # Save dl
    mov [rsp + 120], dl

    # Append "\033[38;2;"
    mov dword ptr [r12], 0x38335b1b
    mov word ptr [r12 + 4], 0x323b
    mov byte ptr [r12 + 6], ';'
    add r12, 7

    # Append R
    mov esi, ecx
    call append_u8_fast

    mov byte ptr [r12], ';'
    inc r12

    # Append G
    mov esi, r8d
    call append_u8_fast

    mov byte ptr [r12], ';'
    inc r12

    # Append B
    mov esi, r9d
    call append_u8_fast

    mov byte ptr [r12], 'm'
    inc r12

    # Update delta trackers
    mov [rsp + 40], ecx
    mov [rsp + 44], r8d
    mov [rsp + 48], r9d

    mov dl, [rsp + 120]

.Lemit_char_only:
    mov [r12], dl
    inc r12

    inc r14d
    jmp .Lcol_loop

.Lend_cols:
    # Emit \r\n at end of row if not last row
    mov eax, [rip + rows]
    dec eax
    cmp r13d, eax
    jae .Lskip_row_nl
    mov word ptr [r12], 0x0a0d   # "\r\n"
    add r12, 2

.Lskip_row_nl:
    inc r13d
    jmp .Lrow_loop

.Lend_rows:
    # Reset color at end of frame: "\033[0m"
    mov dword ptr [r12], 0x6d305b1b
    add r12, 4

    # Calculate total frame length
    lea rax, [rip + out_buf]
    sub r12, rax
    mov [rip + out_len], r12d

    add rsp, 176
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

# ==============================================================================
# main: Application Entry Point
# ==============================================================================
main:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 40

    # 1. Save original termios
    xor edi, edi                 # stdin
    lea rsi, [rip + orig_termios]
    call tcgetattr

    # 2. Configure raw terminal mode
    lea rdi, [rip + raw_termios]
    lea rsi, [rip + orig_termios]
    mov ecx, 60
    rep movsb

    lea rdi, [rip + raw_termios]
    call cfmakeraw

    # Non-blocking VMIN=0, VTIME=0
    mov byte ptr [rip + raw_termios + 17 + 6], 0 # VMIN
    mov byte ptr [rip + raw_termios + 17 + 5], 0 # VTIME

    xor edi, edi
    mov esi, 1                   # TCSADRAIN
    lea rdx, [rip + raw_termios]
    call tcsetattr

    # 3. Register signal handlers
    mov edi, 2                   # SIGINT
    lea rsi, [rip + on_sigint]
    call signal

    mov edi, 15                  # SIGTERM
    lea rsi, [rip + on_sigint]
    call signal

    mov edi, 28                  # SIGWINCH
    lea rsi, [rip + on_sigwinch]
    call signal

    # 4. Initialize screen & SGR 1006 mouse tracking
    mov edi, 1                   # stdout
    lea rsi, [rip + term_enter]
    mov edx, 58
    call write

    # 5. Query window size
    call update_winsize

    # 6. Initialize timers
    call get_time_sec
    movsd [rip + blink_start_time], xmm0
    movsd [rip + last_blink_end_time], xmm0
    movsd [rip + last_mouse_time], xmm0

    addsd xmm0, [rip + c_1_5_d]
    movsd [rip + next_saccade_time], xmm0

    call get_time_sec
    addsd xmm0, [rip + c_0_8_d]
    movsd [rip + next_microsaccade_time], xmm0

    call get_time_sec
    addsd xmm0, [rip + c_3_0_d]
    movsd [rip + next_blink_time], xmm0

    # --------------------------------------------------------------------------
    # Main Render & Animation Loop (~30-60 FPS)
    # --------------------------------------------------------------------------
.Lmain_loop:
    cmp dword ptr [rip + running], 0
    jz .Lexit_app

    # Check terminal resize flag
    cmp dword ptr [rip + winch_flag], 0
    jz .Lno_resize
    mov dword ptr [rip + winch_flag], 0
    call update_winsize
    # Clear screen on resize
    mov edi, 1
    lea rsi, [rip + term_clear]
    mov edx, 4
    call write

.Lno_resize:
    # Record loop start time
    call get_time_sec
    movsd [rsp], xmm0

    # Handle input
    call handle_input

    # Update controller
    call controller_update

    # Render frame
    call render_frame

    # Flush frame buffer in single write syscall
    mov edi, 1
    lea rsi, [rip + out_buf]
    mov edx, [rip + out_len]
    call write

    # Increment tick
    inc dword ptr [rip + tick]

    # FPS throttle (target 33.3ms = 30 FPS)
    call get_time_sec
    subsd xmm0, [rsp]            # elapsed in xmm0
    movsd xmm1, [rip + c_frame_time_d] # 0.033333s
    subsd xmm1, xmm0             # remaining time
    ucomisd xmm1, [rip + c_0_001_d]
    jbe .Lmain_loop

    mulsd xmm1, [rip + c_1000000_d]
    cvtsd2si edi, xmm1
    call usleep
    jmp .Lmain_loop

.Lexit_app:
    # --------------------------------------------------------------------------
    # Terminal Restoration
    # --------------------------------------------------------------------------
    mov edi, 1
    lea rsi, [rip + term_leave]
    mov edx, 55
    call write

    xor edi, edi
    mov esi, 1                   # TCSADRAIN
    lea rdx, [rip + orig_termios]
    call tcsetattr

    xor eax, eax
    add rsp, 40
    pop rbx
    leave
    ret

# ------------------------------------------------------------------------------
# Read-Only Data Section
# ------------------------------------------------------------------------------
.section .rodata

# Terminal escape sequences
term_enter:
    .ascii "\033[?1049h\033[?25l\033[?7l\033[?1000h\033[?1002h\033[?1003h\033[?1006h\033[2J\033[H"
term_enter_len = . - term_enter

term_leave:
    .ascii "\033[?1003l\033[?1002l\033[?1000l\033[?1006l\033[?7h\033[?25h\033[?1049l\033[0m"
term_leave_len = . - term_leave

term_clear:
    .ascii "\033[2J\033[H"

# Character pools
skin_letters:
    .ascii "vczxunxrjftYXZUJCL"
sclera_letters:
    .ascii "0OQCZJUYXzcvun"
iris_letters:
    .ascii "0OQ8%&B$@WM#*obp"

# Choices for saccades
saccade_gx_choices:
    .float -0.20, -0.10, 0.0, 0.10, 0.20
saccade_gy_choices:
    .float -0.06, -0.02, 0.0, 0.03, 0.06

# Choices for space glance
space_gx_choices:
    .float -0.18, -0.09, 0.0, 0.09, 0.18
space_gy_choices:
    .float -0.06, 0.0, 0.06

# Constants
c_char_aspect: .float 2.05
c_scale:       .float 1.65
c_eye_w:       .float 0.82
c_eps:         .float 0.0000001
c_inv_16m:     .float 0.000000059604644775390625
c_inv_1m_d:    .double 0.000001
c_1000000_d:   .double 1000000.0
c_frame_time_d:.double 0.03333333333333333 # 30 FPS
c_0_001_d:     .double 0.001
c_2_5_d:       .double 2.5
c_1_5_d:       .double 1.5
c_0_8_d:       .double 0.8
c_3_0_d:       .double 3.0
c_85_d:        .double 85.0
c_125_d:       .double 125.0
c_240_d:       .double 240.0
c_115_d:       .double 115.0
c_1000_d:      .double 1000.0

c_abs_mask:    .long 0x7fffffff, 0, 0, 0
c_sign_mask:   .long 0x80000000, 0, 0, 0

c_0_0:         .float 0.0
c_1_0:         .float 1.0
c_2_0:         .float 2.0
c_3_0:         .float 3.0
c_0_5:         .float 0.5
c_255_0:       .float 255.0
c_neg_1_0:     .float -1.0
c_0_22:        .float 0.22
c_neg_0_22:    .float -0.22
c_0_14:        .float 0.14
c_neg_0_14:    .float -0.14
c_0_9:         .float 0.9
c_neg_0_9:     .float -0.9
c_0_6:         .float 0.6
c_1_8:         .float 1.8
c_1_2:         .float 1.2
c_3_2:         .float 3.2
c_6_0:         .float 6.0
c_0_8:         .float 0.8
c_0_015:       .float 0.015
c_neg_0_015:   .float -0.015
c_0_009:       .float 0.009
c_neg_0_009:   .float -0.009
c_34_0:        .float 34.0
c_48_0:        .float 48.0
c_30_0:        .float 30.0
c_42_0:        .float 42.0
c_0_0022:      .float 0.0022
c_0_0014:      .float 0.0014
c_0_0018:      .float 0.0018
c_0_0010:      .float 0.0010
c_1_5:         .float 1.5
c_0_012:       .float 0.012
c_0_006:       .float 0.006
c_0_7:         .float 0.7
c_0_022:       .float 0.022
c_0_125:       .float 0.125
c_0_52:        .float 0.52
c_1_6:         .float 1.6
c_0_65:        .float 0.65
c_0_32:        .float 0.32
c_0_055:       .float 0.055
c_0_065:       .float 0.065
c_0_35:        .float 0.35
c_0_20:        .float 0.20
c_0_15:        .float 0.15
c_0_46:        .float 0.46
c_0_02:        .float 0.02
c_0_10:        .float 0.10
c_neg_0_28:    .float -0.28
c_0_01:        .float 0.01
c_neg_0_06:    .float -0.06
c_0_50:        .float 0.50
c_0_04:        .float 0.04
c_5_0:         .float 5.0
c_0_24:        .float 0.24
c_0_88:        .float 0.88
c_skin_base_r: .float 0.62
c_skin_base_g: .float 0.40
c_skin_base_b: .float 0.29
c_1_1:         .float 1.1
c_0_3:         .float 0.3
c_1_15:        .float 1.15
c_1_06:        .float 1.06
c_0_028:       .float 0.028
c_0_18:        .float 0.18
c_0_08:        .float 0.08
c_0_05:        .float 0.05
c_0_07:        .float 0.07
c_0_13:        .float 0.13
c_0_014:       .float 0.014
c_0_007:       .float 0.007
c_0_75:        .float 0.75
c_0_76:        .float 0.76
c_0_34:        .float 0.34
c_0_004:       .float 0.004
c_0_45:        .float 0.45
c_0_40:        .float 0.40
c_0_38:        .float 0.38
c_0_010:       .float 0.010
c_0_28:        .float 0.28
c_0_95:        .float 0.95
c_neg_0_55:    .float -0.55
c_neg_0_92:    .float -0.92
c_25_0:        .float 25.0
c_32_0:        .float 32.0
c_2_2:         .float 2.2
c_3_5:         .float 3.5
c_0_42:        .float 0.42
c_0_94:        .float 0.94
c_0_86:        .float 0.86
c_0_44:        .float 0.44
c_0_90:        .float 0.90
c_0_588:       .float 0.588
c_0_294:       .float 0.294
c_0_280:       .float 0.280
c_12_0:        .float 12.0
c_0_16:        .float 0.16
c_0_92:        .float 0.92
c_0_19:        .float 0.19
c_1_05:        .float 1.05
c_0_72:        .float 0.72
c_0_98:        .float 0.98
c_0_78:        .float 0.78
c_0_06:        .float 0.06
c_0_030:       .float 0.030
c_0_018:       .float 0.018
c_0_96:        .float 0.96
c_0_03:        .float 0.03
c_neg_0_15:    .float -0.15
c_0_2:         .float 0.2
c_0_30:        .float 0.30
c_0_48:        .float 0.48
c_0_36:        .float 0.36
c_0_55:        .float 0.55


# ------------------------------------------------------------------------------
# Data Section
# ------------------------------------------------------------------------------
.section .data

running:             .long 1
winch_flag:          .long 0
cols:                .long 86
rows:                .long 36
tick:                .long 0
is_blinking:         .long 0
mouse_control:       .long 0
out_len:             .long 0

ou:                  .float 1.0
ou_target:           .float 1.0
gx:                  .float 0.0
gy:                  .float 0.0
gx_smooth:           .float 0.0
gy_smooth:           .float 0.0
gx_target:           .float 0.0
gy_target:           .float 0.0
pupil_radius:        .float 0.125

blink_start_time:    .double 0.0
last_blink_end_time: .double 0.0
last_mouse_time:     .double 0.0
next_saccade_time:   .double 0.0
next_microsaccade_time: .double 0.0
next_blink_time:     .double 0.0

rng_state:           .quad 88172645463325252

# ------------------------------------------------------------------------------
# BSS Section
# ------------------------------------------------------------------------------
.section .bss

orig_termios:        .skip 64
raw_termios:         .skip 64
ws:                  .skip 8
in_buf:              .skip 4096
out_buf:             .skip 1048576 # 1MB ANSI TrueColor Frame Buffer
