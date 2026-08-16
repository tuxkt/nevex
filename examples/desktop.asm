    jmp main

wx0: .word 5
wy0: .word 5
wx1: .word 70
wy1: .word 5
wx2: .word 38
wy2: .word 80

visible0: .word 1
visible1: .word 1
visible2: .word 1
front_win: .word -1

drag0: .word 0
drag1: .word 0
drag2: .word 0
drag_off_x: .word 0
drag_off_y: .word 0
prev_btn: .word 0
tick_count: .word 0

ball_lx: .word 20
ball_ly: .word 15
ball_dx: .word 1
ball_dy: .word 1
counter: .word 0

title0: .asciz "KALEM"
title1: .asciz "TOP"
title2: .asciz "SAYAC"

.align 4
paint_buf: .space 1600

pixel_addr:
    mov  t5, t3
    slli t5, t5, 7
    add  t5, t5, t2
    add  t5, t5, s1
    ret

fill_rect:
    addi sp, sp, -4
    sw   ra, 0(sp)
    li   t1, 0
fr_row:
    bge  t1, a3, fr_done
    li   t6, 0
fr_col:
    bge  t6, a2, fr_col_done
    add  t2, a0, t6
    add  t3, a1, t1
    call pixel_addr
    sb   t0, 0(t5)
    addi t6, t6, 1
    jmp  fr_col
fr_col_done:
    addi t1, t1, 1
    jmp  fr_row
fr_done:
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

print_str:
ps_loop:
    lb   t2, 0(t1)
    beq  t2, zero, ps_done
    sw   t2, MMIO_CHAR_DRAW(s0)
    addi t1, t1, 1
    jmp  ps_loop
ps_done:
    ret

draw_window_chrome:
    addi sp, sp, -16
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    sw   a1, 8(sp)
    sw   t1, 12(sp)

    li   a2, 50
    li   a3, 8
    li   t0, 146
    call fill_rect

    lw   a0, 4(sp)
    lw   a1, 8(sp)
    addi a0, a0, 2
    addi a1, a1, 1
    sw   a0, MMIO_CHAR_X(s0)
    sw   a1, MMIO_CHAR_Y(s0)
    li   t0, 255
    sw   t0, MMIO_CHAR_COLOR(s0)
    lw   t1, 12(sp)
    call print_str

    lw   ra, 0(sp)
    addi sp, sp, 16
    ret

blit_paint:
    addi sp, sp, -4
    sw   ra, 0(sp)
    li   t1, 0
bp_row:
    li   t4, 32
    bge  t1, t4, bp_done
    li   t6, 0
bp_col:
    li   t4, 50
    bge  t6, t4, bp_col_done
    mov  a2, t1
    li   a3, 50
    mul  a2, a2, a3
    add  a2, a2, t6
    lli  a3, paint_buf
    add  a3, a3, a2
    lb   a3, 0(a3)
    beq  a3, zero, bp_skip
    add  t2, a0, t6
    add  t3, a1, t1
    call pixel_addr
    sb   a3, 0(t5)
bp_skip:
    addi t6, t6, 1
    jmp  bp_col
bp_col_done:
    addi t1, t1, 1
    jmp  bp_row
bp_done:
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

draw_w0:
    lw   t4, visible0(zero)
    beq  t4, zero, dw0_ret
    addi sp, sp, -4
    sw   ra, 0(sp)

    lw   a0, wx0(zero)
    lw   a1, wy0(zero)
    lli  t1, title0
    call draw_window_chrome

    lw   a0, wx0(zero)
    lw   a1, wy0(zero)
    addi a1, a1, 8
    call blit_paint

    lw   ra, 0(sp)
    addi sp, sp, 4
dw0_ret:
    ret

draw_w1:
    lw   t4, visible1(zero)
    beq  t4, zero, dw1_ret
    addi sp, sp, -4
    sw   ra, 0(sp)

    lw   a0, wx1(zero)
    lw   a1, wy1(zero)
    lli  t1, title1
    call draw_window_chrome

    lw   t2, wx1(zero)
    lw   a0, ball_lx(zero)
    add  t2, t2, a0
    lw   t3, wy1(zero)
    addi t3, t3, 8
    lw   a0, ball_ly(zero)
    add  t3, t3, a0
    call pixel_addr
    li   t4, 31
    sb   t4, 0(t5)

    lw   ra, 0(sp)
    addi sp, sp, 4
dw1_ret:
    ret

