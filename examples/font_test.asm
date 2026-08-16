main:
    lli  s0, MMIO_BASE

    li   t0, 1
    sw   t0, MMIO_CHAR_X(s0)
    li   t0, 1
    sw   t0, MMIO_CHAR_Y(s0)
    li   t0, 255
    sw   t0, MMIO_CHAR_COLOR(s0)

    lli  t1, msg1
    call print_str

    li   t0, 1
    sw   t0, MMIO_CHAR_X(s0)
    li   t0, 10
    sw   t0, MMIO_CHAR_Y(s0)
    li   t0, 28
    sw   t0, MMIO_CHAR_COLOR(s0)

    lli  t1, msg2
    call print_str

    li   t0, 1
    sw   t0, MMIO_CHAR_X(s0)
    li   t0, 19
    sw   t0, MMIO_CHAR_Y(s0)
    li   t0, 224
    sw   t0, MMIO_CHAR_COLOR(s0)

    lli  t1, msg3
    call print_str

    li   t0, 0
    sw   t0, MMIO_EXIT(s0)

print_str:
ps_loop:
    lb   t2, 0(t1)
    beq  t2, zero, ps_done
    sw   t2, MMIO_CHAR_DRAW(s0)
    addi t1, t1, 1
    jmp  ps_loop
ps_done:
    ret

.align 4
msg1: .asciz "NEVEX FONT TEST!"
msg2: .asciz "0123456789 ABC"
msg3: .asciz "DEF GHI JKL MNO"
