#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

#include "isa.h"

#define NUM_REGS   NEVEX_NUM_REGS
#define MEM_SIZE   NEVEX_MEM_SIZE

typedef struct {
    uint32_t x[NUM_REGS];
    uint32_t pc;
    int halted;
    int exit_code;

    int mode;
    uint32_t mtvec;
    uint32_t mepc;
    uint32_t mcause;
    int mpp;
    int mie;
    uint32_t mtime;
    uint32_t mtimecmp;

    int trap_pending;
    uint32_t cur_instr_pc;

    uint32_t char_x;
    uint32_t char_x0;
    uint32_t char_y;
    uint32_t char_color;
} CPU;

#define GUI_SCALE 4

static const uint8_t font3x5[59][5] = {
    [' '-32] = {0,0,0,0,0},
    ['!'-32] = {2,2,2,0,2},
    ['.'-32] = {0,0,0,0,2},
    [':'-32] = {0,2,0,2,0},
    ['0'-32] = {7,5,5,5,7},
    ['1'-32] = {2,6,2,2,7},
    ['2'-32] = {7,1,7,4,7},
    ['3'-32] = {7,1,7,1,7},
    ['4'-32] = {5,5,7,1,1},
    ['5'-32] = {7,4,7,1,7},
    ['6'-32] = {7,4,7,5,7},
    ['7'-32] = {7,1,1,1,1},
    ['8'-32] = {7,5,7,5,7},
    ['9'-32] = {7,5,7,1,7},
    ['A'-32] = {2,5,7,5,5},
    ['B'-32] = {6,5,6,5,6},
    ['C'-32] = {3,4,4,4,3},
    ['D'-32] = {6,5,5,5,6},
    ['E'-32] = {7,4,6,4,7},
    ['F'-32] = {7,4,6,4,4},
    ['G'-32] = {3,4,5,5,3},
    ['H'-32] = {5,5,7,5,5},
    ['I'-32] = {7,2,2,2,7},
    ['J'-32] = {1,1,1,5,2},
    ['K'-32] = {5,5,6,5,5},
    ['L'-32] = {4,4,4,4,7},
    ['M'-32] = {5,7,7,5,5},
    ['N'-32] = {5,7,7,7,5},
    ['O'-32] = {2,5,5,5,2},
    ['P'-32] = {6,5,6,4,4},
    ['Q'-32] = {2,5,5,7,3},
    ['R'-32] = {6,5,6,5,5},
    ['S'-32] = {3,4,2,1,6},
    ['T'-32] = {7,2,2,2,2},
    ['U'-32] = {5,5,5,5,7},
    ['V'-32] = {5,5,5,5,2},
    ['W'-32] = {5,5,7,7,5},
    ['X'-32] = {5,5,2,5,5},
    ['Y'-32] = {5,5,2,2,2},
    ['Z'-32] = {7,1,2,4,7},
};

static uint8_t mem[MEM_SIZE];
static uint8_t fb[NEVEX_FB_SIZE];
static int fb_dirty = 0;
static int gui_last_key = 0;
#ifdef NEVEX_GUI
static int gui_quit_requested = 0;
#endif
static int gui_mouse_x = 0;
static int gui_mouse_y = 0;
static int gui_mouse_btn = 0;

#ifdef NEVEX_GUI
static int gui_present(void);
#endif

static uint32_t reg_read(const CPU *cpu, unsigned idx) {
    return (idx == X_ZERO) ? 0u : cpu->x[idx];
}

static void reg_write(CPU *cpu, unsigned idx, uint32_t val) {
    if (idx != X_ZERO) cpu->x[idx] = val;
}

static void panic(CPU *cpu, const char *msg) {
    fprintf(stderr, "\n[nevex] PANIC @ pc=0x%05x: %s\n", cpu->pc, msg);
    fprintf(stderr, "[nevex] registers:\n");
    for (int i = 0; i < NUM_REGS; i++) {
        fprintf(stderr, "  x%-2d = 0x%08x (%d)\n", i, cpu->x[i], (int32_t)cpu->x[i]);
    }
    fprintf(stderr, "  mode=%s mtvec=0x%05x mepc=0x%05x mcause=%u\n",
            cpu->mode == MODE_MACHINE ? "machine" : "user", cpu->mtvec, cpu->mepc, cpu->mcause);
    exit(1);
}

