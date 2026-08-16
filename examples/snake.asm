    jmp main

dir:      .word 4
head_x:   .word 64
head_y:   .word 64
food_x:   .word 0
food_y:   .word 0
head_idx: .word 0
tail_idx: .word 0
len:      .word 1
body_x:   .space 1024
body_y:   .space 1024
over_msg: .asciz "\noyun bitti\n"
.align 4

pixel_addr:
    mov  t5, t3
    slli t5, t5, 7
    add  t5, t5, t2
    add  t5, t5, s1
    ret

spawn_food:
    addi sp, sp, -4
    sw   ra, 0(sp)
sf_retry:
    lw   t0, MMIO_RAND(s0)
    andi t0, t0, 127
    lw   t1, MMIO_RAND(s0)
    andi t1, t1, 127
    mov  t2, t0
    mov  t3, t1
    call pixel_addr
    lb   t6, 0(t5)
    bne  t6, zero, sf_retry
    li   t4, 224
    sb   t4, 0(t5)
    sw   t0, food_x(zero)
    sw   t1, food_y(zero)
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

main:
    lli  s0, MMIO_BASE
    lli  s1, FB_BASE

    lw   t2, head_x(zero)
    lw   t3, head_y(zero)
    call pixel_addr
    li   t4, 28
    sb   t4, 0(t5)
    lli  t6, body_x
    sb   t2, 0(t6)
    lli  t6, body_y
    sb   t3, 0(t6)
    li   t1, 1
    sw   t1, head_idx(zero)

    call spawn_food

game_loop:
    lw   t0, MMIO_KEY(s0)
    beq  t0, zero, dir_done
    lw   t1, dir(zero)
    li   t4, 1
    bne  t1, t4, gl_chk2
    li   t4, 2
    beq  t0, t4, dir_done
    jmp  set_dir
gl_chk2:
    li   t4, 2
    bne  t1, t4, gl_chk3
    li   t4, 1
    beq  t0, t4, dir_done
    jmp  set_dir
gl_chk3:
    li   t4, 3
    bne  t1, t4, gl_chk4
    li   t4, 4
    beq  t0, t4, dir_done
    jmp  set_dir
gl_chk4:
    li   t4, 4
    bne  t1, t4, set_dir
    li   t4, 3
    beq  t0, t4, dir_done
set_dir:
    sw   t0, dir(zero)
dir_done:

    lw   t2, head_x(zero)
    lw   t3, head_y(zero)
    lw   t1, dir(zero)
    li   t4, 1
    beq  t1, t4, move_up
    li   t4, 2
    beq  t1, t4, move_down
    li   t4, 3
    beq  t1, t4, move_left
    li   t4, 4
    beq  t1, t4, move_right
    jmp  after_move
move_up:
    addi t3, t3, -1
    jmp  after_move
move_down:
    addi t3, t3, 1
    jmp  after_move
move_left:
    addi t2, t2, -1
    jmp  after_move
move_right:
    addi t2, t2, 1
after_move:

    li   t4, 0
    blt  t2, t4, game_over
    blt  t3, t4, game_over
    li   t4, FB_WIDTH
    bge  t2, t4, game_over
    li   t4, FB_HEIGHT
    bge  t3, t4, game_over

    call pixel_addr
    lb   t6, 0(t5)
    li   t4, 28
    beq  t6, t4, game_over
    li   t4, 224
    beq  t6, t4, ate_food
    li   t0, 0
    jmp  push_head
ate_food:
    li   t0, 1

push_head:
    sw   t2, head_x(zero)
    sw   t3, head_y(zero)
    li   t4, 28
    sb   t4, 0(t5)

    lw   t1, head_idx(zero)
    lli  t6, body_x
    add  t6, t6, t1
    sb   t2, 0(t6)
    lli  t6, body_y
    add  t6, t6, t1
    sb   t3, 0(t6)
    addi t1, t1, 1
    andi t1, t1, 1023
    sw   t1, head_idx(zero)
    lw   t1, len(zero)
    addi t1, t1, 1
    sw   t1, len(zero)

    beq  t0, zero, pop_tail
    call spawn_food
    jmp  tick_delay

pop_tail:
    lw   t1, tail_idx(zero)
    lli  t6, body_x
    add  t6, t6, t1
    lb   t2, 0(t6)
    lli  t6, body_y
    add  t6, t6, t1
    lb   t3, 0(t6)
    call pixel_addr
    li   t4, 0
    sb   t4, 0(t5)
    addi t1, t1, 1
    andi t1, t1, 1023
    sw   t1, tail_idx(zero)
    lw   t1, len(zero)
    addi t1, t1, -1
    sw   t1, len(zero)

tick_delay:
    li   t0, 120
    sw   t0, MMIO_SLEEP_MS(s0)
    jmp  game_loop

game_over:
    lli  t1, over_msg
go_print:
    lb   t0, 0(t1)
    beq  t0, zero, go_done
    sw   t0, MMIO_TX(s0)
    addi t1, t1, 1
    jmp  go_print
go_done:
    li   t0, 0
    sw   t0, MMIO_EXIT(s0)
