#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>
#include <stdarg.h>

#include "isa.h"

#define MAX_LABELS 4096
#define MAX_STMTS  16384
#define MAX_LINE   512
#define MAX_OPERAND 80
#define MAX_ASCIZ  256

typedef struct {
    char name[64];
    uint32_t addr;
} Label;

typedef enum { ST_INSTR, ST_INSTR2, ST_WORD, ST_ASCIZ, ST_ALIGN, ST_SPACE } StmtKind;

typedef struct {
    StmtKind kind;
    uint32_t addr;
    int lineno;
    char mnemonic[16];
    char operands[4][MAX_OPERAND];
    int noperands;
    long value;
    uint8_t bytes[MAX_ASCIZ];
    int nbytes;
} Stmt;

static Label labels[MAX_LABELS];
static int nlabels = 0;

static Stmt stmts[MAX_STMTS];
static int nstmts = 0;

static uint8_t out[NEVEX_MEM_SIZE];
static uint32_t asm_addr = 0;

static int lineno = 0;
static const char *srcname = "<input>";

static void die(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "%s:%d: hata: ", srcname, lineno);
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
    exit(1);
}

static void safe_copy(char *dst, size_t dstsize, const char *src) {
    size_t n = strlen(src);
    if (n > dstsize - 1) n = dstsize - 1;
    memcpy(dst, src, n);
    dst[n] = '\0';
}

static void trim(char *s) {
    char *start = s;
    while (isspace((unsigned char)*start)) start++;
    size_t len = strlen(start);
    while (len > 0 && isspace((unsigned char)start[len - 1])) { start[len - 1] = '\0'; len--; }
    if (start != s) memmove(s, start, len + 1);
}

static void strip_comment(char *line) {
    int in_str = 0;
    for (char *p = line; *p; p++) {
        if (*p == '"') in_str = !in_str;
        else if (!in_str && (*p == ';' || *p == '#')) { *p = '\0'; break; }
    }
}

static int valid_label_name(const char *s) {
    if (!*s) return 0;
    if (!(isalpha((unsigned char)s[0]) || s[0] == '_')) return 0;
    for (const char *p = s + 1; *p; p++) {
        if (!(isalnum((unsigned char)*p) || *p == '_')) return 0;
    }
    return 1;
}

static void add_label(const char *name, uint32_t addr) {
    for (int i = 0; i < nlabels; i++) {
        if (!strcmp(labels[i].name, name)) die("etiket '%s' zaten tanimli", name);
    }
    if (nlabels >= MAX_LABELS) die("cok fazla etiket");
    safe_copy(labels[nlabels].name, sizeof(labels[nlabels].name), name);
    labels[nlabels].addr = addr;
    nlabels++;
}