static void take_trap(CPU *cpu, uint32_t cause, uint32_t epc) {
    cpu->mpp = cpu->mode;
    cpu->mepc = epc;
    cpu->mcause = cause;
    cpu->mode = MODE_MACHINE;
    cpu->mie = 0;
    cpu->pc = cpu->mtvec;
    cpu->trap_pending = 1;
}

static void blit_char(CPU *cpu, uint8_t ascii) {
    if (ascii == '\n') {
        cpu->char_x = cpu->char_x0;
        cpu->char_y += 6;
        return;
    }
    if (ascii < 32 || ascii > 90) { cpu->char_x += 4; return; }
    const uint8_t *rows = font3x5[ascii - 32];
    for (int row = 0; row < 5; row++) {
        for (int col = 0; col < 3; col++) {
            if (rows[row] & (4 >> col)) {
                int px = (int)cpu->char_x + col;
                int py = (int)cpu->char_y + row;
                if (px >= 0 && px < NEVEX_FB_WIDTH && py >= 0 && py < NEVEX_FB_HEIGHT) {
                    fb[py * NEVEX_FB_WIDTH + px] = (uint8_t)cpu->char_color;
                    fb_dirty = 1;
                }
            }
        }
    }
    cpu->char_x += 4;
}

static uint32_t mmio_read(CPU *cpu, uint32_t addr) {
    switch (addr) {
        case NEVEX_MMIO_TX:       return 0;
        case NEVEX_MMIO_EXIT:     return 0;
        case NEVEX_MMIO_MTVEC:    return cpu->mtvec;
        case NEVEX_MMIO_MEPC:     return cpu->mepc;
        case NEVEX_MMIO_MCAUSE:   return cpu->mcause;
        case NEVEX_MMIO_MPP:      return (uint32_t)cpu->mpp;
        case NEVEX_MMIO_MIE:      return (uint32_t)cpu->mie;
        case NEVEX_MMIO_MTIME:    return cpu->mtime;
        case NEVEX_MMIO_MTIMECMP: return cpu->mtimecmp;
        case NEVEX_MMIO_KEY:      return (uint32_t)gui_last_key;
        case NEVEX_MMIO_RAND:     return ((uint32_t)rand() << 16) ^ (uint32_t)rand();
        case NEVEX_MMIO_MOUSE_X:  return (uint32_t)gui_mouse_x;
        case NEVEX_MMIO_MOUSE_Y:  return (uint32_t)gui_mouse_y;
        case NEVEX_MMIO_MOUSE_BTN: return (uint32_t)gui_mouse_btn;
        case NEVEX_MMIO_CHAR_X:    return cpu->char_x;
        case NEVEX_MMIO_CHAR_Y:    return cpu->char_y;
        case NEVEX_MMIO_CHAR_COLOR: return cpu->char_color;
        default:
            take_trap(cpu, CAUSE_LOAD_FAULT, cpu->cur_instr_pc);
            return 0;
    }
}

static void mmio_write(CPU *cpu, uint32_t addr, uint32_t val) {
    switch (addr) {
        case NEVEX_MMIO_TX:       putchar((int)(val & 0xFF)); fflush(stdout); return;
        case NEVEX_MMIO_EXIT:     cpu->halted = 1; cpu->exit_code = (int32_t)val; return;
        case NEVEX_MMIO_MTVEC:    cpu->mtvec = val; return;
        case NEVEX_MMIO_MEPC:     cpu->mepc = val; return;
        case NEVEX_MMIO_MCAUSE:   cpu->mcause = val; return;
        case NEVEX_MMIO_MPP:      cpu->mpp = (int)(val & 1u); return;
        case NEVEX_MMIO_MIE:      cpu->mie = (int)(val & 1u); return;
        case NEVEX_MMIO_MTIME:    cpu->mtime = val; return;
        case NEVEX_MMIO_MTIMECMP: cpu->mtimecmp = val; return;
        case NEVEX_MMIO_CHAR_X:   cpu->char_x = val; cpu->char_x0 = val; return;
        case NEVEX_MMIO_CHAR_Y:   cpu->char_y = val; return;
        case NEVEX_MMIO_CHAR_COLOR: cpu->char_color = val & 0xFFu; return;
        case NEVEX_MMIO_CHAR_DRAW: blit_char(cpu, (uint8_t)(val & 0xFFu)); return;
        case NEVEX_MMIO_SLEEP_MS: {
            uint32_t ms = val > 1000u ? 1000u : val;
#ifdef NEVEX_GUI
            uint32_t remaining = ms;
            while (remaining > 0) {
                uint32_t chunk = remaining > 16u ? 16u : remaining;
                nanosleep(&(struct timespec){ .tv_sec = 0, .tv_nsec = (long)chunk * 1000000L }, NULL);
                if (!gui_present()) { cpu->halted = 1; cpu->exit_code = 0; break; }
                remaining -= chunk;
            }
#else
            nanosleep(&(struct timespec){ .tv_sec = 0, .tv_nsec = (long)ms * 1000000L }, NULL);
#endif
            return;
        }
        default:
            take_trap(cpu, CAUSE_STORE_FAULT, cpu->cur_instr_pc);
            return;
    }
}

