; nevexas.asm - Nevex assembler'inin kendi ISA'sinda (self-hosted) yazilmis hali.
;
; Calisma bicimi: ./nevex nevexas.bin < kaynak.asm > cikti.bin
; MMIO_STDIN'den kaynak metni okur, iki gecisli assemble eder, makine kodunu
; MMIO_TX ile stdout'a yazar. Hatalar da MMIO_TX ile "HATA:" onekiyle yazilir
; ve program exit code 1 ile durur (basari: exit code 0).
;
; Kayit konvansiyonu:
;   s0 = MMIO_BASE. Programin basinda BIR KERE yuklenir ve bir daha ASLA
;        yazilmaz - hicbir fonksiyon s0'i save/restore etmek zorunda degil.
;   Diger her sey (s1 dahil) gecici; kalici durum bellekteki global
;   degiskenlerde tutulur (register omru fonksiyonlar arasi guvenilmez).
;
; String'ler SRC_BUF icinde YERINDE (in-place) null-terminate edilir
; (satir sonlari, virguller, bosluklar '\0' ile degistirilir) - boylece
; mnemonic/operand karsilastirmalari duz null-terminated strcmp ile yapilir,
; ayri uzunluk alanlarina gerek kalmaz.

    jmp start

; ============================================================
; Yardimci rutinler
; ============================================================

; --- putc: a0 = karakter, MMIO_TX'e yazar ---
putc:
    sw   a0, MMIO_TX(s0)
    ret

; --- print_str: a0 = null-terminated string adresi ---
print_str:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   s1, 4(sp)
    mov  s1, a0
print_str_loop:
    lb   t1, 0(s1)
    beq  t1, zero, print_str_done
    mov  a0, t1
    call putc
    addi s1, s1, 1
    jmp  print_str_loop
print_str_done:
    lw   ra, 0(sp)
    lw   s1, 4(sp)
    addi sp, sp, 8
    ret

; --- print_dec: a0 = signed 32-bit deger, ondalik yazdirir ---
print_dec:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   s1, 4(sp)
    mov  t3, a0
    li   t4, 0
    bge  t3, zero, print_dec_push
    li   t4, 1
    li   t0, 0
    sub  t3, t0, t3
print_dec_push:
    li   s1, 0
print_dec_push_loop:
    li   t0, 10
    rem  t1, t3, t0
    div  t3, t3, t0
    addi t1, t1, 48
    addi sp, sp, -4
    sw   t1, 0(sp)
    addi s1, s1, 1
    bne  t3, zero, print_dec_push_loop
    beq  t4, zero, print_dec_pop
    li   a0, 45
    call putc
print_dec_pop:
    beq  s1, zero, print_dec_ret
    lw   a0, 0(sp)
    addi sp, sp, 4
    call putc
    addi s1, s1, -1
    jmp  print_dec_pop
print_dec_ret:
    lw   ra, 0(sp)
    lw   s1, 4(sp)
    addi sp, sp, 8
    ret

; --- is_space: a0=char -> a0=1/0 (space,tab,cr,nl) ---
is_space:
    li   t0, 32
    beq  a0, t0, is_space_yes
    li   t0, 9
    beq  a0, t0, is_space_yes
    li   t0, 13
    beq  a0, t0, is_space_yes
    li   t0, 10
    beq  a0, t0, is_space_yes
    li   a0, 0
    ret
is_space_yes:
    li   a0, 1
    ret

; --- is_digit: a0=char -> a0=1/0 ('0'-'9') ---
is_digit:
    li   t0, 48
    blt  a0, t0, is_digit_no
    li   t0, 58
    bge  a0, t0, is_digit_no
    li   a0, 1
    ret
is_digit_no:
    li   a0, 0
    ret

; --- is_alpha: a0=char -> a0=1/0 ('A'-'Z' veya 'a'-'z') ---
is_alpha:
    li   t0, 65
    blt  a0, t0, is_alpha_check_lower
    li   t0, 91
    blt  a0, t0, is_alpha_yes
is_alpha_check_lower:
    li   t0, 97
    blt  a0, t0, is_alpha_no
    li   t0, 123
    bge  a0, t0, is_alpha_no
is_alpha_yes:
    li   a0, 1
    ret
is_alpha_no:
    li   a0, 0
    ret

; --- is_alnum_us: a0=char -> a0=1/0 (alpha, digit, '_') ---
is_alnum_us:
    addi sp, sp, -4
    sw   ra, 0(sp)
    mov  t6, a0
    call is_alpha
    bne  a0, zero, is_alnum_us_yes
    mov  a0, t6
    call is_digit
    bne  a0, zero, is_alnum_us_yes
    li   t0, 95
    beq  t6, t0, is_alnum_us_yes
    li   a0, 0
    jmp  is_alnum_us_ret
is_alnum_us_yes:
    li   a0, 1
is_alnum_us_ret:
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

; --- hexval: a0=char -> a0=deger(0-15), a1=1 gecerli/0 gecersiz ---
hexval:
    addi sp, sp, -4
    sw   ra, 0(sp)
    mov  t6, a0
    call is_digit
    lw   ra, 0(sp)
    addi sp, sp, 4
    beq  a0, zero, hexval_alpha
    addi a0, t6, -48
    li   a1, 1
    ret
hexval_alpha:
    li   t0, 97
    blt  t6, t0, hexval_upper
    li   t0, 103
    bge  t6, t0, hexval_bad
    addi a0, t6, -87
    li   a1, 1
    ret
hexval_upper:
    li   t0, 65
    blt  t6, t0, hexval_bad
    li   t0, 71
    bge  t6, t0, hexval_bad
    addi a0, t6, -55
    li   a1, 1
    ret
hexval_bad:
    li   a0, 0
    li   a1, 0
    ret

; --- streq: a0,a1 = null-terminated string pointerlari -> a0=1/0 ---
streq:
    mov  t0, a0
    mov  t1, a1
streq_loop:
    lb   t2, 0(t0)
    lb   t3, 0(t1)
    bne  t2, t3, streq_no
    beq  t2, zero, streq_yes
    addi t0, t0, 1
    addi t1, t1, 1
    jmp  streq_loop
streq_yes:
    li   a0, 1
    ret
streq_no:
    li   a0, 0
    ret

; --- parse_imm: a0 = null-terminated token -> a0=deger, a1=1/0 (basari) ---
; Kabul eder: karakter literal ('a', '\n', '\t', '\r', '\0', '\\', '\'')
; hex (0x.. / 0X..), isaretli decimal. Bosluk barindirmamali (caller trim etmeli).
parse_imm:
    addi sp, sp, -4
    sw   ra, 0(sp)
    mov  t6, a0
    lb   t0, 0(t6)
    beq  t0, zero, parse_imm_fail
    li   t1, 39
    beq  t0, t1, parse_imm_char
    mov  t2, t6
    li   t3, 0
    lb   t0, 0(t2)
    li   t1, 43
    beq  t0, t1, parse_imm_skip_sign
    li   t1, 45
    bne  t0, t1, parse_imm_check_hex
    li   t3, 1
parse_imm_skip_sign:
    addi t2, t2, 1
parse_imm_check_hex:
    lb   t0, 0(t2)
    li   t1, 48
    bne  t0, t1, parse_imm_dec
    lb   t0, 1(t2)
    li   t1, 120
    beq  t0, t1, parse_imm_hex_go
    li   t1, 88
    beq  t0, t1, parse_imm_hex_go
    jmp  parse_imm_dec
parse_imm_hex_go:
    addi t2, t2, 2
    li   t4, 0
    li   t5, 0
parse_imm_hex_loop:
    lb   a0, 0(t2)
    beq  a0, zero, parse_imm_hex_end
    call hexval
    beq  a1, zero, parse_imm_fail
    slli t4, t4, 4
    add  t4, t4, a0
    addi t2, t2, 1
    addi t5, t5, 1
    jmp  parse_imm_hex_loop
parse_imm_hex_end:
    beq  t5, zero, parse_imm_fail
    jmp  parse_imm_apply_sign
parse_imm_dec:
    li   t4, 0
    li   t5, 0
parse_imm_dec_loop:
    lb   t0, 0(t2)
    beq  t0, zero, parse_imm_dec_end
    mov  a0, t0
    call is_digit
    beq  a0, zero, parse_imm_fail
    li   t0, 10
    mul  t4, t4, t0
    lb   t0, 0(t2)
    addi t0, t0, -48
    add  t4, t4, t0
    addi t2, t2, 1
    addi t5, t5, 1
    jmp  parse_imm_dec_loop
parse_imm_dec_end:
    beq  t5, zero, parse_imm_fail
parse_imm_apply_sign:
    beq  t3, zero, parse_imm_positive
    li   t0, 0
    sub  t4, t0, t4
parse_imm_positive:
    mov  a0, t4
    li   a1, 1
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
parse_imm_char:
    lb   t0, 1(t6)
    li   t1, 92
    beq  t0, t1, parse_imm_char_esc
    lb   t1, 2(t6)
    li   t2, 39
    bne  t1, t2, parse_imm_fail
    lb   t2, 3(t6)
    bne  t2, zero, parse_imm_fail
    mov  a0, t0
    li   a1, 1
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
parse_imm_char_esc:
    lb   t1, 2(t6)
    lb   t2, 3(t6)
    li   t4, 39
    bne  t2, t4, parse_imm_fail
    lb   t4, 4(t6)
    bne  t4, zero, parse_imm_fail
    li   t4, 110
    beq  t1, t4, parse_imm_char_nl
    li   t4, 116
    beq  t1, t4, parse_imm_char_tab
    li   t4, 114
    beq  t1, t4, parse_imm_char_cr
    li   t4, 48
    beq  t1, t4, parse_imm_char_nul
    li   t4, 92
    beq  t1, t4, parse_imm_char_bs
    li   t4, 39
    beq  t1, t4, parse_imm_char_q
    jmp  parse_imm_fail
parse_imm_char_nl:
    li   a0, 10
    jmp  parse_imm_char_ok
parse_imm_char_tab:
    li   a0, 9
    jmp  parse_imm_char_ok
parse_imm_char_cr:
    li   a0, 13
    jmp  parse_imm_char_ok
parse_imm_char_nul:
    li   a0, 0
    jmp  parse_imm_char_ok
