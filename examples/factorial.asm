main:
    lli  s0, MMIO_BASE
    li   a0, 5
    call factorial
    call print_int
    li   t0, '\n'
    sw   t0, MMIO_TX(s0)
    li   t0, 0
    sw   t0, MMIO_EXIT(s0)

factorial:
    mov  t0, a0
    li   t1, 1
loop:
    beq  t0, zero, end
    mul  t1, t1, t0
    addi t0, t0, -1
    jmp  loop
end:
    mov  a0, t1
    ret

print_int:
    bge  a0, zero, pi_body
    li   t0, '-'
    sw   t0, MMIO_TX(s0)
    sub  a0, zero, a0
pi_body:
    li   t5, 10
    bne  a0, zero, pi_nonzero
    li   t0, '0'
    sw   t0, MMIO_TX(s0)
    ret
pi_nonzero:
    addi sp, sp, -64
    mov  t1, sp
    mov  t4, a0
pi_extract:
    li   t3, 0
    mov  t6, t4
pi_sub10:
    blt  t6, t5, pi_digit_done
    sub  t6, t6, t5
    addi t3, t3, 1
    jmp  pi_sub10
pi_digit_done:
    addi t6, t6, '0'
    sb   t6, 0(t1)
    addi t1, t1, 1
    mov  t4, t3
    bne  t4, zero, pi_extract
pi_print_loop:
    addi t1, t1, -1
    lb   t0, 0(t1)
    sw   t0, MMIO_TX(s0)
    bne  t1, sp, pi_print_loop
    addi sp, sp, 64
    ret