static int fb_in_range(uint32_t addr, uint32_t span) {
    return addr >= NEVEX_FB_BASE && addr + span <= NEVEX_FB_BASE + NEVEX_FB_SIZE;
}

static uint32_t mem_load32(CPU *cpu, uint32_t addr) {
    if (fb_in_range(addr, 4)) {
        if (cpu->mode != MODE_MACHINE) { take_trap(cpu, CAUSE_LOAD_FAULT, cpu->cur_instr_pc); return 0; }
        uint32_t off = addr - NEVEX_FB_BASE;
        return  (uint32_t)fb[off]       |
               ((uint32_t)fb[off + 1] << 8)  |
               ((uint32_t)fb[off + 2] << 16) |
               ((uint32_t)fb[off + 3] << 24);
    }
    if (addr >= NEVEX_MMIO_BASE) {
        if (cpu->mode != MODE_MACHINE) { take_trap(cpu, CAUSE_LOAD_FAULT, cpu->cur_instr_pc); return 0; }
        return mmio_read(cpu, addr);
    }
    if (addr + 4 > NEVEX_MMIO_BASE) { take_trap(cpu, CAUSE_LOAD_FAULT, cpu->cur_instr_pc); return 0; }
    return  (uint32_t)mem[addr]       |
           ((uint32_t)mem[addr + 1] << 8)  |
           ((uint32_t)mem[addr + 2] << 16) |
           ((uint32_t)mem[addr + 3] << 24);
}

static void mem_store32(CPU *cpu, uint32_t addr, uint32_t val) {
    if (fb_in_range(addr, 4)) {
        if (cpu->mode != MODE_MACHINE) { take_trap(cpu, CAUSE_STORE_FAULT, cpu->cur_instr_pc); return; }
        uint32_t off = addr - NEVEX_FB_BASE;
        fb[off]     = (uint8_t)(val & 0xFF);
        fb[off + 1] = (uint8_t)((val >> 8) & 0xFF);
        fb[off + 2] = (uint8_t)((val >> 16) & 0xFF);
        fb[off + 3] = (uint8_t)((val >> 24) & 0xFF);
        fb_dirty = 1;
        return;
    }
    if (addr >= NEVEX_MMIO_BASE) {
        if (cpu->mode != MODE_MACHINE) { take_trap(cpu, CAUSE_STORE_FAULT, cpu->cur_instr_pc); return; }
        mmio_write(cpu, addr, val);
        return;
    }
    if (addr + 4 > NEVEX_MMIO_BASE) { take_trap(cpu, CAUSE_STORE_FAULT, cpu->cur_instr_pc); return; }
    mem[addr]     = (uint8_t)(val & 0xFF);
    mem[addr + 1] = (uint8_t)((val >> 8) & 0xFF);
    mem[addr + 2] = (uint8_t)((val >> 16) & 0xFF);
    mem[addr + 3] = (uint8_t)((val >> 24) & 0xFF);
}