parse_imm_char_bs:
    li   a0, 92
    jmp  parse_imm_char_ok
parse_imm_char_q:
    li   a0, 39
parse_imm_char_ok:
    li   a1, 1
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
parse_imm_fail:
    li   a0, 0
    li   a1, 0
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

; ============================================================
; Etiket (label) tablosu: 128 slot, isim basina 32 byte (null-terminated,
; kirpilmis 31 karakter), adres basina 4 byte, ayri bir sayac (NLABELS).
; ============================================================

; --- find_label: a0=name ptr -> a0=index(>=0) veya -1 ---
find_label:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   s1, 4(sp)
    mov  t6, a0
    lli  t5, NLABELS
    lw   t5, 0(t5)
    li   t4, 0
    lli  s1, LABEL_NAMES
find_label_loop:
    beq  t4, t5, find_label_notfound
    li   t0, 32
    mul  t1, t4, t0
    add  t1, s1, t1
    mov  a0, t6
    mov  a1, t1
    call streq
    bne  a0, zero, find_label_found
    addi t4, t4, 1
    jmp  find_label_loop
find_label_found:
    mov  a0, t4
    jmp  find_label_ret
find_label_notfound:
    li   a0, -1
find_label_ret:
    lw   ra, 0(sp)
    lw   s1, 4(sp)
    addi sp, sp, 8
    ret

; --- add_label: a0=name ptr, a1=addr deger -> a0=1 basari / 0 hata (mukerrer/dolu) ---
add_label:
    addi sp, sp, -16
    sw   ra, 0(sp)
    sw   s1, 4(sp)
    sw   a0, 8(sp)
    sw   a1, 12(sp)
    call find_label
    li   t0, -1
    bne  a0, t0, add_label_dup
    lli  t5, NLABELS
    lw   t4, 0(t5)
    li   t0, 200
    bge  t4, t0, add_label_full
    lli  s1, LABEL_NAMES
    li   t0, 32
    mul  t1, t4, t0
    add  t1, s1, t1
    lw   a0, 8(sp)
    li   t2, 0
add_label_copy_loop:
    li   t0, 31
    beq  t2, t0, add_label_copy_done
    add  t3, a0, t2
    lb   t3, 0(t3)
    beq  t3, zero, add_label_copy_done
    add  t0, t1, t2
    sb   t3, 0(t0)
    addi t2, t2, 1
    jmp  add_label_copy_loop
add_label_copy_done:
    add  t0, t1, t2
    sb   zero, 0(t0)
    lli  s1, LABEL_ADDRS
    lw   t4, 0(t5)
    li   t0, 4
    mul  t3, t4, t0
    add  t3, s1, t3
    lw   a1, 12(sp)
    sw   a1, 0(t3)
    addi t4, t4, 1
    sw   t4, 0(t5)
    li   a0, 1
    jmp  add_label_ret
add_label_dup:
    li   a0, 0
    jmp  add_label_ret
add_label_full:
    li   a0, 0
add_label_ret:
    lw   ra, 0(sp)
    lw   s1, 4(sp)
    addi sp, sp, 16
    ret

; --- label_addr: a0=index -> a0=o etiketin adresi ---
label_addr:
    lli  t0, LABEL_ADDRS
    li   t1, 4
    mul  t1, a0, t1
    add  t0, t0, t1
    lw   a0, 0(t0)
    ret

; --- reg_index: a0=null-terminated token -> a0=0..15 register no, -1 gecersiz ---
reg_index:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    lb   t0, 0(a0)
    li   t1, 120
    bne  t0, t1, reg_index_abi
    addi t2, a0, 1
    li   t4, 0
    li   t5, 0
reg_index_x_loop:
    lb   t0, 0(t2)
    beq  t0, zero, reg_index_x_end
    mov  a0, t0
    call is_digit
    beq  a0, zero, reg_index_abi
    lb   t0, 0(t2)
    addi t0, t0, -48
    li   t3, 10
    mul  t4, t4, t3
    add  t4, t4, t0
    addi t2, t2, 1
    addi t5, t5, 1
    jmp  reg_index_x_loop
reg_index_x_end:
    beq  t5, zero, reg_index_abi
    li   t0, 0
    blt  t4, t0, reg_index_bad
    li   t0, 16
    bge  t4, t0, reg_index_bad
    mov  a0, t4
    lw   ra, 0(sp)
    addi sp, sp, 8
    ret
reg_index_abi:
    lw   t6, 4(sp)
    li   t5, 0
    lli  t4, REG_ABI_TABLE
reg_index_abi_loop:
    li   t0, 16
    beq  t5, t0, reg_index_bad
    li   t1, 4
    mul  t1, t5, t1
    add  t1, t4, t1
    lw   t1, 0(t1)
    mov  a0, t6
    mov  a1, t1
    call streq
    bne  a0, zero, reg_index_abi_found
    addi t5, t5, 1
    jmp  reg_index_abi_loop
reg_index_abi_found:
    mov  a0, t5
    lw   ra, 0(sp)
    addi sp, sp, 8
    ret
reg_index_bad:
    li   a0, -1
    lw   ra, 0(sp)
    addi sp, sp, 8
    ret

; --- check_range: a0=deger, a1=lo, a2=hi. Aralik disindaysa hata basip halt eder ---
check_range:
    blt  a0, a1, check_range_bad
    blt  a2, a0, check_range_bad
    ret
check_range_bad:
    lli  a0, err_range
    call print_str
    li   a0, 1
    sw   a0, MMIO_EXIT(s0)

; --- resolve_operand: a0=token, a1=cur_addr, a2=pcrel(0/1) -> a0=deger, a1=1/0 basari ---
resolve_operand:
    addi sp, sp, -16
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    sw   a1, 8(sp)
    sw   a2, 12(sp)
    call find_label
    li   t0, -1
    beq  a0, t0, resolve_operand_try_imm
    call label_addr
    mov  t1, a0
    lw   t2, 8(sp)
    lw   t3, 12(sp)
    beq  t3, zero, resolve_operand_abs
    sub  t1, t1, t2
resolve_operand_abs:
    mov  a0, t1
    li   a1, 1
    lw   ra, 0(sp)
    addi sp, sp, 16
    ret
resolve_operand_try_imm:
    lw   a0, 4(sp)
    call parse_imm
    lw   ra, 0(sp)
    addi sp, sp, 16
    ret

; --- parse_mem: a0=token ("imm(reg)") -> a0=imm deger, a1=reg no, a2=1/0 basari ---
parse_mem:
    addi sp, sp, -12
    sw   ra, 0(sp)
    mov  t6, a0
    li   a1, 40
    call find_char
    beq  a0, zero, parse_mem_fail
    mov  t2, a0
    addi t3, t2, 1
    mov  a0, t3
    li   a1, 41
    call find_char
    beq  a0, zero, parse_mem_fail
    mov  t3, a0
    sb   zero, 0(t2)
    sb   zero, 0(t3)
    addi t4, t2, 1
    sw   t4, 4(sp)
    mov  a0, t6
    call trim
    mov  t6, a0
    lb   t0, 0(t6)
    beq  t0, zero, parse_mem_imm_zero
    mov  a0, t6
    call parse_imm
    beq  a1, zero, parse_mem_try_label
    mov  t5, a0
    jmp  parse_mem_have_imm
parse_mem_try_label:
    mov  a0, t6
    call find_label
    li   t0, -1
    beq  a0, t0, parse_mem_fail
    call label_addr
    mov  t5, a0
    jmp  parse_mem_have_imm
parse_mem_imm_zero:
    li   t5, 0
parse_mem_have_imm:
    sw   t5, 8(sp)
    lw   a0, 4(sp)
    call reg_index
    lw   t5, 8(sp)
    li   t0, -1
    beq  a0, t0, parse_mem_fail
    mov  a1, a0
    mov  a0, t5
    li   a2, 1
    lw   ra, 0(sp)
    addi sp, sp, 12
    ret
parse_mem_fail:
    li   a2, 0
    lw   ra, 0(sp)
    addi sp, sp, 12
    ret

; ============================================================
; Bit-paketleme (nevex_enc_r/i/s/j portu) ve OUT_BUF'a yazma
; ============================================================

; --- asm_r: a0=rd,a1=rs1,a2=rs2,a3=funct -> a0=encoded word (opcode her zaman 0) ---
asm_r:
    li   t0, 22
    sll  t1, a0, t0
    li   t0, 18
    sll  t2, a1, t0
    or   t1, t1, t2
    li   t0, 14
    sll  t2, a2, t0
    or   t1, t1, t2
    li   t0, 8
    sll  t2, a3, t0
    or   t1, t1, t2
    mov  a0, t1
    ret

; --- asm_i: a0=op,a1=rd,a2=rs1,a3=imm14 -> a0=encoded word ---
asm_i:
    li   t0, 26
    sll  t1, a0, t0
    li   t0, 22
    sll  t2, a1, t0
    or   t1, t1, t2
    li   t0, 18
    sll  t2, a2, t0
    or   t1, t1, t2
    li   t0, 1
    li   t3, 14
    sll  t0, t0, t3
    addi t0, t0, -1
    and  t2, a3, t0
    or   t1, t1, t2
    mov  a0, t1
    ret

; --- asm_s: a0=op,a1=rs1,a2=rs2,a3=imm18 -> a0=encoded word ---
asm_s:
    li   t0, 26
    sll  t1, a0, t0
    li   t0, 14
    sra  t2, a3, t0
    li   t0, 15
    and  t2, t2, t0
    li   t0, 22
    sll  t2, t2, t0
    or   t1, t1, t2
    li   t0, 18
    sll  t2, a1, t0
    or   t1, t1, t2
    li   t0, 14
    sll  t2, a2, t0
    or   t1, t1, t2
    li   t0, 1
    li   t3, 14
    sll  t0, t0, t3
    addi t0, t0, -1
    and  t2, a3, t0
    or   t1, t1, t2
    mov  a0, t1
    ret

; --- asm_j: a0=op,a1=rd,a2=imm22 -> a0=encoded word ---
asm_j:
    li   t0, 26
    sll  t1, a0, t0
    li   t0, 22
    sll  t2, a1, t0
    or   t1, t1, t2
    li   t0, 1
    li   t3, 22
    sll  t0, t0, t3
    addi t0, t0, -1
    and  t2, a2, t0
    or   t1, t1, t2
    mov  a0, t1
    ret