draw_w2:
    lw   t4, visible2(zero)
    beq  t4, zero, dw2_ret
    addi sp, sp, -4
    sw   ra, 0(sp)

    lw   a0, wx2(zero)
    lw   a1, wy2(zero)
    lli  t1, title2
    call draw_window_chrome

    lw   a0, wx2(zero)
    addi a0, a0, 2
    lw   a1, wy2(zero)
    addi a1, a1, 20
    lw   a2, counter(zero)
    li   a3, 8
    li   t0, 227
    call fill_rect

    lw   ra, 0(sp)
    addi sp, sp, 4
dw2_ret:
    ret

draw_taskbar:
    addi sp, sp, -4
    sw   ra, 0(sp)

    li   a0, 0
    li   a1, 119
    li   a2, 128
    li   a3, 9
    li   t0, 37
    call fill_rect

    li   a0, 2
    li   a1, 121
    li   a2, 10
    li   a3, 6
    li   t0, 255
    call fill_rect

    li   a0, 16
    li   a1, 121
    li   a2, 10
    li   a3, 6
    li   t0, 31
    call fill_rect

    li   a0, 30
    li   a1, 121
    li   a2, 10
    li   a3, 6
    li   t0, 227
    call fill_rect

    lw   t1, tick_count(zero)
    li   t2, 25
    div  t1, t1, t2
    li   t2, 60
    div  t3, t1, t2
    rem  t1, t1, t2

    li   t2, 10
    div  t4, t3, t2
    rem  t3, t3, t2
    addi t4, t4, 48
    addi t3, t3, 48
    div  t6, t1, t2
    rem  t1, t1, t2
    addi t6, t6, 48
    addi t1, t1, 48

    li   t2, 88
    sw   t2, MMIO_CHAR_X(s0)
    li   t2, 121
    sw   t2, MMIO_CHAR_Y(s0)
    li   t2, 255
    sw   t2, MMIO_CHAR_COLOR(s0)
    sw   t4, MMIO_CHAR_DRAW(s0)
    sw   t3, MMIO_CHAR_DRAW(s0)
    li   t2, 58
    sw   t2, MMIO_CHAR_DRAW(s0)
    sw   t6, MMIO_CHAR_DRAW(s0)
    sw   t1, MMIO_CHAR_DRAW(s0)

    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

main:
    lli  s0, MMIO_BASE
    lli  s1, FB_BASE

desktop_loop:
    lw   t0, MMIO_MOUSE_X(s0)
    lw   t1, MMIO_MOUSE_Y(s0)
    lw   t4, MMIO_MOUSE_BTN(s0)
    beq  t4, zero, mouse_up

    lw   t6, drag0(zero)
    bne  t6, zero, do_drag0
    lw   t6, drag1(zero)
    bne  t6, zero, do_drag1
    lw   t6, drag2(zero)
    bne  t6, zero, do_drag2

    lw   t6, prev_btn(zero)
    bne  t6, zero, after_drag

    li   t6, 119
    blt  t1, t6, chk_titlebars

    li   t6, 2
    blt  t0, t6, chk_tb_done
    li   t6, 12
    bge  t0, t6, chk_tb1
    lw   t6, visible0(zero)
    beq  t6, zero, tb0_show
    li   t6, 0
    sw   t6, visible0(zero)
    jmp  after_drag
tb0_show:
    li   t6, 1
    sw   t6, visible0(zero)
    li   t6, 0
    sw   t6, front_win(zero)
    jmp  after_drag
chk_tb1:
    li   t6, 16
    blt  t0, t6, chk_tb_done
    li   t6, 26
    bge  t0, t6, chk_tb2
    lw   t6, visible1(zero)
    beq  t6, zero, tb1_show
    li   t6, 0
    sw   t6, visible1(zero)
    jmp  after_drag
tb1_show:
    li   t6, 1
    sw   t6, visible1(zero)
    li   t6, 1
    sw   t6, front_win(zero)
    jmp  after_drag
chk_tb2:
    li   t6, 30
    blt  t0, t6, chk_tb_done
    li   t6, 40
    bge  t0, t6, chk_tb_done
    lw   t6, visible2(zero)
    beq  t6, zero, tb2_show
    li   t6, 0
    sw   t6, visible2(zero)
    jmp  after_drag
tb2_show:
    li   t6, 1
    sw   t6, visible2(zero)
    li   t6, 2
    sw   t6, front_win(zero)
chk_tb_done:
    jmp  after_drag