static uint8_t mem_load8(CPU *cpu, uint32_t addr) {
    if (fb_in_range(addr, 1)) {
        if (cpu->mode != MODE_MACHINE) { take_trap(cpu, CAUSE_LOAD_FAULT, cpu->cur_instr_pc); return 0; }
        return fb[addr - NEVEX_FB_BASE];
    }
    if (addr >= NEVEX_MMIO_BASE) { take_trap(cpu, CAUSE_LOAD_FAULT, cpu->cur_instr_pc); return 0; }
    return mem[addr];
}

static void mem_store8(CPU *cpu, uint32_t addr, uint8_t val) {
    if (fb_in_range(addr, 1)) {
        if (cpu->mode != MODE_MACHINE) { take_trap(cpu, CAUSE_STORE_FAULT, cpu->cur_instr_pc); return; }
        fb[addr - NEVEX_FB_BASE] = val;
        fb_dirty = 1;
        return;
    }
    if (addr >= NEVEX_MMIO_BASE) { take_trap(cpu, CAUSE_STORE_FAULT, cpu->cur_instr_pc); return; }
    mem[addr] = val;
}

#define sign_extend nevex_sign_extend
#define enc_r nevex_enc_r
#define enc_i nevex_enc_i
#define enc_s nevex_enc_s
#define enc_j nevex_enc_j
#define split_hi_lo nevex_split_hi_lo

#define ADD(rd,rs1,rs2)   enc_r(OP_R, rd, rs1, rs2, F_ADD)
#define SUB(rd,rs1,rs2)   enc_r(OP_R, rd, rs1, rs2, F_SUB)
#define MUL(rd,rs1,rs2)   enc_r(OP_R, rd, rs1, rs2, F_MUL)
#define AND(rd,rs1,rs2)   enc_r(OP_R, rd, rs1, rs2, F_AND)
#define OR(rd,rs1,rs2)    enc_r(OP_R, rd, rs1, rs2, F_OR)
#define XOR(rd,rs1,rs2)   enc_r(OP_R, rd, rs1, rs2, F_XOR)
#define DIV(rd,rs1,rs2)   enc_r(OP_R, rd, rs1, rs2, F_DIV)
#define REM(rd,rs1,rs2)   enc_r(OP_R, rd, rs1, rs2, F_REM)
#define DIVU(rd,rs1,rs2)  enc_r(OP_R, rd, rs1, rs2, F_DIVU)
#define REMU(rd,rs1,rs2)  enc_r(OP_R, rd, rs1, rs2, F_REMU)
#define ADDI(rd,rs1,imm)  enc_i(OP_ADDI, rd, rs1, imm)
#define LW(rd,rs1,imm)    enc_i(OP_LW, rd, rs1, imm)
#define LB(rd,rs1,imm)    enc_i(OP_LB, rd, rs1, imm)
#define SW(rs1,rs2,imm)   enc_s(OP_SW, rs1, rs2, imm)
#define BEQ(rs1,rs2,imm)  enc_s(OP_BEQ, rs1, rs2, imm)
#define BNE(rs1,rs2,imm)  enc_s(OP_BNE, rs1, rs2, imm)
#define JAL(rd,imm)       enc_j(OP_JAL, rd, imm)
#define JALR(rd,rs1,imm)  enc_i(OP_JALR, rd, rs1, imm)
#define ECALL()           enc_r(OP_ECALL, 0, 0, 0, 0)
#define MRET()            enc_r(OP_MRET, 0, 0, 0, 0)
#define HALT()            enc_r(OP_HALT, 0, 0, 0, 0)
#define NOP()             ADDI(X_ZERO, X_ZERO, 0)
#define LI(rd,imm)        ADDI(rd, X_ZERO, imm)
#define MOV(rd,rs)        ADDI(rd, rs, 0)
#define JMP(imm)          JAL(X_ZERO, imm)
#define CALL(imm)         JAL(X_RA, imm)
#define RET()             JALR(X_ZERO, X_RA, 0)