; --- split_hi_lo: a0=v(32bit) -> a0=hi, a1=lo (lli/LUI+ADDI parcalari) ---
split_hi_lo:
    li   t0, 18
    sll  t1, a0, t0
    sra  t1, t1, t0
    sub  t2, a0, t1
    li   t0, 14
    sra  t2, t2, t0
    mov  a1, t1
    mov  a0, t2
    ret

; --- emit_word: a0=addr,a1=deger -> OUT_BUF'a 4 byte little-endian yazar ---
emit_word:
    lli  t0, OUT_BUF
    add  t0, t0, a0
    sb   a1, 0(t0)
    li   t1, 8
    sra  t2, a1, t1
    sb   t2, 1(t0)
    li   t1, 16
    sra  t2, a1, t1
    sb   t2, 2(t0)
    li   t1, 24
    sra  t2, a1, t1
    sb   t2, 3(t0)
    ret

; --- emit_asciz: a0=addr, a1=ham metin ptr (kacislarla) -> OUT_BUF'a unescape'lenmis
;     bytelari + sonunda 0 byte yazar ---
emit_asciz:
    lli  t0, OUT_BUF
    add  t0, t0, a0
    mov  t1, a1
emit_asciz_loop:
    lb   t2, 0(t1)
    beq  t2, zero, emit_asciz_done
    li   t3, 92
    bne  t2, t3, emit_asciz_plain
    lb   t4, 1(t1)
    beq  t4, zero, emit_asciz_plain
    li   t5, 110
    beq  t4, t5, emit_asciz_nl
    li   t5, 116
    beq  t4, t5, emit_asciz_tab
    li   t5, 114
    beq  t4, t5, emit_asciz_cr
    li   t5, 48
    beq  t4, t5, emit_asciz_nul
    li   t5, 92
    beq  t4, t5, emit_asciz_bs
    li   t5, 34
    beq  t4, t5, emit_asciz_quote
    sb   t4, 0(t0)
    addi t0, t0, 1
    addi t1, t1, 2
    jmp  emit_asciz_loop
emit_asciz_nl:
    li   t5, 10
    jmp  emit_asciz_store_esc
emit_asciz_tab:
    li   t5, 9
    jmp  emit_asciz_store_esc
emit_asciz_cr:
    li   t5, 13
    jmp  emit_asciz_store_esc
emit_asciz_nul:
    li   t5, 0
    jmp  emit_asciz_store_esc
emit_asciz_bs:
    li   t5, 92
    jmp  emit_asciz_store_esc
emit_asciz_quote:
    li   t5, 34
emit_asciz_store_esc:
    sb   t5, 0(t0)
    addi t0, t0, 1
    addi t1, t1, 2
    jmp  emit_asciz_loop
emit_asciz_plain:
    sb   t2, 0(t0)
    addi t0, t0, 1
    addi t1, t1, 1
    jmp  emit_asciz_loop
emit_asciz_done:
    sb   zero, 0(t0)
    ret

; ============================================================
; Genel encode yardimcilari: bir STMT_TABLE kaydini (record_ptr) alip
; operandlari cozer, encode eder, OUT_BUF'a yazar.
; Record alan ofsetleri: 0=kind 4=noperands 8=addr 12=mnemonic_off
; 16=op0 20=op1 24=op2 28=op3 32=value
; ============================================================

; --- encode_rtype: a0=record_ptr, a1=funct (rd,rs1,rs2 operandlari; opcode=0) ---
encode_rtype:
    addi sp, sp, -24
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    sw   a1, 8(sp)
    lw   a0, 16(a0)
    call reg_index
    sw   a0, 12(sp)
    lw   a0, 4(sp)
    lw   a0, 20(a0)
    call reg_index
    sw   a0, 16(sp)
    lw   a0, 4(sp)
    lw   a0, 24(a0)
    call reg_index
    sw   a0, 20(sp)
    lw   a0, 12(sp)
    lw   a1, 16(sp)
    lw   a2, 20(sp)
    lw   a3, 8(sp)
    call asm_r
    mov  t0, a0
    lw   a0, 4(sp)
    lw   a0, 8(a0)
    mov  a1, t0
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 24
    ret

; --- encode_itype_alu: a0=record_ptr, a1=opcode (rd,rs1,imm14 operandlari) ---
encode_itype_alu:
    addi sp, sp, -28
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    sw   a1, 8(sp)
    lw   a0, 16(a0)
    call reg_index
    sw   a0, 12(sp)
    lw   a0, 4(sp)
    lw   a0, 20(a0)
    call reg_index
    sw   a0, 16(sp)
    lw   t1, 4(sp)
    lw   t2, 8(t1)
    sw   t2, 20(sp)
    lw   a0, 24(t1)
    mov  a1, t2
    li   a2, 0
    call resolve_operand
    lli  a1, -8192
    li   a2, 8191
    call check_range
    sw   a0, 24(sp)
    lw   a0, 8(sp)
    lw   a1, 12(sp)
    lw   a2, 16(sp)
    lw   a3, 24(sp)
    call asm_i
    mov  t0, a0
    lw   a0, 20(sp)
    mov  a1, t0
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 28
    ret

; --- encode_load: a0=record_ptr, a1=opcode (rd,mem(op1) operandlari, imm14) ---
encode_load:
    addi sp, sp, -24
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    sw   a1, 8(sp)
    lw   a0, 16(a0)
    call reg_index
    sw   a0, 12(sp)
    lw   t1, 4(sp)
    lw   a0, 20(t1)
    call parse_mem
    beq  a2, zero, encode_memop_bad
    sw   a1, 20(sp)
    lli  a1, -8192
    li   a2, 8191
    call check_range
    sw   a0, 16(sp)
    lw   a0, 8(sp)
    lw   a1, 12(sp)
    lw   a2, 20(sp)
    lw   a3, 16(sp)
    call asm_i
    mov  t0, a0
    lw   a0, 4(sp)
    lw   a0, 8(a0)
    mov  a1, t0
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 24
    ret
encode_memop_bad:
    lli  a0, err_memop
    call print_str
    li   a0, 1
    sw   a0, MMIO_EXIT(s0)

; --- encode_store: a0=record_ptr, a1=opcode (op0=deger reg, op1=mem, imm18) ---
encode_store:
    addi sp, sp, -24
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    sw   a1, 8(sp)
    lw   a0, 16(a0)
    call reg_index
    sw   a0, 12(sp)
    lw   t1, 4(sp)
    lw   a0, 20(t1)
    call parse_mem
    beq  a2, zero, encode_memop_bad
    sw   a1, 20(sp)
    lli  a1, -131072
    lli  a2, 131071
    call check_range
    sw   a0, 16(sp)
    lw   a0, 8(sp)
    lw   a1, 20(sp)
    lw   a2, 12(sp)
    lw   a3, 16(sp)
    call asm_s
    mov  t0, a0
    lw   a0, 4(sp)
    lw   a0, 8(a0)
    mov  a1, t0
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 24
    ret

; --- encode_branch: a0=record_ptr, a1=opcode (rs1,rs2,etiket(pcrel) operandlari) ---
encode_branch:
    addi sp, sp, -28
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    sw   a1, 8(sp)
    lw   a0, 16(a0)
    call reg_index
    sw   a0, 12(sp)
    lw   a0, 4(sp)
    lw   a0, 20(a0)
    call reg_index
    sw   a0, 16(sp)
    lw   t1, 4(sp)
    lw   t2, 8(t1)
    sw   t2, 20(sp)
    lw   a0, 24(t1)
    mov  a1, t2
    li   a2, 1
    call resolve_operand
    lli  a1, -131072
    lli  a2, 131071
    call check_range
    sw   a0, 24(sp)
    lw   a0, 8(sp)
    lw   a1, 12(sp)
    lw   a2, 16(sp)
    lw   a3, 24(sp)
    call asm_s
    mov  t0, a0
    lw   a0, 20(sp)
    mov  a1, t0
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 28
    ret

; --- encode_jal: a0=record_ptr (rd, etiket(pcrel) operandlari) ---
encode_jal:
    addi sp, sp, -20
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    lw   a0, 16(a0)
    call reg_index
    sw   a0, 8(sp)
    lw   t1, 4(sp)
    lw   t2, 8(t1)
    sw   t2, 12(sp)
    lw   a0, 20(t1)
    mov  a1, t2
    li   a2, 1
    call resolve_operand
    lli  a1, -2097152
    lli  a2, 2097151
    call check_range
    sw   a0, 16(sp)
    li   a0, 19
    lw   a1, 8(sp)
    lw   a2, 16(sp)
    call asm_j
    mov  t0, a0
    lw   a0, 12(sp)
    mov  a1, t0
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 20
    ret

; --- encode_jalr: a0=record_ptr (rd,rs1,imm14 operandlari) ---
encode_jalr:
    addi sp, sp, -24
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    lw   a0, 16(a0)
    call reg_index
    sw   a0, 8(sp)
    lw   a0, 4(sp)
    lw   a0, 20(a0)
    call reg_index
    sw   a0, 12(sp)
    lw   t1, 4(sp)
    lw   t2, 8(t1)
    sw   t2, 16(sp)
    lw   a0, 24(t1)
    mov  a1, t2
    li   a2, 0
    call resolve_operand
    lli  a1, -8192
    li   a2, 8191
    call check_range
    sw   a0, 20(sp)
    li   a0, 20
    lw   a1, 8(sp)
    lw   a2, 12(sp)
    lw   a3, 20(sp)
    call asm_i
    mov  t0, a0
    lw   a0, 16(sp)
    mov  a1, t0
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 24
    ret

; --- encode_lui: a0=record_ptr (rd, imm22 operandlari) ---
encode_lui:
    addi sp, sp, -20
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    lw   a0, 16(a0)
    call reg_index
    sw   a0, 8(sp)
    lw   t1, 4(sp)
    lw   t2, 8(t1)
    sw   t2, 12(sp)
    lw   a0, 20(t1)
    mov  a1, t2
    li   a2, 0
    call resolve_operand
    lli  a1, -2097152
    lli  a2, 2097151
    call check_range
    sw   a0, 16(sp)
    li   a0, 21
    lw   a1, 8(sp)
    lw   a2, 16(sp)
    call asm_j
    mov  t0, a0
    lw   a0, 12(sp)
    mov  a1, t0
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 20
    ret

