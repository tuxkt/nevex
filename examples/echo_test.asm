main:
    lli  s0, MMIO_BASE
loop:
    lw   t0, MMIO_STDIN(s0)
    li   t1, -1
    beq  t0, t1, done
    sw   t0, MMIO_TX(s0)
    jmp  loop
done:
    li   t0, 0
    sw   t0, MMIO_EXIT(s0)