static void build_demo_program(uint32_t *prog, int *out_count, uint32_t msg_addr) {
    int i = 0;
    int32_t hi, lo;

    split_hi_lo((int32_t)NEVEX_MMIO_BASE, &hi, &lo);
    prog[i++] = enc_j(OP_LUI, X_S0, hi);
    prog[i++] = ADDI(X_S0, X_S0, lo);
    prog[i++] = LI(X_T1, (int32_t)msg_addr);

    int loop_idx = i;
    prog[i++] = LB(X_T2, X_T1, 0);
    int branch_idx = i;
    prog[i++] = 0;
    prog[i++] = SW(X_S0, X_T2, 0);
    prog[i++] = ADDI(X_T1, X_T1, 1);
    int jmp_idx = i;
    prog[i++] = JMP((int32_t)((loop_idx - jmp_idx) * 4));

    int end_idx = i;
    prog[branch_idx] = BEQ(X_T2, X_ZERO, (int32_t)((end_idx - branch_idx) * 4));

    prog[i++] = LI(X_A1, 0);
    prog[i++] = SW(X_S0, X_A1, (int32_t)(NEVEX_MMIO_EXIT - NEVEX_MMIO_BASE));

    *out_count = i;
}

static void step(CPU *cpu) {
    cpu->trap_pending = 0;
    cpu->mtime++;

    if (cpu->mie && cpu->mtime >= cpu->mtimecmp) {
        take_trap(cpu, CAUSE_TIMER_INTERRUPT, cpu->pc);
        return;
    }

    cpu->cur_instr_pc = cpu->pc;
    if (cpu->pc % 4 != 0) { take_trap(cpu, CAUSE_UNALIGNED_FETCH, cpu->pc); return; }

    uint32_t instr = mem_load32(cpu, cpu->pc);
    if (cpu->trap_pending) return;

    uint32_t instr_pc = cpu->cur_instr_pc;
    cpu->pc = instr_pc + 4;

    uint32_t opcode = (instr >> 26) & 0x3F;
    uint32_t f1     = (instr >> 22) & 0xF;
    uint32_t f2     = (instr >> 18) & 0xF;
    uint32_t f3     = (instr >> 14) & 0xF;
    uint32_t low14  = instr & 0x3FFF;

    switch (opcode) {
        case OP_R: {
            uint32_t rd = f1, rs1 = f2, rs2 = f3;
            uint32_t funct = (low14 >> 8) & 0x3F;
            uint32_t lhs = reg_read(cpu, rs1), rhs = reg_read(cpu, rs2);
            uint32_t result;
            switch (funct) {
                case F_ADD:  result = lhs + rhs; break;
                case F_SUB:  result = lhs - rhs; break;
                case F_MUL:  result = lhs * rhs; break;
                case F_AND:  result = lhs & rhs; break;
                case F_OR:   result = lhs | rhs; break;
                case F_XOR:  result = lhs ^ rhs; break;
                case F_SLL:  result = lhs << (rhs & 31); break;
                case F_SRL:  result = lhs >> (rhs & 31); break;
                case F_SRA:  result = (uint32_t)((int32_t)lhs >> (rhs & 31)); break;
                case F_SLT:  result = ((int32_t)lhs < (int32_t)rhs) ? 1u : 0u; break;
                case F_SLTU: result = (lhs < rhs) ? 1u : 0u; break;
                case F_DIV: {
                    int32_t sl = (int32_t)lhs, sr = (int32_t)rhs;
                    if (sr == 0) result = 0xFFFFFFFFu;
                    else if (sl == INT32_MIN && sr == -1) result = (uint32_t)INT32_MIN;
                    else result = (uint32_t)(sl / sr);
                    break;
                }
                case F_REM: {
                    int32_t sl = (int32_t)lhs, sr = (int32_t)rhs;
                    if (sr == 0) result = lhs;
                    else if (sl == INT32_MIN && sr == -1) result = 0;
                    else result = (uint32_t)(sl % sr);
                    break;
                }
                case F_DIVU: result = (rhs == 0) ? 0xFFFFFFFFu : (lhs / rhs); break;
                case F_REMU: result = (rhs == 0) ? lhs : (lhs % rhs); break;
                default: take_trap(cpu, CAUSE_ILLEGAL_INSTR, instr_pc); return;
            }
            reg_write(cpu, rd, result);
            break;
        }

        case OP_ADDI: case OP_ANDI: case OP_ORI: case OP_XORI:
        case OP_SLLI: case OP_SRLI: case OP_SRAI: {
            uint32_t rd = f1, rs1 = f2;
            int32_t imm = sign_extend(low14, 14);
            uint32_t lhs = reg_read(cpu, rs1);
            uint32_t result;
            switch (opcode) {
                case OP_ADDI: result = lhs + (uint32_t)imm; break;
                case OP_ANDI: result = lhs & (uint32_t)imm; break;
                case OP_ORI:  result = lhs | (uint32_t)imm; break;
                case OP_XORI: result = lhs ^ (uint32_t)imm; break;
                case OP_SLLI: result = lhs << (imm & 31); break;
                case OP_SRLI: result = lhs >> (imm & 31); break;
                case OP_SRAI: result = (uint32_t)((int32_t)lhs >> (imm & 31)); break;
                default: result = 0; break;
            }
            reg_write(cpu, rd, result);
            break;
        }

        case OP_LW: {
            uint32_t rd = f1, rs1 = f2;
            int32_t imm = sign_extend(low14, 14);
            uint32_t addr = reg_read(cpu, rs1) + (uint32_t)imm;
            uint32_t val = mem_load32(cpu, addr);
            if (cpu->trap_pending) return;
            reg_write(cpu, rd, val);
            break;
        }
        case OP_LB: {
            uint32_t rd = f1, rs1 = f2;
            int32_t imm = sign_extend(low14, 14);
            uint32_t addr = reg_read(cpu, rs1) + (uint32_t)imm;
            uint8_t val = mem_load8(cpu, addr);
            if (cpu->trap_pending) return;
            reg_write(cpu, rd, (uint32_t)sign_extend(val, 8));
            break;
        }
        case OP_LBU: {
            uint32_t rd = f1, rs1 = f2;
            int32_t imm = sign_extend(low14, 14);
            uint32_t addr = reg_read(cpu, rs1) + (uint32_t)imm;
            uint8_t val = mem_load8(cpu, addr);
            if (cpu->trap_pending) return;
            reg_write(cpu, rd, (uint32_t)val);
            break;
        }

        case OP_SW: {
            uint32_t rs1 = f2, rs2 = f3;
            int32_t imm = sign_extend((f1 << 14) | low14, 18);
            uint32_t addr = reg_read(cpu, rs1) + (uint32_t)imm;
            mem_store32(cpu, addr, reg_read(cpu, rs2));
            if (cpu->trap_pending) return;
            break;
        }
        case OP_SB: {
            uint32_t rs1 = f2, rs2 = f3;
            int32_t imm = sign_extend((f1 << 14) | low14, 18);
            uint32_t addr = reg_read(cpu, rs1) + (uint32_t)imm;
            mem_store8(cpu, addr, (uint8_t)(reg_read(cpu, rs2) & 0xFF));
            if (cpu->trap_pending) return;
            break;
        }

        case OP_BEQ: case OP_BNE: case OP_BLT:
        case OP_BGE: case OP_BLTU: case OP_BGEU: {
            uint32_t rs1 = f2, rs2 = f3;
            int32_t imm = sign_extend((f1 << 14) | low14, 18);
            uint32_t lhs = reg_read(cpu, rs1), rhs = reg_read(cpu, rs2);
            int take;
            switch (opcode) {
                case OP_BEQ:  take = (lhs == rhs); break;
                case OP_BNE:  take = (lhs != rhs); break;
                case OP_BLT:  take = ((int32_t)lhs < (int32_t)rhs); break;
                case OP_BGE:  take = ((int32_t)lhs >= (int32_t)rhs); break;
                case OP_BLTU: take = (lhs < rhs); break;
                case OP_BGEU: take = (lhs >= rhs); break;
                default: take = 0; break;
            }
            if (take) cpu->pc = instr_pc + (uint32_t)imm;
            break;
        }

        case OP_JAL: {
            uint32_t rd = f1;
            int32_t imm = sign_extend(instr & 0x3FFFFF, 22);
            reg_write(cpu, rd, instr_pc + 4);
            cpu->pc = instr_pc + (uint32_t)imm;
            break;
        }
        case OP_JALR: {
            uint32_t rd = f1, rs1 = f2;
            int32_t imm = sign_extend(low14, 14);
            uint32_t target = (reg_read(cpu, rs1) + (uint32_t)imm) & ~3u;
            reg_write(cpu, rd, instr_pc + 4);
            cpu->pc = target;
            break;
        }
        case OP_LUI: {
            uint32_t rd = f1;
            int32_t imm = sign_extend(instr & 0x3FFFFF, 22);
            reg_write(cpu, rd, (uint32_t)imm << 14);
            break;
        }

        case OP_ECALL: {
            uint32_t cause = (cpu->mode == MODE_USER) ? CAUSE_ECALL_FROM_U : CAUSE_ECALL_FROM_M;
            take_trap(cpu, cause, instr_pc);
            return;
        }

        case OP_MRET: {
            if (cpu->mode != MODE_MACHINE) { take_trap(cpu, CAUSE_ILLEGAL_INSTR, instr_pc); return; }
            cpu->mode = cpu->mpp;
            cpu->pc = cpu->mepc;
            break;
        }

        case OP_HALT:
            cpu->halted = 1;
            cpu->exit_code = 0;
            break;

        default:
            take_trap(cpu, CAUSE_ILLEGAL_INSTR, instr_pc);
            return;
    }
}