; --- encode_noopnd: a0=record_ptr, a1=opcode (ecall/mret/halt: operandsiz) ---
encode_noopnd:
    addi sp, sp, -4
    sw   ra, 0(sp)
    mov  t0, a0
    li   t1, 26
    sll  t2, a1, t1
    lw   a0, 8(t0)
    mov  a1, t2
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

; --- encode_nop: a0=record_ptr ---
encode_nop:
    addi sp, sp, -4
    sw   ra, 0(sp)
    mov  t0, a0
    li   a0, 1
    li   a1, 0
    li   a2, 0
    li   a3, 0
    call asm_i
    mov  t1, a0
    lw   a0, 8(t0)
    mov  a1, t1
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

; --- encode_li: a0=record_ptr (rd, imm14 operandlari) ---
encode_li:
    addi sp, sp, -20
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    lw   a0, 16(a0)
    call reg_index
    sw   a0, 8(sp)
    lw   t1, 4(sp)
    lw   t2, 8(t1)
    sw   t2, 12(sp)
    lw   a0, 20(t1)
    mov  a1, t2
    li   a2, 0
    call resolve_operand
    lli  a1, -8192
    li   a2, 8191
    call check_range
    sw   a0, 16(sp)
    li   a0, 1
    lw   a1, 8(sp)
    li   a2, 0
    lw   a3, 16(sp)
    call asm_i
    mov  t0, a0
    lw   a0, 12(sp)
    mov  a1, t0
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 20
    ret

; --- encode_mov: a0=record_ptr (rd, rs operandlari) ---
encode_mov:
    addi sp, sp, -12
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    lw   a0, 16(a0)
    call reg_index
    sw   a0, 8(sp)
    lw   a0, 4(sp)
    lw   a0, 20(a0)
    call reg_index
    mov  t1, a0
    li   a0, 1
    lw   a1, 8(sp)
    mov  a2, t1
    li   a3, 0
    call asm_i
    mov  t0, a0
    lw   a0, 4(sp)
    lw   a0, 8(a0)
    mov  a1, t0
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 12
    ret

; --- encode_jmp: a0=record_ptr (etiket(pcrel) operandi) ---
encode_jmp:
    addi sp, sp, -16
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    lw   t2, 8(a0)
    sw   t2, 8(sp)
    lw   a0, 16(a0)
    mov  a1, t2
    li   a2, 1
    call resolve_operand
    lli  a1, -2097152
    lli  a2, 2097151
    call check_range
    sw   a0, 12(sp)
    li   a0, 19
    li   a1, 0
    lw   a2, 12(sp)
    call asm_j
    mov  t0, a0
    lw   a0, 8(sp)
    mov  a1, t0
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 16
    ret

; --- encode_call: a0=record_ptr (etiket(pcrel) operandi) ---
encode_call:
    addi sp, sp, -16
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    lw   t2, 8(a0)
    sw   t2, 8(sp)
    lw   a0, 16(a0)
    mov  a1, t2
    li   a2, 1
    call resolve_operand
    lli  a1, -2097152
    lli  a2, 2097151
    call check_range
    sw   a0, 12(sp)
    li   a0, 19
    li   a1, 1
    lw   a2, 12(sp)
    call asm_j
    mov  t0, a0
    lw   a0, 8(sp)
    mov  a1, t0
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 16
    ret

; --- encode_ret: a0=record_ptr (operandsiz) ---
encode_ret:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    mov  t0, a0
    li   a0, 20
    li   a1, 0
    li   a2, 1
    li   a3, 0
    call asm_i
    mov  t1, a0
    lw   t0, 4(sp)
    lw   a0, 8(t0)
    mov  a1, t1
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 8
    ret

; --- encode_word: a0=record_ptr (.word: op0=deger/etiket) ---
encode_word:
    addi sp, sp, -12
    sw   ra, 0(sp)
    lw   t2, 8(a0)
    sw   t2, 4(sp)
    lw   a0, 16(a0)
    mov  a1, t2
    li   a2, 0
    call resolve_operand
    mov  a1, a0
    lw   a0, 4(sp)
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 12
    ret

; --- encode_lli_stmt: a0=record_ptr (LLI: rd, 32-bit deger/etiket, 2 kelime) ---
encode_lli_stmt:
    addi sp, sp, -20
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    lw   a0, 16(a0)
    call reg_index
    sw   a0, 8(sp)
    lw   t1, 4(sp)
    lw   t2, 8(t1)
    sw   t2, 12(sp)
    lw   a0, 20(t1)
    mov  a1, t2
    li   a2, 0
    call resolve_operand
    call split_hi_lo
    sw   a1, 16(sp)
    mov  t3, a0
    li   a0, 21
    lw   a1, 8(sp)
    mov  a2, t3
    call asm_j
    mov  t0, a0
    lw   a0, 12(sp)
    mov  a1, t0
    call emit_word
    li   a0, 1
    lw   a1, 8(sp)
    lw   a2, 8(sp)
    lw   a3, 16(sp)
    call asm_i
    mov  t0, a0
    lw   a0, 12(sp)
    addi a0, a0, 4
    mov  a1, t0
    call emit_word
    lw   ra, 0(sp)
    addi sp, sp, 20
    ret