chk_titlebars:
    lw   t6, visible0(zero)
    beq  t6, zero, chk_w1_tb
    lw   t2, wx0(zero)
    blt  t0, t2, chk_w1_tb
    addi t3, t2, 50
    bge  t0, t3, chk_w1_tb
    lw   t2, wy0(zero)
    blt  t1, t2, chk_w1_tb
    addi t3, t2, 8
    bge  t1, t3, chk_w1_tb
    li   t6, 1
    sw   t6, drag0(zero)
    li   t6, 0
    sw   t6, front_win(zero)
    lw   t2, wx0(zero)
    sub  t6, t0, t2
    sw   t6, drag_off_x(zero)
    lw   t2, wy0(zero)
    sub  t6, t1, t2
    sw   t6, drag_off_y(zero)
    jmp  after_drag

chk_w1_tb:
    lw   t6, visible1(zero)
    beq  t6, zero, chk_w2_tb
    lw   t2, wx1(zero)
    blt  t0, t2, chk_w2_tb
    addi t3, t2, 50
    bge  t0, t3, chk_w2_tb
    lw   t2, wy1(zero)
    blt  t1, t2, chk_w2_tb
    addi t3, t2, 8
    bge  t1, t3, chk_w2_tb
    li   t6, 1
    sw   t6, drag1(zero)
    li   t6, 1
    sw   t6, front_win(zero)
    lw   t2, wx1(zero)
    sub  t6, t0, t2
    sw   t6, drag_off_x(zero)
    lw   t2, wy1(zero)
    sub  t6, t1, t2
    sw   t6, drag_off_y(zero)
    jmp  after_drag

chk_w2_tb:
    lw   t6, visible2(zero)
    beq  t6, zero, after_drag
    lw   t2, wx2(zero)
    blt  t0, t2, after_drag
    addi t3, t2, 50
    bge  t0, t3, after_drag
    lw   t2, wy2(zero)
    blt  t1, t2, after_drag
    addi t3, t2, 8
    bge  t1, t3, after_drag
    li   t6, 1
    sw   t6, drag2(zero)
    li   t6, 2
    sw   t6, front_win(zero)
    lw   t2, wx2(zero)
    sub  t6, t0, t2
    sw   t6, drag_off_x(zero)
    lw   t2, wy2(zero)
    sub  t6, t1, t2
    sw   t6, drag_off_y(zero)
    jmp  after_drag

do_drag0:
    lw   t6, drag_off_x(zero)
    sub  t2, t0, t6
    li   t3, 0
    blt  t2, t3, dw0_x_lo
    li   t3, 78
    bge  t2, t3, dw0_x_hi
    jmp  dw0_x_ok
dw0_x_lo:
    li   t2, 0
    jmp  dw0_x_ok
dw0_x_hi:
    li   t2, 78
dw0_x_ok:
    sw   t2, wx0(zero)
    lw   t6, drag_off_y(zero)
    sub  t3, t1, t6
    li   t2, 0
    blt  t3, t2, dw0_y_lo
    li   t2, 79
    bge  t3, t2, dw0_y_hi
    jmp  dw0_y_ok
dw0_y_lo:
    li   t3, 0
    jmp  dw0_y_ok
dw0_y_hi:
    li   t3, 79
dw0_y_ok:
    sw   t3, wy0(zero)
    jmp  after_drag

do_drag1:
    lw   t6, drag_off_x(zero)
    sub  t2, t0, t6
    li   t3, 0
    blt  t2, t3, dw1_x_lo
    li   t3, 78
    bge  t2, t3, dw1_x_hi
    jmp  dw1_x_ok
dw1_x_lo:
    li   t2, 0
    jmp  dw1_x_ok
dw1_x_hi:
    li   t2, 78
dw1_x_ok:
    sw   t2, wx1(zero)
    lw   t6, drag_off_y(zero)
    sub  t3, t1, t6
    li   t2, 0
    blt  t3, t2, dw1_y_lo
    li   t2, 79
    bge  t3, t2, dw1_y_hi
    jmp  dw1_y_ok
dw1_y_lo:
    li   t3, 0
    jmp  dw1_y_ok
dw1_y_hi:
    li   t3, 79
dw1_y_ok:
    sw   t3, wy1(zero)
    jmp  after_drag

do_drag2:
    lw   t6, drag_off_x(zero)
    sub  t2, t0, t6
    li   t3, 0
    blt  t2, t3, dw2_x_lo
    li   t3, 78
    bge  t2, t3, dw2_x_hi
    jmp  dw2_x_ok
dw2_x_lo:
    li   t2, 0
    jmp  dw2_x_ok
dw2_x_hi:
    li   t2, 78