static void rgb332_to_rgb888(uint8_t px, uint8_t *r, uint8_t *g, uint8_t *b) {
    uint8_t r3 = (px >> 5) & 0x7, g3 = (px >> 2) & 0x7, b2 = px & 0x3;
    *r = (uint8_t)((r3 << 5) | (r3 << 2) | (r3 >> 1));
    *g = (uint8_t)((g3 << 5) | (g3 << 2) | (g3 >> 1));
    *b = (uint8_t)((b2 << 6) | (b2 << 4) | (b2 << 2) | b2);
}

static void dump_framebuffer_ppm(const char *path) {
    FILE *f = fopen(path, "wb");
    if (!f) { fprintf(stderr, "[nevex] '%s' yazilamadi\n", path); return; }
    fprintf(f, "P6\n%d %d\n255\n", NEVEX_FB_WIDTH, NEVEX_FB_HEIGHT);
    for (int i = 0; i < NEVEX_FB_SIZE; i++) {
        uint8_t r, g, b;
        rgb332_to_rgb888(fb[i], &r, &g, &b);
        uint8_t rgb[3] = { r, g, b };
        fwrite(rgb, 1, 3, f);
    }
    fclose(f);
    fprintf(stderr, "[nevex] framebuffer '%s' dosyasina yazildi (%dx%d)\n", path, NEVEX_FB_WIDTH, NEVEX_FB_HEIGHT);
}