; --- encode_instr: a0=record_ptr (kind=0 satirlarini mnemonic'e gore dispatch eder) ---
encode_instr:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   a0, 4(sp)
    lw   a0, 12(a0)

    lli  a1, mn_add
    call streq
    beq  a0, zero, ei_1
    lw   a0, 4(sp)
    li   a1, 0
    call encode_rtype
    jmp  encode_instr_ret
ei_1:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_sub
    call streq
    beq  a0, zero, ei_2
    lw   a0, 4(sp)
    li   a1, 1
    call encode_rtype
    jmp  encode_instr_ret
ei_2:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_mul
    call streq
    beq  a0, zero, ei_3
    lw   a0, 4(sp)
    li   a1, 2
    call encode_rtype
    jmp  encode_instr_ret
ei_3:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_and
    call streq
    beq  a0, zero, ei_4
    lw   a0, 4(sp)
    li   a1, 3
    call encode_rtype
    jmp  encode_instr_ret
ei_4:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_or
    call streq
    beq  a0, zero, ei_5
    lw   a0, 4(sp)
    li   a1, 4
    call encode_rtype
    jmp  encode_instr_ret
ei_5:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_xor
    call streq
    beq  a0, zero, ei_6
    lw   a0, 4(sp)
    li   a1, 5
    call encode_rtype
    jmp  encode_instr_ret
ei_6:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_sll
    call streq
    beq  a0, zero, ei_7
    lw   a0, 4(sp)
    li   a1, 6
    call encode_rtype
    jmp  encode_instr_ret
ei_7:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_srl
    call streq
    beq  a0, zero, ei_8
    lw   a0, 4(sp)
    li   a1, 7
    call encode_rtype
    jmp  encode_instr_ret
ei_8:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_sra
    call streq
    beq  a0, zero, ei_9
    lw   a0, 4(sp)
    li   a1, 8
    call encode_rtype
    jmp  encode_instr_ret
ei_9:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_slt
    call streq
    beq  a0, zero, ei_10
    lw   a0, 4(sp)
    li   a1, 9
    call encode_rtype
    jmp  encode_instr_ret
ei_10:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_sltu
    call streq
    beq  a0, zero, ei_11
    lw   a0, 4(sp)
    li   a1, 10
    call encode_rtype
    jmp  encode_instr_ret
ei_11:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_div
    call streq
    beq  a0, zero, ei_12
    lw   a0, 4(sp)
    li   a1, 11
    call encode_rtype
    jmp  encode_instr_ret
ei_12:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_rem
    call streq
    beq  a0, zero, ei_13
    lw   a0, 4(sp)
    li   a1, 12
    call encode_rtype
    jmp  encode_instr_ret
ei_13:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_divu
    call streq
    beq  a0, zero, ei_14
    lw   a0, 4(sp)
    li   a1, 13
    call encode_rtype
    jmp  encode_instr_ret
ei_14:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_remu
    call streq
    beq  a0, zero, ei_15
    lw   a0, 4(sp)
    li   a1, 14
    call encode_rtype
    jmp  encode_instr_ret

ei_15:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_addi
    call streq
    beq  a0, zero, ei_16
    lw   a0, 4(sp)
    li   a1, 1
    call encode_itype_alu
    jmp  encode_instr_ret
ei_16:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_andi
    call streq
    beq  a0, zero, ei_17
    lw   a0, 4(sp)
    li   a1, 2
    call encode_itype_alu
    jmp  encode_instr_ret
ei_17:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_ori
    call streq
    beq  a0, zero, ei_18
    lw   a0, 4(sp)
    li   a1, 3
    call encode_itype_alu
    jmp  encode_instr_ret
ei_18:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_xori
    call streq
    beq  a0, zero, ei_19
    lw   a0, 4(sp)
    li   a1, 4
    call encode_itype_alu
    jmp  encode_instr_ret
ei_19:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_slli
    call streq
    beq  a0, zero, ei_20
    lw   a0, 4(sp)
    li   a1, 5
    call encode_itype_alu
    jmp  encode_instr_ret
ei_20:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_srli
    call streq
    beq  a0, zero, ei_21
    lw   a0, 4(sp)
    li   a1, 6
    call encode_itype_alu
    jmp  encode_instr_ret
ei_21:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_srai
    call streq
    beq  a0, zero, ei_22
    lw   a0, 4(sp)
    li   a1, 7
    call encode_itype_alu
    jmp  encode_instr_ret

ei_22:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_lw
    call streq
    beq  a0, zero, ei_23
    lw   a0, 4(sp)
    li   a1, 8
    call encode_load
    jmp  encode_instr_ret
ei_23:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_lb
    call streq
    beq  a0, zero, ei_24
    lw   a0, 4(sp)
    li   a1, 9
    call encode_load
    jmp  encode_instr_ret
ei_24:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_lbu
    call streq
    beq  a0, zero, ei_25
    lw   a0, 4(sp)
    li   a1, 10
    call encode_load
    jmp  encode_instr_ret

ei_25:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_sw
    call streq
    beq  a0, zero, ei_26
    lw   a0, 4(sp)
    li   a1, 11
    call encode_store
    jmp  encode_instr_ret
ei_26:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_sb
    call streq
    beq  a0, zero, ei_27
    lw   a0, 4(sp)
    li   a1, 12
    call encode_store
    jmp  encode_instr_ret

ei_27:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_beq
    call streq
    beq  a0, zero, ei_28
    lw   a0, 4(sp)
    li   a1, 13
    call encode_branch
    jmp  encode_instr_ret
ei_28:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_bne
    call streq
    beq  a0, zero, ei_29
    lw   a0, 4(sp)
    li   a1, 14
    call encode_branch
    jmp  encode_instr_ret
ei_29:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_blt
    call streq
    beq  a0, zero, ei_30
    lw   a0, 4(sp)
    li   a1, 15
    call encode_branch
    jmp  encode_instr_ret
ei_30:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_bge
    call streq
    beq  a0, zero, ei_31
    lw   a0, 4(sp)
    li   a1, 16
    call encode_branch
    jmp  encode_instr_ret
ei_31:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_bltu
    call streq
    beq  a0, zero, ei_32
    lw   a0, 4(sp)
    li   a1, 17
    call encode_branch
    jmp  encode_instr_ret
ei_32:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_bgeu
    call streq
    beq  a0, zero, ei_33
    lw   a0, 4(sp)
    li   a1, 18
    call encode_branch
    jmp  encode_instr_ret

ei_33:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_jal
    call streq
    beq  a0, zero, ei_34
    lw   a0, 4(sp)
    call encode_jal
    jmp  encode_instr_ret
ei_34:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_jalr
    call streq
    beq  a0, zero, ei_35
    lw   a0, 4(sp)
    call encode_jalr
    jmp  encode_instr_ret
ei_35:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_lui
    call streq
    beq  a0, zero, ei_36
    lw   a0, 4(sp)
    call encode_lui
    jmp  encode_instr_ret

ei_36:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_ecall
    call streq
    beq  a0, zero, ei_37
    lw   a0, 4(sp)
    li   a1, 22
    call encode_noopnd
    jmp  encode_instr_ret
ei_37:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_mret
    call streq
    beq  a0, zero, ei_38
    lw   a0, 4(sp)
    li   a1, 23
    call encode_noopnd
    jmp  encode_instr_ret
ei_38:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_halt
    call streq
    beq  a0, zero, ei_39
    lw   a0, 4(sp)
    li   a1, 63
    call encode_noopnd
    jmp  encode_instr_ret

ei_39:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_nop
    call streq
    beq  a0, zero, ei_40
    lw   a0, 4(sp)
    call encode_nop
    jmp  encode_instr_ret
ei_40:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_li
    call streq
    beq  a0, zero, ei_41
    lw   a0, 4(sp)
    call encode_li
    jmp  encode_instr_ret
ei_41:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_mov
    call streq
    beq  a0, zero, ei_42
    lw   a0, 4(sp)
    call encode_mov
    jmp  encode_instr_ret
ei_42:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_jmp
    call streq
    beq  a0, zero, ei_43
    lw   a0, 4(sp)
    call encode_jmp
    jmp  encode_instr_ret
ei_43:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_call
    call streq
    beq  a0, zero, ei_44
    lw   a0, 4(sp)
    call encode_call
    jmp  encode_instr_ret
ei_44:
    lw   a0, 4(sp)
    lw   a0, 12(a0)
    lli  a1, mn_ret
    call streq
    beq  a0, zero, ei_unknown
    lw   a0, 4(sp)
    call encode_ret
    jmp  encode_instr_ret

ei_unknown:
    lli  a0, err_unknown_mn
    call print_str
    li   a0, 1
    sw   a0, MMIO_EXIT(s0)

encode_instr_ret:
    lw   ra, 0(sp)
    addi sp, sp, 8
    ret

; ============================================================
; Pass 2: STMT_TABLE'i tarar, her kayit icin encode_instr/encode_lli_stmt/
; encode_word/emit_asciz cagirir (align/space icin islem gerekmez, OUT_BUF
; zaten sifir).
; ============================================================
pass2:
    addi sp, sp, -4
    sw   ra, 0(sp)
    lli  t0, PASS2_I
    sw   zero, 0(t0)
pass2_loop:
    lli  t0, PASS2_I
    lw   t1, 0(t0)
    lli  t2, NSTMTS
    lw   t2, 0(t2)
    bge  t1, t2, pass2_ret
    lli  t3, STMT_TABLE
    li   t4, 36
    mul  t4, t1, t4
    add  t3, t3, t4
    lw   t5, 0(t3)
    li   t0, 0
    beq  t5, t0, pass2_do_instr
    li   t0, 1
    beq  t5, t0, pass2_do_lli
    li   t0, 2
    beq  t5, t0, pass2_do_word
    li   t0, 3
    beq  t5, t0, pass2_do_asciz
    jmp  pass2_next
pass2_do_instr:
    mov  a0, t3
    call encode_instr
    jmp  pass2_next
pass2_do_lli:
    mov  a0, t3
    call encode_lli_stmt
    jmp  pass2_next
pass2_do_word:
    mov  a0, t3
    call encode_word
    jmp  pass2_next
pass2_do_asciz:
    lw   a1, 16(t3)
    lw   a0, 8(t3)
    call emit_asciz
pass2_next:
    lli  t0, PASS2_I
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)
    jmp  pass2_loop
pass2_ret:
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

; ============================================================
; Built-in semboller (MMIO_*/CAUSE_*/SYS_*/MODE_*/FB_*) etiket tablosuna
; onceden yuklenir - kullanici kodu bunlari normal etiket gibi kullanabilir.
; ============================================================
seed_builtins:
    addi sp, sp, -4
    sw   ra, 0(sp)
    lli  t0, SEED_I
    sw   zero, 0(t0)
seed_builtins_loop:
    lli  t0, SEED_I
    lw   t5, 0(t0)
    li   t1, 38
    beq  t5, t1, seed_builtins_ret
    lli  t4, BUILTIN_TABLE
    li   t1, 8
    mul  t1, t5, t1
    add  t2, t4, t1
    lw   a0, 0(t2)
    lw   a1, 4(t2)
    call add_label
    lli  t0, SEED_I
    lw   t5, 0(t0)
    addi t5, t5, 1
    sw   t5, 0(t0)
    jmp  seed_builtins_loop
seed_builtins_ret:
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

; ============================================================
; Cikti: OUT_BUF[0..CUR_ADDR) MMIO_TX ile stdout'a yazilir.
; ============================================================
emit_output:
    addi sp, sp, -4
    sw   ra, 0(sp)
    lli  t0, CUR_ADDR
    lw   t1, 0(t0)
    lli  t2, OUT_BUF
    li   t3, 0
emit_output_loop:
    beq  t3, t1, emit_output_ret
    add  t4, t2, t3
    lb   a0, 0(t4)
    call putc
    addi t3, t3, 1
    jmp  emit_output_loop
emit_output_ret:
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

; ============================================================
; Girdi okuma: MMIO_STDIN'den EOF'a kadar SRC_BUF'a doldurur.
; '\r' atlanir, sonuna '\0' eklenir. a0 = toplam byte sayisi.
; SRC_BUF sinirini (16384) asarsa hata basip exit(1) yapar.
; ============================================================
read_source:
    addi sp, sp, -4
    sw   ra, 0(sp)
    lli  t0, SRC_BUF
    li   t1, 0
read_source_loop:
    lw   t2, MMIO_STDIN(s0)
    li   t3, -1
    beq  t2, t3, read_source_done
    li   t3, 13
    beq  t2, t3, read_source_loop
    lli  t3, 14335
    blt  t1, t3, read_source_store
    lli  a0, err_src_too_long
    call print_str
    li   a0, 1
    sw   a0, MMIO_EXIT(s0)
read_source_store:
    add  t4, t0, t1
    sb   t2, 0(t4)
    addi t1, t1, 1
    jmp  read_source_loop
read_source_done:
    add  t4, t0, t1
    sb   zero, 0(t4)
    mov  a0, t1
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

; ============================================================
; Tokenize yardimcilari
; ============================================================

; --- strip_comment: a0=ptr, yerinde ';' ya da '#' (tirnak disinda) yorumunu
;     '\0' ile keser ---
strip_comment:
    mov  t0, a0
    li   t1, 0
strip_comment_loop:
    lb   t2, 0(t0)
    beq  t2, zero, strip_comment_ret
    li   t3, 34
    beq  t2, t3, strip_comment_toggle
    bne  t1, zero, strip_comment_next
    li   t3, 59
    beq  t2, t3, strip_comment_cut
    li   t3, 35
    beq  t2, t3, strip_comment_cut
strip_comment_next:
    addi t0, t0, 1
    jmp  strip_comment_loop
strip_comment_toggle:
    li   t3, 1
    sub  t1, t3, t1
    addi t0, t0, 1
    jmp  strip_comment_loop
strip_comment_cut:
    sb   zero, 0(t0)
strip_comment_ret:
    ret

; --- ltrim: a0=ptr -> a0=ptr (bastaki bosluk/tab atlanmis) ---
ltrim:
    addi sp, sp, -4
    sw   ra, 0(sp)
    mov  t6, a0
ltrim_loop:
    lb   a0, 0(t6)
    beq  a0, zero, ltrim_done
    call is_space
    beq  a0, zero, ltrim_done
    addi t6, t6, 1
    jmp  ltrim_loop
ltrim_done:
    mov  a0, t6
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

; --- rtrim: a0=ptr, sondaki bosluk/tab'i yerinde '\0' ile kirpar ---
rtrim:
    addi sp, sp, -4
    sw   ra, 0(sp)
    mov  t6, a0
    mov  t5, a0
rtrim_find_end:
    lb   t0, 0(t5)
    beq  t0, zero, rtrim_have_end
    addi t5, t5, 1
    jmp  rtrim_find_end