dw2_x_ok:
    sw   t2, wx2(zero)
    lw   t6, drag_off_y(zero)
    sub  t3, t1, t6
    li   t2, 0
    blt  t3, t2, dw2_y_lo
    li   t2, 79
    bge  t3, t2, dw2_y_hi
    jmp  dw2_y_ok
dw2_y_lo:
    li   t3, 0
    jmp  dw2_y_ok
dw2_y_hi:
    li   t3, 79
dw2_y_ok:
    sw   t3, wy2(zero)
    jmp  after_drag

mouse_up:
    li   t6, 0
    sw   t6, drag0(zero)
    sw   t6, drag1(zero)
    sw   t6, drag2(zero)

after_drag:
    lw   t4, MMIO_MOUSE_BTN(s0)
    beq  t4, zero, after_apps
    lw   t6, drag0(zero)
    bne  t6, zero, after_apps
    lw   t6, drag1(zero)
    bne  t6, zero, after_apps
    lw   t6, drag2(zero)
    bne  t6, zero, after_apps

    lw   t0, MMIO_MOUSE_X(s0)
    lw   t1, MMIO_MOUSE_Y(s0)

    lw   t6, visible0(zero)
    beq  t6, zero, chk_cnt
    lw   t2, wx0(zero)
    blt  t0, t2, chk_cnt
    addi t3, t2, 50
    bge  t0, t3, chk_cnt
    lw   t2, wy0(zero)
    addi t2, t2, 8
    blt  t1, t2, chk_cnt
    addi t3, t2, 32
    bge  t1, t3, chk_cnt

    lw   t2, wx0(zero)
    sub  t2, t0, t2
    lw   t3, wy0(zero)
    addi t3, t3, 8
    sub  t3, t1, t3
    li   t6, 50
    mul  t3, t3, t6
    add  t3, t3, t2
    lli  t6, paint_buf
    add  t6, t6, t3
    li   t2, 255
    sb   t2, 0(t6)
    jmp  after_apps

chk_cnt:
    lw   t6, visible2(zero)
    beq  t6, zero, after_apps
    lw   t2, wx2(zero)
    blt  t0, t2, after_apps
    addi t3, t2, 50
    bge  t0, t3, after_apps
    lw   t2, wy2(zero)
    addi t2, t2, 8
    blt  t1, t2, after_apps
    addi t3, t2, 32
    bge  t1, t3, after_apps
    lw   t6, prev_btn(zero)
    bne  t6, zero, after_apps
    lw   t6, counter(zero)
    addi t6, t6, 1
    li   t2, 100
    blt  t6, t2, cnt_ok
    li   t6, 100
cnt_ok:
    sw   t6, counter(zero)

after_apps:
    lw   t2, ball_lx(zero)
    lw   t6, ball_dx(zero)
    add  a0, t2, t6
    li   t4, 0
    blt  a0, t4, blx_flip
    li   t4, 50
    blt  a0, t4, blx_ok
blx_flip:
    sub  t6, zero, t6
    sw   t6, ball_dx(zero)
    add  a0, t2, t6
blx_ok:
    sw   a0, ball_lx(zero)

    lw   t2, ball_ly(zero)
    lw   t6, ball_dy(zero)
    add  a0, t2, t6
    li   t4, 0
    blt  a0, t4, bly_flip
    li   t4, 32
    blt  a0, t4, bly_ok
bly_flip:
    sub  t6, zero, t6
    sw   t6, ball_dy(zero)
    add  a0, t2, t6
bly_ok:
    sw   a0, ball_ly(zero)

    lw   t6, tick_count(zero)
    addi t6, t6, 1
    sw   t6, tick_count(zero)

    li   a0, 0
    li   a1, 0
    li   a2, 128
    li   a3, 128
    li   t0, 0
    call fill_rect

    call draw_taskbar

    lw   t4, front_win(zero)
    li   t6, 0
    beq  t4, t6, order_skip0
    call draw_w0
order_skip0:
    li   t6, 1
    beq  t4, t6, order_skip1
    call draw_w1
order_skip1:
    li   t6, 2
    beq  t4, t6, order_skip2
    call draw_w2
order_skip2:
    li   t6, -1
    beq  t4, t6, order_no_front
    li   t6, 0
    beq  t4, t6, order_front0
    li   t6, 1
    beq  t4, t6, order_front1
    call draw_w2
    jmp  order_no_front
order_front0:
    call draw_w0
    jmp  order_no_front
order_front1:
    call draw_w1
order_no_front:

    lw   t4, MMIO_MOUSE_BTN(s0)
    sw   t4, prev_btn(zero)
    li   t4, 40
    sw   t4, MMIO_SLEEP_MS(s0)
    jmp  desktop_loop