static int find_label(const char *tok) {
    char buf[64];
    strncpy(buf, tok, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';
    trim(buf);
    for (int i = 0; i < nlabels; i++) {
        if (!strcmp(labels[i].name, buf)) return i;
    }
    return -1;
}

static const char *abi_names[16] = {
    "zero", "ra", "sp", "a0", "a1", "a2", "a3", "t0",
    "t1", "t2", "t3", "t4", "t5", "t6", "s0", "s1"
};

static int reg_index(const char *tok) {
    char buf[32];
    strncpy(buf, tok, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';
    trim(buf);
    for (char *p = buf; *p; p++) *p = (char)tolower((unsigned char)*p);
    if ((buf[0] == 'x') && isdigit((unsigned char)buf[1])) {
        int n = atoi(buf + 1);
        if (n >= 0 && n < 16) return n;
    }
    for (int i = 0; i < 16; i++) {
        if (!strcmp(buf, abi_names[i])) return i;
    }
    return -1;
}

static int reg_index_or_die(const char *tok) {
    int r = reg_index(tok);
    if (r < 0) die("gecersiz register '%s'", tok);
    return r;
}

static int parse_imm(const char *tok, long *out_val) {
    char buf[128];
    strncpy(buf, tok, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';
    trim(buf);
    if (buf[0] == '\0') return 0;

    if (buf[0] == '\'') {
        size_t len = strlen(buf);
        if (len < 3 || buf[len - 1] != '\'') return 0;
        char c;
        if (buf[1] == '\\') {
            if (len != 4) return 0;
            switch (buf[2]) {
                case 'n': c = '\n'; break;
                case 't': c = '\t'; break;
                case 'r': c = '\r'; break;
                case '0': c = '\0'; break;
                case '\\': c = '\\'; break;
                case '\'': c = '\''; break;
                default: return 0;
            }
        } else {
            if (len != 3) return 0;
            c = buf[1];
        }
        *out_val = (long)(unsigned char)c;
        return 1;
    }

    const char *p = buf;
    int neg = 0;
    if (*p == '+' || *p == '-') { neg = (*p == '-'); p++; }
    char *end;
    long v;
    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
        v = strtol(p + 2, &end, 16);
    } else {
        v = strtol(p, &end, 10);
    }
    if (end == p || *end != '\0') return 0;
    *out_val = neg ? -v : v;
    return 1;
}

static long resolve_operand_as_imm(const char *tok, uint32_t cur_addr, int pcrel) {
    int idx = find_label(tok);
    if (idx >= 0) {
        long target = (long)labels[idx].addr;
        return pcrel ? (target - (long)cur_addr) : target;
    }
    long v;
    if (!parse_imm(tok, &v)) die("immediate ya da etiket bekleniyordu: '%s'", tok);
    return v;
}

static void check_range(long v, int bits, const char *ctx) {
    long lo = -(1L << (bits - 1));
    long hi = (1L << (bits - 1)) - 1;
    if (v < lo || v > hi) {
        die("'%s' icin immediate %ld aralik disinda (%d-bit signed, %ld..%ld)", ctx, v, bits, lo, hi);
    }
}

static int parse_mem(const char *tok, long *imm, int *reg) {
    char buf[128];
    strncpy(buf, tok, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';
    trim(buf);
    char *paren = strchr(buf, '(');
    if (!paren) return 0;
    char *close = strchr(paren, ')');
    if (!close) return 0;
    *paren = '\0';
    *close = '\0';
    char *imm_str = buf;
    char *reg_str = paren + 1;
    trim(imm_str);
    if (imm_str[0] == '\0') {
        *imm = 0;
    } else if (!parse_imm(imm_str, imm)) {
        int idx = find_label(imm_str);
        if (idx < 0) return 0;
        *imm = (long)labels[idx].addr;
    }
    int r = reg_index(reg_str);
    if (r < 0) return 0;
    *reg = r;
    return 1;
}

static int unescape_into(const char *src, int srclen, uint8_t *dst, int dstmax) {
    int n = 0;
    for (int i = 0; i < srclen; i++) {
        char c = src[i];
        if (c == '\\' && i + 1 < srclen) {
            i++;
            char e = src[i];
            switch (e) {
                case 'n': c = '\n'; break;
                case 't': c = '\t'; break;
                case 'r': c = '\r'; break;
                case '0': c = '\0'; break;
                case '\\': c = '\\'; break;
                case '"': c = '"'; break;
                default: c = e; break;
            }
        }
        if (n >= dstmax) die("string literal cok uzun");
        dst[n++] = (uint8_t)c;
    }
    return n;
}

static void parse_statement(char *line, Stmt *st) {
    char *p = line;
    char mnemonic[16];
    size_t mlen = 0;
    while (p[mlen] && !isspace((unsigned char)p[mlen])) mlen++;
    if (mlen == 0 || mlen >= sizeof(mnemonic)) die("gecersiz komut/direktif");
    memcpy(mnemonic, p, mlen);
    mnemonic[mlen] = '\0';
    p += mlen;
    while (isspace((unsigned char)*p)) p++;
    for (char *q = mnemonic; *q; q++) *q = (char)tolower((unsigned char)*q);

    if (!strcmp(mnemonic, ".word")) {
        st->kind = ST_WORD;
        trim(p);
        if (p[0] == '\0') die(".word bir operand bekliyor");
        strncpy(st->operands[0], p, MAX_OPERAND - 1);
        st->noperands = 1;
        return;
    }

    if (!strcmp(mnemonic, ".asciz")) {
        st->kind = ST_ASCIZ;
        char *q1 = strchr(p, '"');
        if (!q1) die(".asciz bir tirnakli string bekliyor");
        char *q2 = strrchr(p, '"');
        if (q2 <= q1) die(".asciz string'i hatali");
        int n = unescape_into(q1 + 1, (int)(q2 - (q1 + 1)), st->bytes, MAX_ASCIZ - 1);
        st->bytes[n++] = 0;
        st->nbytes = n;
        return;
    }

    if (!strcmp(mnemonic, ".align")) {
        st->kind = ST_ALIGN;
        trim(p);
        long v;
        if (!parse_imm(p, &v) || v <= 0) die(".align pozitif bir tamsayi bekliyor");
        st->value = v;
        return;
    }

    if (!strcmp(mnemonic, ".space")) {
        st->kind = ST_SPACE;
        trim(p);
        long v;
        if (!parse_imm(p, &v) || v < 0) die(".space negatif olmayan bir tamsayi bekliyor");
        st->value = v;
        return;
    }

    st->kind = !strcmp(mnemonic, "lli") ? ST_INSTR2 : ST_INSTR;
    safe_copy(st->mnemonic, sizeof(st->mnemonic), mnemonic);
    trim(p);
    st->noperands = 0;
    if (p[0] != '\0') {
        char *tok = strtok(p, ",");
        while (tok) {
            if (st->noperands >= 4) die("cok fazla operand");
            strncpy(st->operands[st->noperands], tok, MAX_OPERAND - 1);
            trim(st->operands[st->noperands]);
            st->noperands++;
            tok = strtok(NULL, ",");
        }
    }
}

static void record_stmt(char *stmt_line) {
    if (nstmts >= MAX_STMTS) die("cok fazla satir");
    Stmt *st = &stmts[nstmts];
    memset(st, 0, sizeof(*st));
    st->lineno = lineno;
    st->addr = asm_addr;
    parse_statement(stmt_line, st);

    switch (st->kind) {
        case ST_ALIGN: {
            long n = st->value;
            uint32_t pad = (uint32_t)(((n - (long)(asm_addr % (uint32_t)n)) % n));
            st->value = pad;
            asm_addr += pad;
            break;
        }
        case ST_ASCIZ:
            asm_addr += (uint32_t)st->nbytes;
            break;
        case ST_SPACE:
            asm_addr += (uint32_t)st->value;
            break;
        case ST_INSTR:
        case ST_WORD:
            asm_addr += 4;
            break;
        case ST_INSTR2:
            asm_addr += 8;
            break;
    }
    if (asm_addr > NEVEX_MEM_SIZE) die("program 64KB bellek sinirini asiyor");
    nstmts++;
}

static void pass1(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) { fprintf(stderr, "[nevexas] dosya acilamadi: %s\n", path); exit(1); }

    char rawline[MAX_LINE];
    while (fgets(rawline, sizeof(rawline), f)) {
        lineno++;
        char line[MAX_LINE];
        strncpy(line, rawline, sizeof(line) - 1);
        line[sizeof(line) - 1] = '\0';
        strip_comment(line);
        trim(line);
        if (line[0] == '\0') continue;

        char *p = line;
        while (*p && !isspace((unsigned char)*p) && *p != ':') p++;
        if (*p == ':') {
            *p = '\0';
            trim(line);
            if (!valid_label_name(line)) die("gecersiz etiket adi '%s'", line);
            add_label(line, asm_addr);
            char *rest = p + 1;
            trim(rest);
            if (rest[0] == '\0') continue;
            record_stmt(rest);
            continue;
        }
        record_stmt(line);
    }
    fclose(f);
}

static uint32_t encode_instruction(Stmt *st) {
    const char *mn = st->mnemonic;
    int n = st->noperands;
    char (*op)[MAX_OPERAND] = st->operands;

    if (n < 0) die("internal");

#define REQ(cnt) do { if (n != (cnt)) die("'%s' %d operand bekliyor, %d verildi", mn, (cnt), n); } while (0)
#define REG(i) reg_index_or_die(op[i])
#define IMMV(i, pcrel) resolve_operand_as_imm(op[i], st->addr, (pcrel))

    if (!strcmp(mn, "add"))  { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_ADD); }
    if (!strcmp(mn, "sub"))  { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_SUB); }
    if (!strcmp(mn, "mul"))  { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_MUL); }
    if (!strcmp(mn, "and"))  { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_AND); }
    if (!strcmp(mn, "or"))   { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_OR); }
    if (!strcmp(mn, "xor"))  { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_XOR); }
    if (!strcmp(mn, "sll"))  { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_SLL); }
    if (!strcmp(mn, "srl"))  { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_SRL); }
    if (!strcmp(mn, "sra"))  { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_SRA); }
    if (!strcmp(mn, "slt"))  { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_SLT); }
    if (!strcmp(mn, "sltu")) { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_SLTU); }
    if (!strcmp(mn, "div"))  { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_DIV); }
    if (!strcmp(mn, "rem"))  { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_REM); }
    if (!strcmp(mn, "divu")) { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_DIVU); }
    if (!strcmp(mn, "remu")) { REQ(3); return nevex_enc_r(OP_R, REG(0), REG(1), REG(2), F_REMU); }

    if (!strcmp(mn, "addi")) { REQ(3); long v = IMMV(2, 0); check_range(v, 14, mn); return nevex_enc_i(OP_ADDI, REG(0), REG(1), (int32_t)v); }
    if (!strcmp(mn, "andi")) { REQ(3); long v = IMMV(2, 0); check_range(v, 14, mn); return nevex_enc_i(OP_ANDI, REG(0), REG(1), (int32_t)v); }
    if (!strcmp(mn, "ori"))  { REQ(3); long v = IMMV(2, 0); check_range(v, 14, mn); return nevex_enc_i(OP_ORI, REG(0), REG(1), (int32_t)v); }
    if (!strcmp(mn, "xori")) { REQ(3); long v = IMMV(2, 0); check_range(v, 14, mn); return nevex_enc_i(OP_XORI, REG(0), REG(1), (int32_t)v); }
    if (!strcmp(mn, "slli")) { REQ(3); long v = IMMV(2, 0); check_range(v, 14, mn); return nevex_enc_i(OP_SLLI, REG(0), REG(1), (int32_t)v); }
    if (!strcmp(mn, "srli")) { REQ(3); long v = IMMV(2, 0); check_range(v, 14, mn); return nevex_enc_i(OP_SRLI, REG(0), REG(1), (int32_t)v); }
    if (!strcmp(mn, "srai")) { REQ(3); long v = IMMV(2, 0); check_range(v, 14, mn); return nevex_enc_i(OP_SRAI, REG(0), REG(1), (int32_t)v); }

    if (!strcmp(mn, "lw") || !strcmp(mn, "lb") || !strcmp(mn, "lbu")) {
        REQ(2);
        int rd = REG(0);
        long imm; int rs1;
        if (!parse_mem(op[1], &imm, &rs1)) die("bellek operandi hatali '%s' (beklenen: imm(reg))", op[1]);
        check_range(imm, 14, mn);
        int opc = !strcmp(mn, "lw") ? OP_LW : (!strcmp(mn, "lb") ? OP_LB : OP_LBU);
        return nevex_enc_i(opc, rd, rs1, (int32_t)imm);
    }
    if (!strcmp(mn, "sw") || !strcmp(mn, "sb")) {
        REQ(2);
        int rs2 = REG(0);
        long imm; int rs1;
        if (!parse_mem(op[1], &imm, &rs1)) die("bellek operandi hatali '%s' (beklenen: imm(reg))", op[1]);
        check_range(imm, 18, mn);
        int opc = !strcmp(mn, "sw") ? OP_SW : OP_SB;
        return nevex_enc_s(opc, rs1, rs2, (int32_t)imm);
    }

    if (!strcmp(mn, "beq") || !strcmp(mn, "bne") || !strcmp(mn, "blt") ||
        !strcmp(mn, "bge") || !strcmp(mn, "bltu") || !strcmp(mn, "bgeu")) {
        REQ(3);
        int rs1 = REG(0), rs2 = REG(1);
        long imm = IMMV(2, 1);
        check_range(imm, 18, mn);
        int opc = !strcmp(mn, "beq") ? OP_BEQ :
                  !strcmp(mn, "bne") ? OP_BNE :
                  !strcmp(mn, "blt") ? OP_BLT :
                  !strcmp(mn, "bge") ? OP_BGE :
                  !strcmp(mn, "bltu") ? OP_BLTU : OP_BGEU;
        return nevex_enc_s(opc, rs1, rs2, (int32_t)imm);
    }

    if (!strcmp(mn, "jal"))  { REQ(2); int rd = REG(0); long v = IMMV(1, 1); check_range(v, 22, mn); return nevex_enc_j(OP_JAL, rd, (int32_t)v); }
    if (!strcmp(mn, "jalr")) { REQ(3); int rd = REG(0), rs1 = REG(1); long v = IMMV(2, 0); check_range(v, 14, mn); return nevex_enc_i(OP_JALR, rd, rs1, (int32_t)v); }
    if (!strcmp(mn, "lui"))  { REQ(2); int rd = REG(0); long v = IMMV(1, 0); check_range(v, 22, mn); return nevex_enc_j(OP_LUI, rd, (int32_t)v); }

    if (!strcmp(mn, "ecall")) { REQ(0); return nevex_enc_r(OP_ECALL, 0, 0, 0, 0); }
    if (!strcmp(mn, "mret"))  { REQ(0); return nevex_enc_r(OP_MRET, 0, 0, 0, 0); }
    if (!strcmp(mn, "halt"))  { REQ(0); return nevex_enc_r(OP_HALT, 0, 0, 0, 0); }

    if (!strcmp(mn, "nop")) { REQ(0); return nevex_enc_i(OP_ADDI, X_ZERO, X_ZERO, 0); }
    if (!strcmp(mn, "li"))  { REQ(2); int rd = REG(0); long v = IMMV(1, 0); check_range(v, 14, mn); return nevex_enc_i(OP_ADDI, rd, X_ZERO, (int32_t)v); }
    if (!strcmp(mn, "mov")) { REQ(2); int rd = REG(0), rs = REG(1); return nevex_enc_i(OP_ADDI, rd, rs, 0); }
    if (!strcmp(mn, "jmp")) { REQ(1); long v = IMMV(0, 1); check_range(v, 22, mn); return nevex_enc_j(OP_JAL, X_ZERO, (int32_t)v); }
    if (!strcmp(mn, "call")) { REQ(1); long v = IMMV(0, 1); check_range(v, 22, mn); return nevex_enc_j(OP_JAL, X_RA, (int32_t)v); }
    if (!strcmp(mn, "ret")) { REQ(0); return nevex_enc_i(OP_JALR, X_ZERO, X_RA, 0); }

    die("bilinmeyen mnemonic '%s'", mn);
    return 0;

