main:
    lli  s0, MMIO_BASE
    lli  s1, FB_BASE
    mov  t3, s1
    li   t0, 0
row_loop:
    li   t1, 0
col_loop:
    xor  t2, t0, t1
    sb   t2, 0(t3)
    addi t3, t3, 1
    addi t1, t1, 1
    li   t4, 128
    blt  t1, t4, col_loop

    addi t0, t0, 1
    li   t4, 128
    blt  t0, t4, row_loop

    li   t0, 0
    sw   t0, MMIO_EXIT(s0)
