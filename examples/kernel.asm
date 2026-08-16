boot:
    lli  s0, MMIO_BASE
    lli  t0, trap_handler
    sw   t0, MMIO_MTVEC(s0)
    li   t0, MODE_USER
    sw   t0, MMIO_MPP(s0)
    lli  t0, user_main
    sw   t0, MMIO_MEPC(s0)
    li   t0, 1000
    sw   t0, MMIO_MTIMECMP(s0)
    li   t0, 1
    sw   t0, MMIO_MIE(s0)
    mret

trap_handler:
    lw   t0, MMIO_MCAUSE(s0)
    li   t1, CAUSE_ECALL_FROM_U
    beq  t0, t1, th_syscall
    li   t1, CAUSE_TIMER_INTERRUPT
    beq  t0, t1, th_timer

    li   t0, '?'
    sw   t0, MMIO_TX(s0)
    li   t0, 1
    sw   t0, MMIO_EXIT(s0)
th_halt_loop:
    jmp  th_halt_loop

th_timer:
    li   t0, '.'
    sw   t0, MMIO_TX(s0)
    lw   t0, MMIO_MTIME(s0)
    li   t1, 1000
    add  t0, t0, t1
    sw   t0, MMIO_MTIMECMP(s0)
    li   t0, 1
    sw   t0, MMIO_MIE(s0)
    mret

th_syscall:
    li   t1, SYS_PRINT_INT
    beq  a0, t1, th_print_int
    li   t1, SYS_PRINT_CHAR
    beq  a0, t1, th_print_char
    li   t1, SYS_PRINT_STR
    beq  a0, t1, th_print_str
    li   t1, SYS_EXIT
    beq  a0, t1, th_exit
    jmp  th_return

th_print_int:
    mov  a0, a1
    call print_int
    jmp  th_return

th_print_char:
    sw   a1, MMIO_TX(s0)
    jmp  th_return

th_print_str:
    mov  t1, a1
th_print_str_loop:
    lb   t0, 0(t1)
    beq  t0, zero, th_return
    sw   t0, MMIO_TX(s0)
    addi t1, t1, 1
    jmp  th_print_str_loop

th_exit:
    sw   a1, MMIO_EXIT(s0)

th_return:
    li   t0, 1
    sw   t0, MMIO_MIE(s0)
    lw   t0, MMIO_MEPC(s0)
    addi t0, t0, 4
    sw   t0, MMIO_MEPC(s0)
    mret

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

user_main:
    li   a0, 5
    call factorial
    mov  a1, a0
    li   a0, SYS_PRINT_INT
    ecall

    li   a0, SYS_PRINT_CHAR
    li   a1, '\n'
    ecall

    lli  a1, greeting
    li   a0, SYS_PRINT_STR
    ecall

    li   t3, 5000
um_busy_loop:
    addi t3, t3, -1
    bne  t3, zero, um_busy_loop

    li   a0, SYS_PRINT_CHAR
    li   a1, '\n'
    ecall

    li   a0, SYS_EXIT
    li   a1, 0
    ecall

factorial:
    mov  t0, a0
    li   t1, 1
f_loop:
    beq  t0, zero, f_end
    mul  t1, t1, t0
    addi t0, t0, -1
    jmp  f_loop
f_end:
    mov  a0, t1
    ret

.align 4
greeting:
    .asciz "\nnevex mini-kernel: timer interrupt + syscall demo\n"