#ifdef NEVEX_GUI
#include <SDL2/SDL.h>

static SDL_Window *gui_window = NULL;
static SDL_Renderer *gui_renderer = NULL;
static SDL_Texture *gui_texture = NULL;

static void gui_init(void) {
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "[nevex] SDL_Init hatasi: %s\n", SDL_GetError());
        return;
    }
    gui_window = SDL_CreateWindow("nevex framebuffer", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                   NEVEX_FB_WIDTH * GUI_SCALE, NEVEX_FB_HEIGHT * GUI_SCALE, SDL_WINDOW_SHOWN);
    gui_renderer = SDL_CreateRenderer(gui_window, -1, SDL_RENDERER_ACCELERATED);
    gui_texture = SDL_CreateTexture(gui_renderer, SDL_PIXELFORMAT_RGB888, SDL_TEXTUREACCESS_STREAMING,
                                     NEVEX_FB_WIDTH, NEVEX_FB_HEIGHT);
}

static int gui_present(void) {
    if (!gui_window) return 1;
    SDL_Event ev;
    while (SDL_PollEvent(&ev)) {
        if (ev.type == SDL_QUIT) { gui_quit_requested = 1; return 0; }
        if (ev.type == SDL_KEYDOWN) {
            switch (ev.key.keysym.sym) {
                case SDLK_ESCAPE: gui_quit_requested = 1; return 0;
                case SDLK_UP:    case SDLK_w: gui_last_key = 1; break;
                case SDLK_DOWN:  case SDLK_s: gui_last_key = 2; break;
                case SDLK_LEFT:  case SDLK_a: gui_last_key = 3; break;
                case SDLK_RIGHT: case SDLK_d: gui_last_key = 4; break;
                default: break;
            }
        }
        if (ev.type == SDL_MOUSEMOTION) {
            gui_mouse_x = ev.motion.x / GUI_SCALE;
            gui_mouse_y = ev.motion.y / GUI_SCALE;
        }
        if (ev.type == SDL_MOUSEBUTTONDOWN && ev.button.button == SDL_BUTTON_LEFT) {
            gui_mouse_x = ev.button.x / GUI_SCALE;
            gui_mouse_y = ev.button.y / GUI_SCALE;
            gui_mouse_btn = 1;
        }
        if (ev.type == SDL_MOUSEBUTTONUP && ev.button.button == SDL_BUTTON_LEFT) {
            gui_mouse_btn = 0;
        }
        if (gui_mouse_x < 0) gui_mouse_x = 0;
        if (gui_mouse_x >= NEVEX_FB_WIDTH) gui_mouse_x = NEVEX_FB_WIDTH - 1;
        if (gui_mouse_y < 0) gui_mouse_y = 0;
        if (gui_mouse_y >= NEVEX_FB_HEIGHT) gui_mouse_y = NEVEX_FB_HEIGHT - 1;
    }
    uint32_t pixels[NEVEX_FB_WIDTH * NEVEX_FB_HEIGHT];
    for (int i = 0; i < NEVEX_FB_SIZE; i++) {
        uint8_t r, g, b;
        rgb332_to_rgb888(fb[i], &r, &g, &b);
        pixels[i] = ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
    }
    SDL_UpdateTexture(gui_texture, NULL, pixels, NEVEX_FB_WIDTH * (int)sizeof(uint32_t));
    SDL_RenderClear(gui_renderer);
    SDL_RenderCopy(gui_renderer, gui_texture, NULL, NULL);
    SDL_RenderPresent(gui_renderer);
    return 1;
}