#undef REQ
#undef REG
#undef IMMV
}

static void encode_lli(Stmt *st, uint32_t *out1, uint32_t *out2) {
    if (st->noperands != 2) die("'lli' 2 operand bekliyor (rd, imm32)");
    int rd = reg_index_or_die(st->operands[0]);
    long v = resolve_operand_as_imm(st->operands[1], st->addr, 0);
    if (v < -2147483648L || v > 2147483647L) die("'lli' icin deger 32-bit'e sigmiyor");
    int32_t hi, lo;
    nevex_split_hi_lo((int32_t)v, &hi, &lo);
    *out1 = nevex_enc_j(OP_LUI, (uint8_t)rd, hi);
    *out2 = nevex_enc_i(OP_ADDI, (uint8_t)rd, (uint8_t)rd, lo);
}

static void write32(uint32_t addr, uint32_t val) {
    out[addr + 0] = (uint8_t)(val & 0xFF);
    out[addr + 1] = (uint8_t)((val >> 8) & 0xFF);
    out[addr + 2] = (uint8_t)((val >> 16) & 0xFF);
    out[addr + 3] = (uint8_t)((val >> 24) & 0xFF);
}

static void pass2(void) {
    for (int i = 0; i < nstmts; i++) {
        Stmt *st = &stmts[i];
        lineno = st->lineno;
        switch (st->kind) {
            case ST_INSTR:
                write32(st->addr, encode_instruction(st));
                break;
            case ST_INSTR2: {
                uint32_t w1, w2;
                encode_lli(st, &w1, &w2);
                write32(st->addr, w1);
                write32(st->addr + 4, w2);
                break;
            }
            case ST_WORD: {
                long v = resolve_operand_as_imm(st->operands[0], st->addr, 0);
                write32(st->addr, (uint32_t)v);
                break;
            }
            case ST_ASCIZ:
                memcpy(&out[st->addr], st->bytes, (size_t)st->nbytes);
                break;
            case ST_ALIGN:
                break;
            case ST_SPACE:
                memset(&out[st->addr], 0, (size_t)st->value);
                break;
        }
    }
}