rtrim_have_end:
rtrim_back_loop:
    beq  t5, t6, rtrim_ret
    addi t4, t5, -1
    lb   a0, 0(t4)
    call is_space
    beq  a0, zero, rtrim_ret
    sb   zero, 0(t4)
    mov  t5, t4
    jmp  rtrim_back_loop
rtrim_ret:
    mov  a0, t6
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

; --- trim: a0=ptr -> a0=ptr (ltrim+rtrim) ---
trim:
    addi sp, sp, -4
    sw   ra, 0(sp)
    call ltrim
    call rtrim
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

; --- scan_label: a0=ptr -> a0= ilk ':'/bosluk/tab/'\0' konumu ---
scan_label:
    mov  t0, a0
scan_label_loop:
    lb   t1, 0(t0)
    beq  t1, zero, scan_label_ret
    li   t2, 58
    beq  t1, t2, scan_label_ret
    li   t2, 32
    beq  t1, t2, scan_label_ret
    li   t2, 9
    beq  t1, t2, scan_label_ret
    addi t0, t0, 1
    jmp  scan_label_loop
scan_label_ret:
    mov  a0, t0
    ret

; --- scan_ws: a0=ptr -> a0= ilk bosluk/tab/'\0' konumu ---
scan_ws:
    mov  t0, a0
scan_ws_loop:
    lb   t1, 0(t0)
    beq  t1, zero, scan_ws_ret
    li   t2, 32
    beq  t1, t2, scan_ws_ret
    li   t2, 9
    beq  t1, t2, scan_ws_ret
    addi t0, t0, 1
    jmp  scan_ws_loop
scan_ws_ret:
    mov  a0, t0
    ret

; --- valid_label: a0=null-terminated isim -> a0=1/0 ---
valid_label:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   s1, 4(sp)
    mov  s1, a0
    lb   a0, 0(s1)
    beq  a0, zero, valid_label_no
    li   t0, 95
    beq  a0, t0, valid_label_first_ok
    call is_alpha
    beq  a0, zero, valid_label_no
valid_label_first_ok:
    addi s1, s1, 1
valid_label_loop:
    lb   a0, 0(s1)
    beq  a0, zero, valid_label_yes
    call is_alnum_us
    beq  a0, zero, valid_label_no
    addi s1, s1, 1
    jmp  valid_label_loop
valid_label_yes:
    li   a0, 1
    jmp  valid_label_ret
valid_label_no:
    li   a0, 0
valid_label_ret:
    lw   ra, 0(sp)
    lw   s1, 4(sp)
    addi sp, sp, 8
    ret

; --- find_char: a0=ptr, a1=char -> a0=ilk eslesen konum veya 0 ---
find_char:
    mov  t0, a0
find_char_loop:
    lb   t1, 0(t0)
    beq  t1, zero, find_char_notfound
    beq  t1, a1, find_char_found
    addi t0, t0, 1
    jmp  find_char_loop
find_char_found:
    mov  a0, t0
    ret
find_char_notfound:
    li   a0, 0
    ret

; --- find_last_char: a0=ptr, a1=char -> a0=son eslesen konum veya 0 ---
find_last_char:
    mov  t0, a0
    li   t2, 0
find_last_char_loop:
    lb   t1, 0(t0)
    beq  t1, zero, find_last_char_ret
    bne  t1, a1, find_last_char_next
    mov  t2, t0
find_last_char_next:
    addi t0, t0, 1
    jmp  find_last_char_loop
find_last_char_ret:
    mov  a0, t2
    ret

; --- measure_asciz: a0=start, a1=end(haric) -> a0=escape'siz byte sayisi ---
measure_asciz:
    mov  t0, a0
    mov  t1, a1
    li   t2, 0
measure_asciz_loop:
    beq  t0, t1, measure_asciz_ret
    lb   t3, 0(t0)
    li   t4, 92
    bne  t3, t4, measure_asciz_plain
    addi t5, t0, 1
    beq  t5, t1, measure_asciz_plain
    addi t0, t0, 2
    addi t2, t2, 1
    jmp  measure_asciz_loop
measure_asciz_plain:
    addi t0, t0, 1
    addi t2, t2, 1
    jmp  measure_asciz_loop
measure_asciz_ret:
    mov  a0, t2
    ret

; --- split_operands: a0=rest ptr -> PASS1_OP[0..3]/PASS1_NOP'u doldurur.
;     a0=1 basari, 0 = 4'ten fazla operand hatasi ---
split_operands:
    addi sp, sp, -12
    sw   ra, 0(sp)
    mov  t6, a0
    li   t5, 0
    lb   t0, 0(t6)
    beq  t0, zero, split_operands_done
split_operands_loop:
    mov  a0, t6
    call ltrim
    mov  t6, a0
    mov  t4, t6
split_operands_find_comma:
    lb   t0, 0(t4)
    beq  t0, zero, split_operands_last
    li   t1, 44
    beq  t0, t1, split_operands_cut
    addi t4, t4, 1
    jmp  split_operands_find_comma
split_operands_cut:
    sb   zero, 0(t4)
    sw   t4, 4(sp)
    sw   t5, 8(sp)
    mov  a0, t6
    call rtrim
    mov  t6, a0
    lw   t4, 4(sp)
    lw   t5, 8(sp)
    li   t1, 4
    bge  t5, t1, split_operands_toomany
    lli  t2, PASS1_OP
    li   t3, 4
    mul  t3, t5, t3
    add  t2, t2, t3
    sw   t6, 0(t2)
    addi t5, t5, 1
    addi t4, t4, 1
    mov  t6, t4
    jmp  split_operands_loop
split_operands_last:
    sw   t5, 4(sp)
    mov  a0, t6
    call rtrim
    mov  t6, a0
    lw   t5, 4(sp)
    li   t1, 4
    bge  t5, t1, split_operands_toomany
    lli  t2, PASS1_OP
    li   t3, 4
    mul  t3, t5, t3
    add  t2, t2, t3
    sw   t6, 0(t2)
    addi t5, t5, 1
split_operands_done:
    lli  t0, PASS1_NOP
    sw   t5, 0(t0)
    li   a0, 1
    lw   ra, 0(sp)
    addi sp, sp, 12
    ret
split_operands_toomany:
    li   a0, 0
    lw   ra, 0(sp)
    addi sp, sp, 12
    ret

; --- stmt_new: STMT_TABLE[NSTMTS] icin yer ayirir, NSTMTS++ -> a0=kayit adresi (-1=dolu) ---
stmt_new:
    lli  t0, NSTMTS
    lw   t1, 0(t0)
    lli  t2, 550
    bge  t1, t2, stmt_new_full
    lli  t3, STMT_TABLE
    li   t4, 36
    mul  t4, t1, t4
    add  t3, t3, t4
    addi t1, t1, 1
    sw   t1, 0(t0)
    mov  a0, t3
    ret
stmt_new_full:
    li   a0, -1
    ret

; ============================================================
; Pass 1: SRC_BUF'i satir satir tarar, etiketleri LABEL tablosuna,
; komut/direktifleri STMT_TABLE'a kaydeder, CUR_ADDR'i ilerletir.
; ============================================================
pass1:
    addi sp, sp, -4
    sw   ra, 0(sp)
    lli  t0, PASS1_POS
    lli  t1, SRC_BUF
    sw   t1, 0(t0)
    lli  t0, CUR_ADDR
    sw   zero, 0(t0)
pass1_loop:
    lli  t0, CUR_ADDR
    lw   t1, 0(t0)
    lli  t2, 61440
    bge  t1, t2, pass1_err_toolarge
    lli  t0, PASS1_POS
    lw   t1, 0(t0)
    lb   t2, 0(t1)
    beq  t2, zero, pass1_ret
    mov  t3, t1
pass1_find_nl:
    lb   t4, 0(t3)
    beq  t4, zero, pass1_found_end
    li   t5, 10
    beq  t4, t5, pass1_found_nl
    addi t3, t3, 1
    jmp  pass1_find_nl
pass1_found_nl:
    sb   zero, 0(t3)
    addi t5, t3, 1
    jmp  pass1_store_next
pass1_found_end:
    mov  t5, t3
pass1_store_next:
    lli  t0, PASS1_POS
    sw   t5, 0(t0)
    addi sp, sp, -4
    sw   t1, 0(sp)
    mov  a0, t1
    call strip_comment
    lw   t1, 0(sp)
    mov  a0, t1
    call trim
    addi sp, sp, 4
    mov  t6, a0
    lb   t0, 0(t6)
    beq  t0, zero, pass1_loop
    mov  a0, t6
    call scan_label
    mov  t1, a0
    lb   t2, 0(t1)
    li   t3, 58
    bne  t2, t3, pass1_no_label
    sb   zero, 0(t1)
    addi sp, sp, -8
    sw   t1, 0(sp)
    sw   t6, 4(sp)
    mov  a0, t6
    call valid_label
    lw   t6, 4(sp)
    beq  a0, zero, pass1_err_badlabel
    mov  a0, t6
    lli  t0, CUR_ADDR
    lw   a1, 0(t0)
    call add_label
    beq  a0, zero, pass1_err_duplabel
    lw   t1, 0(sp)
    addi sp, sp, 8
    addi t1, t1, 1
    mov  a0, t1
    call trim
    mov  t6, a0
    lb   t0, 0(t6)
    beq  t0, zero, pass1_loop
pass1_no_label:
    mov  a0, t6
    call scan_ws
    mov  t1, a0
    lb   t2, 0(t1)
    beq  t2, zero, pass1_have_rest
    sb   zero, 0(t1)
    addi t1, t1, 1
    addi sp, sp, -4
    sw   t6, 0(sp)
    mov  a0, t1
    call ltrim
    mov  t1, a0
    lw   t6, 0(sp)
    addi sp, sp, 4
pass1_have_rest:
    lli  t0, PASS1_MNEM
    sw   t6, 0(t0)
    lli  t0, PASS1_REST
    sw   t1, 0(t0)

    mov  a0, t6
    lli  a1, dir_word
    call streq
    bne  a0, zero, pass1_do_word

    mov  a0, t6
    lli  a1, dir_asciz
    call streq
    bne  a0, zero, pass1_do_asciz

    mov  a0, t6
    lli  a1, dir_align
    call streq
    bne  a0, zero, pass1_do_align

    mov  a0, t6
    lli  a1, dir_space
    call streq
    bne  a0, zero, pass1_do_space

    jmp  pass1_do_instr