static void gui_shutdown(void) {
    if (!gui_window) return;
    SDL_DestroyTexture(gui_texture);
    SDL_DestroyRenderer(gui_renderer);
    SDL_DestroyWindow(gui_window);
    SDL_Quit();
}
#endif

static size_t load_binary_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "[nevex] dosya acilamadi: %s\n", path);
        exit(1);
    }
    size_t n = fread(mem, 1, NEVEX_MMIO_BASE, f);
    fclose(f);
    return n;
}

int main(int argc, char **argv) {
    srand((unsigned)time(NULL));

    CPU cpu;
    memset(&cpu, 0, sizeof(cpu));
    cpu.x[X_SP] = NEVEX_MMIO_BASE;
    cpu.pc = 0;
    cpu.mode = MODE_MACHINE;

    if (argc > 1) {
        size_t n = load_binary_file(argv[1]);
        printf("[nevex] '%s' yuklendi (%zu byte)\n", argv[1], n);
    } else {
        uint32_t prog[64];
        int count = 0;
        const char *msg = "nevex vm calisiyor\n";

        build_demo_program(prog, &count, 0);
        uint32_t msg_addr = (uint32_t)count * 4;
        build_demo_program(prog, &count, msg_addr);

        for (int i = 0; i < count; i++) mem_store32(&cpu, (uint32_t)(i * 4), prog[i]);
        for (int k = 0; msg[k]; k++) mem_store8(&cpu, msg_addr + (uint32_t)k, (uint8_t)msg[k]);
        mem_store8(&cpu, msg_addr + (uint32_t)strlen(msg), 0);

        printf("[nevex] gomulu demo program yuklendi\n");
    }

#ifdef NEVEX_GUI
    gui_init();
#endif

    long steps = 0;
    const long MAX_STEPS = 100000000L;
    while (!cpu.halted) {
        step(&cpu);
        if (++steps > MAX_STEPS) {
            panic(&cpu, "instruction limit exceeded (olasi sonsuz dongu)");
        }
#ifdef NEVEX_GUI
        if (steps % 20000 == 0) {
            if (!gui_present()) break;
        }
#endif
    }

    printf("[nevex] program sonlandi, exit code = %d\n", cpu.exit_code);

    if (fb_dirty) dump_framebuffer_ppm("nevex_fb.ppm");

#ifdef NEVEX_GUI
    if (!gui_quit_requested && gui_present()) {
        fprintf(stderr, "[nevex] pencereyi kapatmak icin ESC'e bas ya da pencereyi kapat\n");
        while (gui_present()) SDL_Delay(16);
    }
    gui_shutdown();
#endif

    return cpu.exit_code;
}
