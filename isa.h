#ifndef NEVEX_ISA_H
#define NEVEX_ISA_H

#include <stdint.h>

#define NEVEX_MEM_SIZE   (64 * 1024)
#define NEVEX_NUM_REGS   16

enum {
    X_ZERO = 0, X_RA = 1, X_SP = 2,
    X_A0 = 3, X_A1 = 4, X_A2 = 5, X_A3 = 6,
    X_T0 = 7, X_T1 = 8, X_T2 = 9, X_T3 = 10,
    X_T4 = 11, X_T5 = 12, X_T6 = 13,
    X_S0 = 14, X_S1 = 15
};

enum {
    OP_R     = 0x00,
    OP_ADDI  = 0x01,
    OP_ANDI  = 0x02,
    OP_ORI   = 0x03,
    OP_XORI  = 0x04,
    OP_SLLI  = 0x05,
    OP_SRLI  = 0x06,
    OP_SRAI  = 0x07,
    OP_LW    = 0x08,
    OP_LB    = 0x09,
    OP_LBU   = 0x0A,
    OP_SW    = 0x0B,
    OP_SB    = 0x0C,
    OP_BEQ   = 0x0D,
    OP_BNE   = 0x0E,
    OP_BLT   = 0x0F,
    OP_BGE   = 0x10,
    OP_BLTU  = 0x11,
    OP_BGEU  = 0x12,
    OP_JAL   = 0x13,
    OP_JALR  = 0x14,
    OP_LUI   = 0x15,
    OP_ECALL = 0x16,
    OP_MRET  = 0x17,
    OP_HALT  = 0x3F
};

enum {
    MODE_MACHINE = 0,
    MODE_USER    = 1
};

enum {
    CAUSE_ILLEGAL_INSTR   = 0,
    CAUSE_LOAD_FAULT      = 1,
    CAUSE_STORE_FAULT     = 2,
    CAUSE_ECALL_FROM_U    = 3,
    CAUSE_ECALL_FROM_M    = 4,
    CAUSE_TIMER_INTERRUPT = 5,
    CAUSE_UNALIGNED_FETCH = 6,
    CAUSE_FETCH_FAULT     = 7
};

#define NEVEX_MMIO_BASE       0xF000u
#define NEVEX_MMIO_TX         0xF000u
#define NEVEX_MMIO_EXIT       0xF004u
#define NEVEX_MMIO_MTVEC      0xF008u
#define NEVEX_MMIO_MEPC       0xF00Cu
#define NEVEX_MMIO_MCAUSE     0xF010u
#define NEVEX_MMIO_MPP        0xF014u
#define NEVEX_MMIO_MIE        0xF018u
#define NEVEX_MMIO_MTIME      0xF01Cu
#define NEVEX_MMIO_MTIMECMP   0xF020u
#define NEVEX_MMIO_KEY        0xF024u
#define NEVEX_MMIO_RAND       0xF028u
#define NEVEX_MMIO_SLEEP_MS   0xF02Cu
#define NEVEX_MMIO_MOUSE_X    0xF030u
#define NEVEX_MMIO_MOUSE_Y    0xF034u
#define NEVEX_MMIO_MOUSE_BTN  0xF038u
#define NEVEX_MMIO_CHAR_X     0xF03Cu
#define NEVEX_MMIO_CHAR_Y     0xF040u
#define NEVEX_MMIO_CHAR_COLOR 0xF044u
#define NEVEX_MMIO_CHAR_DRAW  0xF048u

#define NEVEX_FB_BASE    0x10000u
#define NEVEX_FB_WIDTH   128
#define NEVEX_FB_HEIGHT  128
#define NEVEX_FB_SIZE    (NEVEX_FB_WIDTH * NEVEX_FB_HEIGHT)

enum {
    F_ADD = 0x00, F_SUB = 0x01, F_MUL = 0x02,
    F_AND = 0x03, F_OR  = 0x04, F_XOR = 0x05,
    F_SLL = 0x06, F_SRL = 0x07, F_SRA = 0x08,
    F_SLT = 0x09, F_SLTU = 0x0A,
    F_DIV = 0x0B, F_REM = 0x0C, F_DIVU = 0x0D, F_REMU = 0x0E
};

enum {
    SYS_EXIT = 0,
    SYS_PRINT_INT = 1,
    SYS_PRINT_CHAR = 2,
    SYS_PRINT_STR = 3
};

static inline int32_t nevex_sign_extend(uint32_t value, int bits) {
    uint32_t mask = 1u << (bits - 1);
    value &= (bits == 32) ? 0xFFFFFFFFu : ((1u << bits) - 1u);
    return (int32_t)((value ^ mask) - mask);
}

static inline uint32_t nevex_enc_r(uint8_t op, uint8_t rd, uint8_t rs1, uint8_t rs2, uint8_t funct) {
    return ((uint32_t)op    << 26) |
           ((uint32_t)rd    << 22) |
           ((uint32_t)rs1   << 18) |
           ((uint32_t)rs2   << 14) |
           ((uint32_t)funct << 7);
}

static inline uint32_t nevex_enc_i(uint8_t op, uint8_t rd, uint8_t rs1, int32_t imm) {
    return ((uint32_t)op  << 26) |
           ((uint32_t)rd  << 22) |
           ((uint32_t)rs1 << 18) |
           ((uint32_t)imm & 0x3FFF);
}

static inline uint32_t nevex_enc_s(uint8_t op, uint8_t rs1, uint8_t rs2, int32_t imm) {
    uint32_t imm_hi = ((uint32_t)imm >> 14) & 0xF;
    uint32_t imm_lo = (uint32_t)imm & 0x3FFF;
    return ((uint32_t)op << 26) | (imm_hi << 22) |
           ((uint32_t)rs1 << 18) | ((uint32_t)rs2 << 14) | imm_lo;
}

static inline uint32_t nevex_enc_j(uint8_t op, uint8_t rd, int32_t imm) {
    return ((uint32_t)op << 26) | ((uint32_t)rd << 22) | ((uint32_t)imm & 0x3FFFFF);
}

static inline void nevex_split_hi_lo(int32_t v, int32_t *hi, int32_t *lo) {
    int32_t lo14 = (int32_t)(((uint32_t)v) << 18) >> 18;
    *lo = lo14;
    *hi = (v - lo14) >> 14;
}

#endif