pass1_do_word:
    call stmt_new
    li   t1, -1
    beq  a0, t1, pass1_err_full
    mov  t2, a0
    li   t3, 2
    sw   t3, 0(t2)
    li   t3, 1
    sw   t3, 4(t2)
    lli  t3, CUR_ADDR
    lw   t3, 0(t3)
    sw   t3, 8(t2)
    lli  t4, PASS1_MNEM
    lw   t4, 0(t4)
    sw   t4, 12(t2)
    lli  t4, PASS1_REST
    lw   t4, 0(t4)
    sw   t4, 16(t2)
    lli  t3, CUR_ADDR
    lw   t4, 0(t3)
    addi t4, t4, 4
    sw   t4, 0(t3)
    jmp  pass1_loop

pass1_do_asciz:
    lli  a0, PASS1_REST
    lw   a0, 0(a0)
    li   a1, 34
    call find_char
    beq  a0, zero, pass1_err_asciz
    addi sp, sp, -4
    sw   a0, 0(sp)
    lli  a0, PASS1_REST
    lw   a0, 0(a0)
    li   a1, 34
    call find_last_char
    mov  t3, a0
    lw   t2, 0(sp)
    addi sp, sp, 4
    beq  t3, zero, pass1_err_asciz
    bge  t3, t2, pass1_asciz_have_both
    jmp  pass1_err_asciz
pass1_asciz_have_both:
    sb   zero, 0(t3)
    addi t2, t2, 1
    addi sp, sp, -8
    sw   t2, 0(sp)
    sw   t3, 4(sp)
    mov  a0, t2
    mov  a1, t3
    call measure_asciz
    lw   t2, 0(sp)
    lw   t3, 4(sp)
    addi sp, sp, 8
    addi t4, a0, 1
    addi sp, sp, -12
    sw   t2, 0(sp)
    sw   t3, 4(sp)
    sw   t4, 8(sp)
    call stmt_new
    lw   t2, 0(sp)
    lw   t3, 4(sp)
    lw   t4, 8(sp)
    addi sp, sp, 12
    mov  t5, a0
    li   t1, -1
    beq  t5, t1, pass1_err_full
    li   t1, 3
    sw   t1, 0(t5)
    li   t1, 1
    sw   t1, 4(t5)
    lli  t1, CUR_ADDR
    lw   t1, 0(t1)
    sw   t1, 8(t5)
    lli  t1, PASS1_MNEM
    lw   t1, 0(t1)
    sw   t1, 12(t5)
    sw   t2, 16(t5)
    sw   t4, 32(t5)
    lli  t1, CUR_ADDR
    lw   t6, 0(t1)
    add  t6, t6, t4
    sw   t6, 0(t1)
    jmp  pass1_loop

pass1_do_align:
    lli  a0, PASS1_REST
    lw   a0, 0(a0)
    call parse_imm
    beq  a1, zero, pass1_err_align
    li   t1, 1
    blt  a0, t1, pass1_err_align
    mov  t2, a0
    lli  t3, CUR_ADDR
    lw   t4, 0(t3)
    rem  t5, t4, t2
    sub  t5, t2, t5
    rem  t5, t5, t2
    addi sp, sp, -8
    sw   t4, 0(sp)
    sw   t5, 4(sp)
    call stmt_new
    lw   t4, 0(sp)
    lw   t5, 4(sp)
    addi sp, sp, 8
    li   t1, -1
    beq  a0, t1, pass1_err_full
    mov  t6, a0
    li   t1, 4
    sw   t1, 0(t6)
    sw   zero, 4(t6)
    sw   t4, 8(t6)
    lli  t1, PASS1_MNEM
    lw   t1, 0(t1)
    sw   t1, 12(t6)
    sw   t5, 32(t6)
    lli  t1, CUR_ADDR
    lw   t2, 0(t1)
    add  t2, t2, t5
    sw   t2, 0(t1)
    jmp  pass1_loop

pass1_do_space:
    lli  a0, PASS1_REST
    lw   a0, 0(a0)
    call parse_imm
    beq  a1, zero, pass1_err_space
    blt  a0, zero, pass1_err_space
    mov  t2, a0
    addi sp, sp, -4
    sw   t2, 0(sp)
    call stmt_new
    lw   t2, 0(sp)
    addi sp, sp, 4
    li   t1, -1
    beq  a0, t1, pass1_err_full
    mov  t6, a0
    li   t1, 5
    sw   t1, 0(t6)
    sw   zero, 4(t6)
    lli  t1, CUR_ADDR
    lw   t3, 0(t1)
    sw   t3, 8(t6)
    lli  t1, PASS1_MNEM
    lw   t1, 0(t1)
    sw   t1, 12(t6)
    sw   t2, 32(t6)
    lli  t1, CUR_ADDR
    lw   t3, 0(t1)
    add  t3, t3, t2
    sw   t3, 0(t1)
    jmp  pass1_loop

pass1_do_instr:
    lli  a0, PASS1_REST
    lw   a0, 0(a0)
    call split_operands
    lli  a0, PASS1_MNEM
    lw   a0, 0(a0)
    lli  a1, mn_lli
    call streq
    mov  t2, a0
    addi sp, sp, -4
    sw   t2, 0(sp)
    call stmt_new
    lw   t2, 0(sp)
    addi sp, sp, 4
    li   t1, -1
    beq  a0, t1, pass1_err_full
    mov  t6, a0
    beq  t2, zero, pass1_instr_kind0
    li   t1, 1
    sw   t1, 0(t6)
    li   t3, 8
    jmp  pass1_instr_have_size
pass1_instr_kind0:
    sw   zero, 0(t6)
    li   t3, 4
pass1_instr_have_size:
    lli  t1, PASS1_NOP
    lw   t1, 0(t1)
    sw   t1, 4(t6)
    lli  t1, CUR_ADDR
    lw   t4, 0(t1)
    sw   t4, 8(t6)
    lli  t1, PASS1_MNEM
    lw   t1, 0(t1)
    sw   t1, 12(t6)
    lli  t1, PASS1_OP
    lw   t4, 0(t1)
    sw   t4, 16(t6)
    lw   t4, 4(t1)
    sw   t4, 20(t6)
    lw   t4, 8(t1)
    sw   t4, 24(t6)
    lw   t4, 12(t1)
    sw   t4, 28(t6)
    lli  t1, CUR_ADDR
    lw   t4, 0(t1)
    add  t4, t4, t3
    sw   t4, 0(t1)
    jmp  pass1_loop

pass1_err_badlabel:
    lli  a0, err_badlabel
    call print_str
    li   a0, 1
    sw   a0, MMIO_EXIT(s0)
pass1_err_duplabel:
    lli  a0, err_duplabel
    call print_str
    li   a0, 1
    sw   a0, MMIO_EXIT(s0)
pass1_err_full:
    lli  a0, err_full
    call print_str
    li   a0, 1
    sw   a0, MMIO_EXIT(s0)
pass1_err_asciz:
    lli  a0, err_asciz
    call print_str
    li   a0, 1
    sw   a0, MMIO_EXIT(s0)
pass1_err_align:
    lli  a0, err_align
    call print_str
    li   a0, 1
    sw   a0, MMIO_EXIT(s0)
pass1_err_space:
    lli  a0, err_space
    call print_str
    li   a0, 1
    sw   a0, MMIO_EXIT(s0)
pass1_err_toolarge:
    lli  a0, err_toolarge
    call print_str
    li   a0, 1
    sw   a0, MMIO_EXIT(s0)
pass1_ret:
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

; --- dump_stmts (debug): STMT_TABLE'i insan-okunur sekilde basar ---
dump_stmts:
    addi sp, sp, -4
    sw   ra, 0(sp)
    lli  t0, DUMP_I
    sw   zero, 0(t0)
dump_stmts_loop:
    lli  t0, DUMP_I
    lw   t1, 0(t0)
    lli  t2, NSTMTS
    lw   t2, 0(t2)
    bge  t1, t2, dump_stmts_ret
    lli  t3, STMT_TABLE
    li   t4, 36
    mul  t4, t1, t4
    add  t3, t3, t4
    lli  t0, DUMP_PTR
    sw   t3, 0(t0)

    mov  a0, t1
    call print_dec
    li   a0, 58
    call putc

    lli  t0, DUMP_PTR
    lw   t0, 0(t0)
    lw   a0, 0(t0)
    call print_dec
    li   a0, 32
    call putc

    lli  t0, DUMP_PTR
    lw   t0, 0(t0)
    lw   a0, 8(t0)
    call print_dec
    li   a0, 32
    call putc

    lli  t0, DUMP_PTR
    lw   t0, 0(t0)
    lw   a0, 12(t0)
    call print_str
    li   a0, 32
    call putc

    lli  t0, DUMP_PTR
    lw   t0, 0(t0)
    lw   t5, 4(t0)
    beq  t5, zero, dump_stmts_no_op0
    lli  t0, DUMP_PTR
    lw   t0, 0(t0)
    lw   a0, 16(t0)
    call print_str
dump_stmts_no_op0:
    li   a0, 10
    call putc

    lli  t0, DUMP_I
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)
    jmp  dump_stmts_loop
dump_stmts_ret:
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

start:
    lli  s0, MMIO_BASE
    call seed_builtins
    call read_source
    call pass1
    call pass2
    call emit_output
    li   t0, 0
    sw   t0, MMIO_EXIT(s0)

dbg_mytest_name:
    .asciz "mytest"
dbg_msg_name:
    .asciz "msg"
dbg_mmio_name:
    .asciz "MMIO_BASE"
dbg_printloop_name:
    .asciz "print_loop"
dbg_fbheight_name:
    .asciz "FB_HEIGHT"
dbg_main_name:
    .asciz "main"

.align 4
dbg_reg_s1:
    .asciz "s1"
dbg_reg_x14:
    .asciz "x14"
dbg_reg_bad:
    .asciz "zz"
dbg_mem_a:
    .asciz "4(sp)"
dbg_mem_b:
    .asciz "(t0)"
dbg_split_src:
    .asciz "t0, 5"
dbg_tok_100:
    .asciz "100"
