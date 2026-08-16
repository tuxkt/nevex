main:
    lli  s0, MMIO_BASE
    lli  t1, msg
print_loop:
    lb   t2, 0(t1)
    beq  t2, zero, print_done
    sw   t2, MMIO_TX(s0)
    addi t1, t1, 1
    jmp  print_loop
print_done:

    li   t0, 2000
    li   t1, 'c'
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    sw   t2, MMIO_TX(s0)

    li   t0, '\n'
    sw   t0, MMIO_TX(s0)
    li   t0, 0
    sw   t0, MMIO_EXIT(s0)

.align 4
msg:
    .asciz "merhaba dunya\n"