static void seed_builtin_symbols(void) {
    add_label("MMIO_BASE", NEVEX_MMIO_BASE);
    add_label("MMIO_TX", NEVEX_MMIO_TX - NEVEX_MMIO_BASE);
    add_label("MMIO_EXIT", NEVEX_MMIO_EXIT - NEVEX_MMIO_BASE);
    add_label("MMIO_MTVEC", NEVEX_MMIO_MTVEC - NEVEX_MMIO_BASE);
    add_label("MMIO_MEPC", NEVEX_MMIO_MEPC - NEVEX_MMIO_BASE);
    add_label("MMIO_MCAUSE", NEVEX_MMIO_MCAUSE - NEVEX_MMIO_BASE);
    add_label("MMIO_MPP", NEVEX_MMIO_MPP - NEVEX_MMIO_BASE);
    add_label("MMIO_MIE", NEVEX_MMIO_MIE - NEVEX_MMIO_BASE);
    add_label("MMIO_MTIME", NEVEX_MMIO_MTIME - NEVEX_MMIO_BASE);
    add_label("MMIO_MTIMECMP", NEVEX_MMIO_MTIMECMP - NEVEX_MMIO_BASE);
    add_label("MMIO_KEY", NEVEX_MMIO_KEY - NEVEX_MMIO_BASE);
    add_label("MMIO_RAND", NEVEX_MMIO_RAND - NEVEX_MMIO_BASE);
    add_label("MMIO_SLEEP_MS", NEVEX_MMIO_SLEEP_MS - NEVEX_MMIO_BASE);
    add_label("MMIO_MOUSE_X", NEVEX_MMIO_MOUSE_X - NEVEX_MMIO_BASE);
    add_label("MMIO_MOUSE_Y", NEVEX_MMIO_MOUSE_Y - NEVEX_MMIO_BASE);
    add_label("MMIO_MOUSE_BTN", NEVEX_MMIO_MOUSE_BTN - NEVEX_MMIO_BASE);
    add_label("MMIO_CHAR_X", NEVEX_MMIO_CHAR_X - NEVEX_MMIO_BASE);
    add_label("MMIO_CHAR_Y", NEVEX_MMIO_CHAR_Y - NEVEX_MMIO_BASE);
    add_label("MMIO_CHAR_COLOR", NEVEX_MMIO_CHAR_COLOR - NEVEX_MMIO_BASE);
    add_label("MMIO_CHAR_DRAW", NEVEX_MMIO_CHAR_DRAW - NEVEX_MMIO_BASE);

    add_label("CAUSE_ILLEGAL_INSTR", CAUSE_ILLEGAL_INSTR);
    add_label("CAUSE_LOAD_FAULT", CAUSE_LOAD_FAULT);
    add_label("CAUSE_STORE_FAULT", CAUSE_STORE_FAULT);
    add_label("CAUSE_ECALL_FROM_U", CAUSE_ECALL_FROM_U);
    add_label("CAUSE_ECALL_FROM_M", CAUSE_ECALL_FROM_M);
    add_label("CAUSE_TIMER_INTERRUPT", CAUSE_TIMER_INTERRUPT);
    add_label("CAUSE_UNALIGNED_FETCH", CAUSE_UNALIGNED_FETCH);
    add_label("CAUSE_FETCH_FAULT", CAUSE_FETCH_FAULT);

    add_label("SYS_EXIT", SYS_EXIT);
    add_label("SYS_PRINT_INT", SYS_PRINT_INT);
    add_label("SYS_PRINT_CHAR", SYS_PRINT_CHAR);
    add_label("SYS_PRINT_STR", SYS_PRINT_STR);

    add_label("MODE_MACHINE", MODE_MACHINE);
    add_label("MODE_USER", MODE_USER);

    add_label("FB_BASE", NEVEX_FB_BASE);
    add_label("FB_WIDTH", NEVEX_FB_WIDTH);
    add_label("FB_HEIGHT", NEVEX_FB_HEIGHT);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "kullanim: %s <girdi.asm> <cikti.bin>\n", argv[0]);
        return 1;
    }
    srcname = argv[1];

    seed_builtin_symbols();
    pass1(argv[1]);
    pass2();

    FILE *outf = fopen(argv[2], "wb");
    if (!outf) { fprintf(stderr, "[nevexas] cikti dosyasi acilamadi: %s\n", argv[2]); return 1; }
    fwrite(out, 1, asm_addr, outf);
    fclose(outf);

    fprintf(stderr, "[nevexas] %s -> %s (%u byte, %d satir, %d etiket)\n",
            argv[1], argv[2], asm_addr, nstmts, nlabels);
    return 0;
}