dbg_testlbl:
    .asciz "testlbl"
dbg_hin:
    .asciz "hi\\n"
test_msg:
    .asciz "yardimci rutinler ok: "
tok_123:
    .asciz "123"
tok_neg45:
    .asciz "-45"
tok_hex1f:
    .asciz "0x1F"
tok_char_a:
    .asciz "'a'"
tok_char_nl:
    .asciz "'\n'"
tok_bad:
    .asciz "12x3"
streq_a:
    .asciz "hello"
streq_b:
    .asciz "hello"
streq_c:
    .asciz "world"

lbl_foo:
    .asciz "foo"
lbl_bar:
    .asciz "bar"

.align 4
NLABELS:
    .word 0
LABEL_NAMES:
    .space 6400
LABEL_ADDRS:
    .space 800

err_src_too_long:
    .asciz "HATA: kaynak metni SRC_BUF sinirini asti\n"

.align 4
SRC_BUF:
    .space 14336

reg_n0:
    .asciz "zero"
reg_n1:
    .asciz "ra"
reg_n2:
    .asciz "sp"
reg_n3:
    .asciz "a0"
reg_n4:
    .asciz "a1"
reg_n5:
    .asciz "a2"
reg_n6:
    .asciz "a3"
reg_n7:
    .asciz "t0"
reg_n8:
    .asciz "t1"
reg_n9:
    .asciz "t2"
reg_n10:
    .asciz "t3"
reg_n11:
    .asciz "t4"
reg_n12:
    .asciz "t5"
reg_n13:
    .asciz "t6"
reg_n14:
    .asciz "s0"
reg_n15:
    .asciz "s1"
err_range:
    .asciz "HATA: immediate deger aralik disinda\n"

.align 4
REG_ABI_TABLE:
    .word reg_n0
    .word reg_n1
    .word reg_n2
    .word reg_n3
    .word reg_n4
    .word reg_n5
    .word reg_n6
    .word reg_n7
    .word reg_n8
    .word reg_n9
    .word reg_n10
    .word reg_n11
    .word reg_n12
    .word reg_n13
    .word reg_n14
    .word reg_n15

dir_word:
    .asciz ".word"
dir_asciz:
    .asciz ".asciz"
dir_align:
    .asciz ".align"
dir_space:
    .asciz ".space"
mn_lli:
    .asciz "lli"
mn_add:
    .asciz "add"
mn_sub:
    .asciz "sub"
mn_mul:
    .asciz "mul"
mn_and:
    .asciz "and"
mn_or:
    .asciz "or"
mn_xor:
    .asciz "xor"
mn_sll:
    .asciz "sll"
mn_srl:
    .asciz "srl"
mn_sra:
    .asciz "sra"
mn_slt:
    .asciz "slt"
mn_sltu:
    .asciz "sltu"
mn_div:
    .asciz "div"
mn_rem:
    .asciz "rem"
mn_divu:
    .asciz "divu"
mn_remu:
    .asciz "remu"
mn_addi:
    .asciz "addi"
mn_andi:
    .asciz "andi"
mn_ori:
    .asciz "ori"
mn_xori:
    .asciz "xori"
mn_slli:
    .asciz "slli"
mn_srli:
    .asciz "srli"
mn_srai:
    .asciz "srai"
mn_lw:
    .asciz "lw"
mn_lb:
    .asciz "lb"
mn_lbu:
    .asciz "lbu"
mn_sw:
    .asciz "sw"
mn_sb:
    .asciz "sb"
mn_beq:
    .asciz "beq"
mn_bne:
    .asciz "bne"
mn_blt:
    .asciz "blt"
mn_bge:
    .asciz "bge"
mn_bltu:
    .asciz "bltu"
mn_bgeu:
    .asciz "bgeu"
mn_jal:
    .asciz "jal"
mn_jalr:
    .asciz "jalr"
mn_lui:
    .asciz "lui"
mn_ecall:
    .asciz "ecall"
mn_mret:
    .asciz "mret"
mn_halt:
    .asciz "halt"
mn_nop:
    .asciz "nop"
mn_li:
    .asciz "li"
mn_mov:
    .asciz "mov"
mn_jmp:
    .asciz "jmp"
mn_call:
    .asciz "call"
mn_ret:
    .asciz "ret"

err_memop:
    .asciz "HATA: bellek operandi hatali (beklenen: imm(reg))\n"
err_unknown_mn:
    .asciz "HATA: bilinmeyen mnemonic\n"

bn_mmio_base:     .asciz "MMIO_BASE"
bn_mmio_tx:       .asciz "MMIO_TX"
bn_mmio_exit:     .asciz "MMIO_EXIT"
bn_mmio_mtvec:    .asciz "MMIO_MTVEC"
bn_mmio_mepc:     .asciz "MMIO_MEPC"
bn_mmio_mcause:   .asciz "MMIO_MCAUSE"
bn_mmio_mpp:      .asciz "MMIO_MPP"
bn_mmio_mie:      .asciz "MMIO_MIE"
bn_mmio_mtime:    .asciz "MMIO_MTIME"
bn_mmio_mtimecmp: .asciz "MMIO_MTIMECMP"
bn_mmio_key:      .asciz "MMIO_KEY"
bn_mmio_rand:     .asciz "MMIO_RAND"
bn_mmio_sleep_ms: .asciz "MMIO_SLEEP_MS"
bn_mmio_mouse_x:  .asciz "MMIO_MOUSE_X"
bn_mmio_mouse_y:  .asciz "MMIO_MOUSE_Y"
bn_mmio_mouse_btn: .asciz "MMIO_MOUSE_BTN"
bn_mmio_char_x:   .asciz "MMIO_CHAR_X"
bn_mmio_char_y:   .asciz "MMIO_CHAR_Y"
bn_mmio_char_color: .asciz "MMIO_CHAR_COLOR"
bn_mmio_char_draw: .asciz "MMIO_CHAR_DRAW"
bn_mmio_stdin:    .asciz "MMIO_STDIN"
bn_cause_illegal: .asciz "CAUSE_ILLEGAL_INSTR"
bn_cause_load:    .asciz "CAUSE_LOAD_FAULT"
bn_cause_store:   .asciz "CAUSE_STORE_FAULT"
bn_cause_ecall_u: .asciz "CAUSE_ECALL_FROM_U"
bn_cause_ecall_m: .asciz "CAUSE_ECALL_FROM_M"
bn_cause_timer:   .asciz "CAUSE_TIMER_INTERRUPT"
bn_cause_unaligned: .asciz "CAUSE_UNALIGNED_FETCH"
bn_cause_fetch:   .asciz "CAUSE_FETCH_FAULT"
bn_sys_exit:      .asciz "SYS_EXIT"
bn_sys_print_int: .asciz "SYS_PRINT_INT"
bn_sys_print_char: .asciz "SYS_PRINT_CHAR"
bn_sys_print_str: .asciz "SYS_PRINT_STR"
bn_mode_machine:  .asciz "MODE_MACHINE"
bn_mode_user:     .asciz "MODE_USER"
bn_fb_base:       .asciz "FB_BASE"
bn_fb_width:      .asciz "FB_WIDTH"
bn_fb_height:     .asciz "FB_HEIGHT"

.align 4
BUILTIN_TABLE:
    .word bn_mmio_base
    .word 61440
    .word bn_mmio_tx
    .word 0
    .word bn_mmio_exit
    .word 4
    .word bn_mmio_mtvec
    .word 8
    .word bn_mmio_mepc
    .word 12
    .word bn_mmio_mcause
    .word 16
    .word bn_mmio_mpp
    .word 20
    .word bn_mmio_mie
    .word 24
    .word bn_mmio_mtime
    .word 28
    .word bn_mmio_mtimecmp
    .word 32
    .word bn_mmio_key
    .word 36
    .word bn_mmio_rand
    .word 40
    .word bn_mmio_sleep_ms
    .word 44
    .word bn_mmio_mouse_x
    .word 48
    .word bn_mmio_mouse_y
    .word 52
    .word bn_mmio_mouse_btn
    .word 56
    .word bn_mmio_char_x
    .word 60
    .word bn_mmio_char_y
    .word 64
    .word bn_mmio_char_color
    .word 68
    .word bn_mmio_char_draw
    .word 72
    .word bn_mmio_stdin
    .word 76
    .word bn_cause_illegal
    .word 0
    .word bn_cause_load
    .word 1
    .word bn_cause_store
    .word 2
    .word bn_cause_ecall_u
    .word 3
    .word bn_cause_ecall_m
    .word 4
    .word bn_cause_timer
    .word 5
    .word bn_cause_unaligned
    .word 6
    .word bn_cause_fetch
    .word 7
    .word bn_sys_exit
    .word 0
    .word bn_sys_print_int
    .word 1
    .word bn_sys_print_char
    .word 2
    .word bn_sys_print_str
    .word 3
    .word bn_mode_machine
    .word 0
    .word bn_mode_user
    .word 1
    .word bn_fb_base
    .word 65536
    .word bn_fb_width
    .word 128
    .word bn_fb_height
    .word 128

err_badlabel:
    .asciz "HATA: gecersiz etiket adi\n"
err_duplabel:
    .asciz "HATA: etiket zaten tanimli ya da tablo dolu\n"
err_full:
    .asciz "HATA: cok fazla satir (STMT_TABLE dolu)\n"
err_asciz:
    .asciz "HATA: .asciz bir tirnakli string bekliyor\n"
err_align:
    .asciz "HATA: .align pozitif bir tamsayi bekliyor\n"
err_space:
    .asciz "HATA: .space negatif olmayan bir tamsayi bekliyor\n"
err_toolarge:
    .asciz "HATA: program bellek sinirini asiyor\n"

.align 4
PASS1_POS:
    .word 0
CUR_ADDR:
    .word 0
PASS1_MNEM:
    .word 0
PASS1_REST:
    .word 0
PASS1_OP:
    .space 16
PASS1_NOP:
    .word 0
NSTMTS:
    .word 0
PASS2_I:
    .word 0
SEED_I:
    .word 0
STMT_TABLE:
    .space 19800
.align 4
OUT_BUF:
    .space 8192
DUMP_I:
    .word 0
DUMP_PTR:
    .word 0

; APPEND_MARK
