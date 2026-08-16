# Nevex ISA Specification (v0.1)

Nevex, RISC-V'nin tasarım felsefesinden ilham alan, register-based, 32-bit sabit genişlikte
instruction encoding kullanan basit bir ISA'dır. Amaç; hem yazılımsal bir VM üzerinde hem de
ileride bir FPGA üzerinde donanım olarak kolayca decode edilebilecek kadar sade bir instruction
formatı sunmaktır.

## 1. Genel Özellikler

| Özellik              | Değer                                             |
|-----------------------|---------------------------------------------------|
| Kelime genişliği       | 32-bit                                             |
| Instruction genişliği  | 32-bit, sabit (fixed-width)                        |
| Register sayısı        | 16 genel amaçlı register (`x0`-`x15`), 32-bit      |
| Program counter        | Ayrı 32-bit `PC` register (GPR değil)              |
| Bellek modeli           | 60 KB RAM + 4 KB MMIO, byte-addressable            |
| Endianness              | Little-endian                                      |
| Alignment               | Instruction fetch 4 byte hizalı olmalı             |
| Privilege mode          | 2 seviye: Machine (kernel) ve User (bkz. §8)       |

Register `x0` donanımsal olarak sıfıra sabitlenmiştir (RISC-V `zero` register'ı gibi): okunduğunda
her zaman `0` döner, yazma girişimleri yok sayılır. Bu, donanımda `LI`/`MOV` gibi ek instruction'lara
gerek kalmadan `ADDI rd, x0, imm` ile sabit yükleme yapılmasını sağlar.

## 2. Register Listesi

| Register | ABI adı | Açıklama                                   |
|----------|---------|---------------------------------------------|
| x0       | zero    | Sabit 0 (yazılamaz)                         |
| x1       | ra      | Return address (çağrı dönüş adresi)         |
| x2       | sp      | Stack pointer                               |
| x3       | a0      | Argüman 0 / syscall no / dönüş değeri       |
| x4       | a1      | Argüman 1 / syscall argümanı                |
| x5       | a2      | Argüman 2                                   |
| x6       | a3      | Argüman 3                                   |
| x7       | t0      | Geçici (temporary)                          |
| x8       | t1      | Geçici                                      |
| x9       | t2      | Geçici                                      |
| x10      | t3      | Geçici                                      |
| x11      | t4      | Geçici                                      |
| x12      | t5      | Geçici                                      |
| x13      | t6      | Geçici                                      |
| x14      | s0      | Saved (callee-saved, konvansiyon)            |
| x15      | s1      | Saved (callee-saved, konvansiyon)            |

Bu ABI konvansiyonları donanım tarafından zorlanmaz; sadece yazılım/derleyici anlaşmasıdır
(RET/CALL pseudo-op'ları hariç, bkz. §6).

## 3. Instruction Formatları

Tüm instruction'lar 32 bit'tir. Bit alanlarının pozisyonu format ne olursa olsun mümkün olduğunca
sabit tutulmuştur (opcode her zaman `[31:26]`, `rd`/`imm_hi` her zaman `[25:22]`, `rs1` her zaman
`[21:18]`, `rs2` her zaman `[17:14]`), böylece donanımda register-file okuma hatları format'tan
bağımsız sabit kalır — sadece hangi alanların "immediate" olarak yorumlanacağı değişir. Bu, RISC-V'nin
kullandığı yaklaşımın basitleştirilmiş halidir.

5 format tanımlıdır: **R, I, S, B, J**

```
 31        26 25      22 21      18 17      14 13                        0
+-----------+----------+----------+----------+---------------------------+
|  opcode(6)|  rd(4)   |  rs1(4)  |  rs2(4)  |     funct(6) | rsvd(8)     |   R-type
+-----------+----------+----------+----------+---------------------------+
|  opcode(6)|  rd(4)   |  rs1(4)  |  rsvd(4) |         imm14 (signed)     |   I-type
+-----------+----------+----------+----------+---------------------------+
|  opcode(6)| imm_hi(4)|  rs1(4)  |  rs2(4)  |         imm_lo14           |   S-type
+-----------+----------+----------+----------+---------------------------+
|  opcode(6)| imm_hi(4)|  rs1(4)  |  rs2(4)  |         imm_lo14           |   B-type
+-----------+----------+----------+----------+---------------------------+
|  opcode(6)|  rd(4)   |                imm22 (signed)                   |   J-type
+-----------+----------+--------------------------------------------------+
```

### 3.1 R-type (register-register)
- `opcode` = `0x00` (tüm R-type ALU işlemleri bu opcode'u paylaşır, `funct` alanı ile ayrışır)
- `rd`, `rs1`, `rs2`: register indeksleri (0-15)
- `funct` (6 bit, `[13:8]`): işlem seçici
- `[7:0]`: reserved, `0` olmalı

### 3.2 I-type (register-immediate, load, jalr)
- `imm` = `imm14`, sign-extended, aralık: `-8192 .. 8191`
- `rs2` alanı kullanılmaz, `0` olmalı

### 3.3 S-type (store)
- `rs1`: base adres register'ı, `rs2`: yazılacak veri register'ı
- `imm18 = sign_extend((imm_hi << 14) | imm_lo)`, aralık: `-131072 .. 131071`
- Efektif adres = `rs1 + imm18`

### 3.4 B-type (branch)
- `rs1`, `rs2`: karşılaştırılacak register'lar
- `imm18` S-type ile aynı şekilde hesaplanır
- Hedef adres = `PC_instr + imm18` (koşul doğruysa) — `PC_instr`, dallanma instruction'ının
  **kendi adresi** (fetch edilen adres, henüz +4 ilerletilmemiş hâli)

### 3.5 J-type (jump/link, upper-immediate)
- `rd`: link register (JAL için) veya hedef register (LUI için)
- `imm22`, sign-extended, aralık: `-2097152 .. 2097151`
- JAL: `rd = PC_instr + 4`; hedef adres = `PC_instr + imm22`
- LUI: `rd = imm22 << 14` (bir sonraki `ADDI`'nin ekleyeceği 14-bit'lik alt kısımla tam olarak
  örtüşmeyecek şekilde, 32 bitin üst kısmını doldurur). `imm22` sign-extended olduğu için pratikte
  yalnızca alt 18 biti anlamlıdır (üst 4 bit, `<<14` sonrası 32 biti aşıp taşar) — bu, tam 32-bit
  bir sabit için gereken aralığı (±2³¹) tam olarak karşılar. Bkz. §6 `LLI` pseudo-op'u.

> **Not:** Tüm PC-relative offsetler (`B`, `JAL`), tıpkı RISC-V'de olduğu gibi, dallanma/atlama
> instruction'ının **kendi adresine** görecelidir — `PC+4`'e değil. `JALR` ise mutlak hesaplama
> yapar: `PC = (rs1 + imm) & ~3`.

## 4. Opcode Tablosu

| Opcode (hex) | Mnemonic | Format | Anlam                                          |
|--------------|----------|--------|--------------------------------------------------|
| 0x00         | (R-type) | R      | Bkz. §4.1 funct tablosu                          |
| 0x01         | ADDI     | I      | `rd = rs1 + imm`                                 |
| 0x02         | ANDI     | I      | `rd = rs1 & imm`                                 |
| 0x03         | ORI      | I      | `rd = rs1 \| imm`                                |
| 0x04         | XORI     | I      | `rd = rs1 ^ imm`                                 |
| 0x05         | SLLI     | I      | `rd = rs1 << (imm & 31)`                         |
| 0x06         | SRLI     | I      | `rd = (uint32)rs1 >> (imm & 31)`                 |
| 0x07         | SRAI     | I      | `rd = (int32)rs1 >> (imm & 31)`                  |
| 0x08         | LW       | I      | `rd = MEM32[rs1 + imm]`                          |
| 0x09         | LB       | I      | `rd = sign_extend(MEM8[rs1 + imm])`              |
| 0x0A         | LBU      | I      | `rd = zero_extend(MEM8[rs1 + imm])`              |
| 0x0B         | SW       | S      | `MEM32[rs1 + imm] = rs2`                         |
| 0x0C         | SB       | S      | `MEM8[rs1 + imm] = rs2 & 0xFF`                    |
| 0x0D         | BEQ      | B      | `if (rs1 == rs2) PC += imm`                       |
| 0x0E         | BNE      | B      | `if (rs1 != rs2) PC += imm`                       |
| 0x0F         | BLT      | B      | `if ((i32)rs1 < (i32)rs2) PC += imm`              |
| 0x10         | BGE      | B      | `if ((i32)rs1 >= (i32)rs2) PC += imm`             |
| 0x11         | BLTU     | B      | `if ((u32)rs1 < (u32)rs2) PC += imm`              |
| 0x12         | BGEU     | B      | `if ((u32)rs1 >= (u32)rs2) PC += imm`             |
| 0x13         | JAL      | J      | `rd = PC + 4; PC += imm`                          |
| 0x14         | JALR     | I      | `rd = PC + 4; PC = (rs1 + imm) & ~3`               |
| 0x15         | LUI      | J      | `rd = imm << 14`                                  |
| 0x16         | ECALL    | R*     | Machine mode'a trap eder (`CAUSE_ECALL_FROM_U/M`). Bkz. §8. |
| 0x17         | MRET     | R*     | Trap'ten döner: `mode = mpp; PC = mepc`. Bkz. §8. |
| 0x3F         | HALT     | R*     | VM'i durdurur (exit code = 0). Debug/güvenlik ağı.|

`*` ECALL, MRET ve HALT, R-type kalıbını kullanır ama `rd/rs1/rs2/funct` alanlarını okumaz (hepsi
`0` olmalı).

### 4.1 R-type funct tablosu (opcode 0x00)

| funct (hex) | Mnemonic | Anlam                                          |
|-------------|----------|--------------------------------------------------|
| 0x00        | ADD      | `rd = rs1 + rs2`                                 |
| 0x01        | SUB      | `rd = rs1 - rs2`                                 |
| 0x02        | MUL      | `rd = rs1 * rs2` (alt 32 bit)                     |
| 0x03        | AND      | `rd = rs1 & rs2`                                 |
| 0x04        | OR       | `rd = rs1 \| rs2`                                |
| 0x05        | XOR      | `rd = rs1 ^ rs2`                                 |
| 0x06        | SLL      | `rd = rs1 << (rs2 & 31)`                         |
| 0x07        | SRL      | `rd = (uint32)rs1 >> (rs2 & 31)`                  |
| 0x08        | SRA      | `rd = (int32)rs1 >> (rs2 & 31)`                   |
| 0x09        | SLT      | `rd = ((i32)rs1 < (i32)rs2) ? 1 : 0`              |
| 0x0A        | SLTU     | `rd = ((u32)rs1 < (u32)rs2) ? 1 : 0`              |
| 0x0B        | DIV      | `rd = (i32)rs1 / (i32)rs2` (signed, truncating)   |
| 0x0C        | REM      | `rd = (i32)rs1 % (i32)rs2` (signed)               |
| 0x0D        | DIVU     | `rd = (u32)rs1 / (u32)rs2` (unsigned)             |
| 0x0E        | REMU     | `rd = (u32)rs1 % (u32)rs2` (unsigned)             |

`DIV`/`REM`/`DIVU`/`REMU`, RISC-V M-extension'ın sıfıra bölme/taşma konvansiyonunu izler (donanımda
trap üretmez, exception oluşturmaz):

| Durum                              | DIV/DIVU sonucu | REM/REMU sonucu |
|--------------------------------------|--------------------|----------------------|
| `rs2 == 0`                            | `0xFFFFFFFF` (tümü 1) | `rs1`              |
| Signed taşma (`rs1 = INT32_MIN, rs2 = -1`) | `INT32_MIN`      | `0`                  |

## 5. Syscall Konvansiyonu (ECALL)

`ECALL`, VM'de **doğrudan bir işlem yapmaz** — Machine mode'a trap eder (bkz. §8). Gerçek
syscall servisini (ekrana yazma, sonlandırma, ...) sağlayan kod, trap handler'da MMIO
register'larını kullanarak yazılır (bkz. `examples/kernel.asm`). Aşağıdaki `a0` (x3) syscall
numaraları sadece bir **yazılım konvansiyonu**dur (kernel/user arasındaki anlaşma); VM bunları
tanımaz, `nevexas` bunları built-in sembol olarak sağlar (`SYS_EXIT` gibi, bkz. §10.1):

| a0 (no) | İsim       | Argümanlar                | Onerilen davranış (kernel tarafında)              |
|---------|------------|-----------------------------|------------------------------------------------------|
| 0       | SYS_EXIT       | a1 = exit code       | `MMIO_EXIT`'e `a1` yazilir                          |
| 1       | SYS_PRINT_INT  | a1 = değer (i32)     | `a1` decimal'e cevrilip `MMIO_TX`'e byte byte yazilir |
| 2       | SYS_PRINT_CHAR | a1 = karakter (alt 8 bit) | `a1`'in alt byte'i `MMIO_TX`'e yazilir          |
| 3       | SYS_PRINT_STR  | a1 = bellek adresi   | `a1`'den itibaren NUL'e kadar `MMIO_TX`'e yazilir     |

`examples/kernel.asm`, bu tabloyu tam olarak uygulayan calisan bir trap handler icerir
(`print_int` alt-rutini dahil).

## 6. Pseudo-Instruction'lar (Fonksiyon Çağrısı: call/ret)

Nevex donanımı sadece `JAL`/`JALR` sağlar; `CALL`/`RET`, RISC-V'deki gibi bunların üzerine kurulu
software konvansiyonlarıdır (assembler/programcı tarafından üretilir, ek opcode gerektirmez):

| Pseudo-op     | Gerçek encoding      | Anlam                                   |
|---------------|----------------------|-------------------------------------------|
| `CALL label`  | `JAL ra, label`      | `ra = PC+4`; `PC = PC + offset`; fonksiyona dallan |
| `RET`         | `JALR x0, ra, 0`     | `PC = ra`; dönüş değeri okunmaz          |
| `JMP label`   | `JAL x0, label`      | Koşulsuz dallanma, link yok               |
| `NOP`         | `ADDI x0, x0, 0`     | Hiçbir şey yapmaz                          |
| `MOV rd, rs`  | `ADDI rd, rs, 0`     | Register kopyalama                        |
| `LI rd, imm`  | `ADDI rd, x0, imm`   | Küçük sabit yükleme (`-8192..8191`)       |
| `LLI rd, imm32` | `LUI rd, hi` + `ADDI rd, rd, lo` | Herhangi bir 32-bit sabit/adres (2 instruction) |

`LLI`, tek `LI`'nin sığamadığı büyük sabitler (ör. `MMIO_BASE = 0xF000`) için kullanılır; assembler
`hi`/`lo` bölünmesini otomatik hesaplar (bkz. §3.5). Boyutu her zaman 2 word'dür (deger ne olursa
olsun), bu yuzden adres hesaplamalari degere bagli degildir.

Konvansiyon gereği çağrı yapan fonksiyon argümanları `a0-a3`'e koyar, dönüş değerini `a0`'dan okur;
`sp` (x2) yığın üzerinde yerel değişkenler/geri kaydedilen register'lar için kullanılır (push/pop
donanımda yoktur, `SW`/`LW` + `ADDI sp, sp, ±imm` ile yazılım seviyesinde yapılır).

## 7. Bellek Modeli

- 64 KB adres alanı (`0x0000` - `0xFFFF`), little-endian, ikiye bölünmüştür:
  - `0x0000 - 0xEFFF` (60 KB): normal RAM — kod, veri, stack.
  - `0xF000 - 0xFFFF` (4 KB): **memory-mapped I/O** (MMIO), RAM değildir; bkz. §8.3.
- Program adres `0x0000`'dan itibaren yüklenir; VM her zaman Machine mode'da, `PC=0`'da açılır.
- Stack, MMIO bölgesinin hemen altından (`sp = 0xF000` ile, VM başlangıcında) aşağı doğru büyür.
- RAM sınırları dışına (fetch, load, store) erişim ya da MMIO'ya izinsiz erişim CPU-seviyesi bir
  **trap**'e neden olur (VM'i durdurmaz, bkz. §8) — sadece assembler/host seviyesi hatalar (örn.
  program dosyası 60 KB'den büyükse) fatal'dır.
- Word erişimleri (`LW`/`SW`) 4-byte hizalanmış olmak *zorunda değildir* (basitlik için); ancak
  instruction fetch her zaman 4-byte hizalı olmalıdır.

## 8. Privilege Modes ve Trap/Interrupt Mekanizması

Nevex, gerçek bir OS'in ihtiyaç duyacağı asgari donanımı sağlar: 2 ayrıcalık seviyesi, tek-seviyeli
bir trap mekanizması ve memory-mapped bir kontrol/I-O bloğu. Bu, RISC-V'nin Machine-mode privilege
mimarisinin (ve CLINT'inin) fazlasıyla basitleştirilmiş bir alt kümesidir.

### 8.1 Modlar

| Mod           | Değer | Açıklama                                                        |
|----------------|-------|--------------------------------------------------------------------|
| `MODE_MACHINE` | 0     | Ayrıcalıklı (kernel) mod. MMIO'ya ve `MRET`'e erişebilir.          |
| `MODE_USER`    | 1     | Ayrıcalıksız (uygulama) mod. MMIO erişimi ve `MRET` fault üretir.  |

VM her zaman `MODE_MACHINE`'de, `PC=0`'da açılır (bkz. §7). User mode'a geçiş sadece bir trap
donuşü (`MRET`) ile olur — kernel, ilk kullanıcı programını başlatmak için `MMIO_MPP`'yi
`MODE_USER` yapıp `MMIO_MEPC`'yi kullanıcı giriş noktasına ayarlayıp `MRET` calistirir (bkz.
`examples/kernel.asm`, `boot:`).

### 8.2 Trap Alma Semantiği

Bir trap (hata ya da interrupt) oluştuğunda CPU **otomatik olarak** şunu yapar (yazılım
müdahalesi olmadan, `MRET` haricinde):

```
mpp    = mode              ; trap oncesi mod kaydedilir (MRET'in donecegi mod)
mepc   = <trap adresi>      ; fault'a neden olan / kesilen instruction'in adresi
mcause = <neden kodu>        ; asagidaki CAUSE_* tablosu
mode   = MODE_MACHINE          ; her zaman Machine mode'a gecilir
mie    = 0                      ; global interrupt enable otomatik kapatilir
PC     = mtvec                  ; trap handler'a atlanir
```

`mie`'nin trap girisinde otomatik sifirlanmasi onemlidir: aksi halde, handler'in ilk instruction'i
daha calismadan bir sonraki `step()` cagrisinda `mtime >= mtimecmp` kosulu hala true olacagi icin
timer trap'i tekrar tetiklenir (mepc/mcause/mpp ustune yazilir, handler hicbir zaman calisamaz).
Bu, gercek RISC-V donanimindaki `mstatus.MIE`'nin trap girisinde otomatik temizlenmesiyle ayni
amaci tasir. Nevex'te ayri bir "onceki mie" saklama alani (RISC-V'deki `MPIE` gibi) olmadigindan,
handler interrupt'lari tekrar acmak istiyorsa (`MMIO_MIE` = 1) bunu donusten (`MRET`) once, ve
mtimecmp'yi zaten ilerletmisken, kendisi yapmalidir — bkz. `examples/kernel.asm`.

`MRET`, tersini yapar: `mode = mpp; PC = mepc` (yalniz Machine mode'da calisir; User mode'dan
calistirilirsa kendisi de illegal-instruction trap'i uretir). `MRET`, `mie`'ye dokunmaz — bunu
software (`MMIO_MIE` yazarak) yonetir.

**ECALL** her zaman Machine mode'a trap eder (mevcut mod User ya da Machine olsa da); syscall
argumanlari sıradan GPR'lerdir (`a0`/`a1`), trap tarafindan etkilenmez. Handler, `mepc`'yi
donmeden once **4 arttirmalidir** (`ecall` instruction'inin uzerinden atlamak icin) — aksi halde
`MRET` ayni `ecall`'a geri doner ve sonsuz donguye girilir.

| CAUSE (hex/dec) | İsim                    | Ne zaman olusur                                    |
|-------------------|--------------------------|--------------------------------------------------------|
| 0                 | CAUSE_ILLEGAL_INSTR      | Bilinmeyen opcode/funct, ya da User mode'da `MRET`     |
| 1                 | CAUSE_LOAD_FAULT         | RAM disina LW/LB/LBU, ya da User mode'dan MMIO load    |
| 2                 | CAUSE_STORE_FAULT        | RAM disina SW/SB, ya da User mode'dan MMIO store       |
| 3                 | CAUSE_ECALL_FROM_U       | `ecall`, mode=User iken calistirildi                    |
| 4                 | CAUSE_ECALL_FROM_M       | `ecall`, mode=Machine iken calistirildi                  |
| 5                 | CAUSE_TIMER_INTERRUPT    | `mie` aktif ve `mtime >= mtimecmp`                        |
| 6                 | CAUSE_UNALIGNED_FETCH    | `PC % 4 != 0` durumunda fetch denemesi                    |
| 7                 | CAUSE_FETCH_FAULT        | (Rezerve; su an fetch de load-fault yolunu kullanir)      |

> **Sinirlama:** Trap durumu (`mepc`/`mcause`/`mpp`) **tek seviyelidir** — ic ice (nested) bir trap
> bir onceki trap'in bilgisini ustune yazar. Timer interrupt kullanan bir kernel, kritik
> bolgelerde `MMIO_MIE`'yi temizlemelidir (gercek donanimlarin da yaptigi gibi).

### 8.3 Memory-Mapped I/O (MMIO)

`0xF000-0xFFFF` bolgesi sadece **32-bit (LW/SW) erisimi destekler**; `LB/SB/LBU` bu bolgeye
erisirse (mod ne olursa olsun) load/store fault uretir. **Sadece Machine mode** bu bolgeye
erisebilir; User mode'dan erisim load/store fault'a donusur (bkz. §8.2).

| Adres    | Isim (offset MMIO_BASE'e gore) | R/W | Anlam                                    |
|----------|-----------------------------------|-----|-----------------------------------------------|
| 0xF000   | MMIO_TX                            | W   | Dusuk byte'i stdout'a yazar (UART TX benzeri) |
| 0xF004   | MMIO_EXIT                           | W   | VM'i bu deger exit code'u ile durdurur         |
| 0xF008   | MMIO_MTVEC                          | R/W | Trap vektoru adresi                             |
| 0xF00C   | MMIO_MEPC                           | R/W | Trap anindaki/donus PC'si                        |
| 0xF010   | MMIO_MCAUSE                         | R/W | Son trap'in nedeni (CAUSE_*)                     |
| 0xF014   | MMIO_MPP                            | R/W | Trap oncesi mod (MRET'in donecegi mod)           |
| 0xF018   | MMIO_MIE                            | R/W | bit0: global interrupt enable                      |
| 0xF01C   | MMIO_MTIME                          | R/W | Her adimda (instruction) 1 artan sayac             |
| 0xF020   | MMIO_MTIMECMP                       | R/W | `MTIME >= MTIMECMP` oldugunda timer trap'i tetiklenir |
| 0xF024   | MMIO_KEY                            | R   | Son basilan yon tusu (0=yok,1=up,2=down,3=left,4=right); sadece `nevex-gui`'de doludur |
| 0xF028   | MMIO_RAND                           | R   | Okundukca yenilenen 32-bit pseudo-random deger      |
| 0xF02C   | MMIO_SLEEP_MS                       | W   | Yazilan ms (max 1000) kadar VM'i **gercek zamanda** bekletir |
| 0xF030   | MMIO_MOUSE_X                        | R   | Fare imlecinin framebuffer hucre-koordinati (0-127), sadece `nevex-gui`  |
| 0xF034   | MMIO_MOUSE_Y                        | R   | Fare imlecinin framebuffer hucre-koordinati (0-127), sadece `nevex-gui`  |
| 0xF038   | MMIO_MOUSE_BTN                      | R   | Sol fare tusu su an basili mi (1/0), sadece `nevex-gui`                   |
| 0xF03C   | MMIO_CHAR_X                         | R/W | Bir sonraki karakterin x konumu (yazilinca "sol kenar" da guncellenir, bkz. asagi) |
| 0xF040   | MMIO_CHAR_Y                         | R/W | Bir sonraki karakterin y konumu                       |
| 0xF044   | MMIO_CHAR_COLOR                     | R/W | Bir sonraki karakterin rengi (RGB332)                  |
| 0xF048   | MMIO_CHAR_DRAW                      | W   | Yazilan ASCII karakteri framebuffer'a "basar", cursor'u ilerletir |
| 0xF04C   | MMIO_STDIN                          | R   | stdin'den bir sonraki byte'i okur; veri kalmadiysa (EOF) `0xFFFFFFFF` doner |

`MMIO_CHAR_*`, gercek eski donanimlardaki "karakter ureteci" (character generator) cipslerinin
(Apple II, C64 vb.) basitlestirilmis bir benzeri: yazilim sadece ASCII kodu yaziyor, glyph'i
piksel piksel cizmek donanimin (VM'in) isi. 3x5 piksellik sabit-genislikli bir font iceriyor —
bosluk, `0-9`, `A-Z`, `.`, `:`, `!` destekleniyor (kapsam disi karakterler bos birakilir).
`MMIO_CHAR_DRAW`'a yazilan her karakterden sonra `char_x` otomatik olarak 4 piksel ilerler (teleks/
konsol mantigi); `'\n'` (10) yazilirsa `char_x`, en son `MMIO_CHAR_X`'e yazilan degere (sol kenar)
doner ve `char_y` 6 artar. Bu sayede bir string yazdirmak sadece `MMIO_CHAR_X/Y/COLOR`'i bir kere
ayarlayip, string'in her byte'ini sirayla `MMIO_CHAR_DRAW`'a yazan bir dongu ile yapilir — `MMIO_TX`
ile ayni sadelikte (bkz. `examples/font_test.asm`).

`MMIO_BASE` (`0xF000`) tipik olarak 14-bit `ADDI`/`LW` immediate araligina sigmadigi icin, kernel
kodu genelde bunu bir kere `LLI` ile bir register'a (konvansiyon: `s0`) yukleyip sonrasinda kucuk
offsetlerle erisir (`sw t0, MMIO_MTVEC(s0)` gibi) — bkz. `examples/kernel.asm`.

### 8.4 Framebuffer (ekran cihazi)

Kontrol MMIO'sundan (§8.3) ayri, adres uzayinda daha yukarida (`0xF000-0xFFFF`'in hemen ustunde)
duran ikinci bir cihaz bolgesi: dogrudan piksel belleği. Kontrol register'lari gibi tek tek
isimlendirilmis alanlar degil, duz bir bayt dizisidir — gercek bir VRAM/framebuffer donanimi gibi.

| Ozellik          | Deger                                                        |
|--------------------|------------------------------------------------------------------|
| `FB_BASE`           | `0x10000`                                                        |
| Boyut                | `FB_WIDTH x FB_HEIGHT` = `128 x 128` = 16384 byte                 |
| Piksel formati        | 1 byte/piksel, **RGB332** (`[7:5]`=R, `[4:2]`=G, `[1:0]`=B)         |
| Erisim                | `LB`/`SB` (tek piksel) ve `LW`/`SW` (4 piksel birden, little-endian) |
| Ayricalik             | **Sadece Machine mode** (kontrol MMIO ile ayni kural, bkz. §8.3)   |
| Adresleme              | `pixel(row,col) = FB_BASE + row*FB_WIDTH + col`                    |

`FB_WIDTH` 2'nin kuvveti oldugu icin `row*FB_WIDTH` bir `SLLI`(7) ile hesaplanabilir; pratikte
en verimli yontem, satir/sutun dongusu boyunca tek bir "cursor" register'ini `addi cur, cur, 1`
ile artirmaktir (bkz. `examples/gui_demo.asm`, klasik bir XOR-desen demosu: `pixel = row XOR col`).

Bu bolgeye yazilan her byte, VM'in kendisi tarafindan **surekli tarama yapan bir ekran** gibi
davranilir — ayri bir "present"/"vsync" MMIO sinyaline gerek yoktur, gercek bir VGA/framebuffer
donanimi da boyle calisir:

- Standart `nevex` binary'si (SDL2 gerektirmez): program haltlandiginda framebuffer'a hic
  yazilmamissa hicbir sey yapmaz; en az bir byte yazilmissa calisma dizininde `nevex_fb.ppm`
  (duz P6 PPM) dosyasina son kareyi yazar — headless/CI ortaminda bile framebuffer ciktisini
  dogrulamak icin yeterlidir.
- `nevex-gui` (SDL2 gerektirir, `nix-shell -p SDL2 --run "make nevex-gui"` ile derlenir): ayni
  seyi yapar, ustune canli bir SDL penceresinde ~50 adimda bir kareyi gunceller; program
  haltlandiktan sonra pencere, kullanici kapatana ya da ESC'e basana kadar son kareyi gostermeye
  devam eder.

## 9. FPGA'ye Taşınabilirlik Notları

- Register field pozisyonları (`opcode`, `rd`, `rs1`, `rs2`) format bağımsız sabittir → decode
  aşaması tek bir kombinasyonel blok olabilir, format'a göre mux'lanan tek şey immediate
  generator'dur.
- Tüm ALU işlemleri (R-type) tek opcode + funct ile gruplu → tek bir ALU bloğu + funct → opcode
  mapping tablosu yeterli.
- Immediate genişlikleri (14/18/22 bit) sign-extension donanımında basit birer mux + sign-bit
  replicate devresi ile üretilebilir.
- MMIO bölgesi (§8.3), gerçek RISC-V donanımlarındaki CLINT (Core-Local Interruptor) fikrinin
  basitleştirilmiş bir benzeridir — `mtime`/`mtimecmp` bile aynı isimlerle, aynı memory-mapped
  yaklaşımla var. FPGA'de bu bölge, adres decode mantığının bir "peripheral bus" bloğuna
  yönlendirilmesiyle doğal olarak gerçeklenir (UART TX register'ı, gerçek bir UART çekirdeğine
  bağlanabilir).
- Privilege mode tek bitlik bir register'dır (donanımda 1 flip-flop); trap alma mantığı (§8.2)
  kombinasyonel + birkaç register'a yazmadan ibarettir, mikrokod gerektirmez.
- Framebuffer (§8.4), FPGA'de dogal olarak bir dual-port Block RAM'e (bir port CPU'nun
  LB/SB/LW/SW erisimi icin, diger port bir VGA/HDMI tarama devresinin surekli okumasi icin)
  karsilik gelir — yazilim tarafinda "present" sinyaline gerek olmamasi tam da bu yuzdendir,
  ikinci port zaten surekli taniyor.

## 10. Toolchain: `nevex` (VM) ve `nevexas` (Assembler)

Proje iki C programından oluşur, ikisi de `isa.h` içindeki ortak opcode/encoding tanımlarını
paylaşır (VM ile assembler'ın encoding'i asla birbirinden sapmaz):

```
make            # nevex ve nevexas'i derler
./nevexas program.asm program.bin     # metin assembly -> ham binary
./nevex program.bin                   # binary'i calistir
./nevex                                 # argumansiz: gomulu MMIO smoke-test demosu calisir
```

Framebuffer kullanan programlar icin (bkz. §8.4), SDL2 gerektiren opsiyonel bir hedef de var:

```
nix-shell -p SDL2 --run "make nevex-gui"    # SDL2'li VM'i derler (SDL2 gerektirir)
./nevex-gui program.bin                       # canli pencerede framebuffer'i gosterir
```

SDL2 kurulu degilse `./nevex program.bin` yine calisir; framebuffer'a yazan bir program
haltlandiginda son kareyi otomatik olarak `nevex_fb.ppm` dosyasina yazar.

### 10.1 Assembly Sözdizimi

- Satır başına bir etiket (`label:`) ve/veya bir komut/direktif.
- Yorum: `;` veya `#` karakterinden satır sonuna kadar.
- Register: `x0`-`x15` ya da ABI adları (`zero`, `ra`, `sp`, `a0-a3`, `t0-t6`, `s0-s1`).
- Immediate: decimal (`-12`), hex (`0x1F`), karakter literal (`'a'`, `'\n'`, `'\0'`).
- Tüm gerçek instruction'lar (`add`, `addi`, `lw`, `beq`, `jal`, `ecall`, `mret`, ... — bkz. §4) ve
  pseudo-instruction'lar (`nop`, `li`, `lli`, `mov`, `jmp`, `call`, `ret` — bkz. §6) desteklenir.
- Load/Store operandı RISC-V stilinde yazılır: `lw t0, 4(sp)`, `sw t1, 0(a0)`.
- Branch/Jump hedefleri register yerine etiket adı olarak yazılır (`beq t0, zero, end`,
  `jal ra, factorial`); offset assembler tarafından otomatik hesaplanır.
- `nevexas`, §5 ve §8'deki tüm `MMIO_*`, `CAUSE_*`, `SYS_*`, `MODE_*` isimlerini **built-in sembol**
  olarak önceden tanımlar — bunlar sıradan bir etiket gibi kullanılabilir (`lli s0, MMIO_BASE`,
  `sw t0, MMIO_MTVEC(s0)`, `li t1, CAUSE_ECALL_FROM_U`). Kullanıcı kodu bu isimleri kendi etiketi
  olarak tekrar tanımlarsa assembler hata verir.

### 10.2 Direktifler

| Direktif          | Anlam                                                          |
|--------------------|------------------------------------------------------------------|
| `.word imm`        | 4 byte'lık ham değer gömer (immediate ya da bir etiket adresi)   |
| `.asciz "metin"`   | NUL-terminated string gömer (`\n`, `\t`, `\0`, `\\`, `\"` kaçışları desteklenir) |
| `.align N`         | Bir sonraki adresi `N`'in katına hizalamak için sıfır byte ekler |
| `.space N`          | `N` sıfır byte ayırır (dizi/scratch değişkeni için yer açar)      |

Kod ve veri aynı adres alanını paylaştığı için (`.asciz`/`.word`/`.space` gibi) veri bloklarını,
üzerinden "düşerek" (fall-through) instruction gibi çalıştırılmasını önlemek amacıyla genellikle
bir `jmp`/`call`'dan sonra ya da fonksiyonun en sonuna yerleştirin (bkz. `examples/hello.asm`).
`.asciz`/`.space` toplam uzunluğu 4'ün katı olmayabilir — hemen ardından kod geliyorsa (instruction
fetch alignment gerektirdiği için, bkz. §7) bir `.align 4` eklemeyi unutmayın (bkz.
`examples/snake.asm`, ki bunu unutup önce hizası bozuk bir binary üretmişti).

### 10.3 Örnekler

- `examples/factorial.asm` — `call`/`ret` ile iteratif faktoriyel; sonucu MMIO üzerinden doğrudan
  yazdırır (Machine mode, privilege geçişi yok). `print_int` alt-rutini `DIV`/`REM` eklenmeden önce
  yazıldığı için ondalık yazdırmayı hâlâ tekrarlı çıkarma ile yapıyor — donanımda artık `DIV`/`REM`
  olduğundan yeni kod bunları doğrudan kullanabilir (bkz. §4.1).
- `examples/hello.asm` — `.asciz` ile string gömme, `sw`/`lw` ile bellek erişimi; MMIO'ya doğrudan
  yazar (Machine mode).
- `examples/kernel.asm` — **flagship örnek**: `boot` (Machine mode) trap vektörünü ve
  `MMIO_MTIMECMP`/`MMIO_MIE`'yi kurup `mret` ile User mode'a düşer; `user_main` (User mode) `ecall`
  ile syscall ister (`SYS_PRINT_INT`, `SYS_PRINT_STR`, `SYS_EXIT`); `trap_handler` (Machine mode)
  `mcause`'a bakıp senkron syscall trap'lerini (`th_syscall`) asenkron timer interrupt'lerinden
  (`th_timer`) ayırt eder — ikincisi periyodik olarak `MMIO_MTIMECMP`'yi ileri alıp bir `.` basarak
  user kodunun (busy-loop) ortasında **kesintiye uğradığını** görünür kılar. Her iki dönüş yolu da
  `MRET`'ten önce `MMIO_MIE`'yi yeniden 1 yapar (donanım trap girişinde otomatik 0'lar, bkz. §8.2).
  Tam bir privilege-separated, interrupt-driven "mini OS" iskeletinin çalışan hâlidir — bir OS'in
  üzerine inşa edilebileceği ilk katman budur.
- `examples/gui_demo.asm` — framebuffer'a (§8.4) klasik bir XOR deseni çizer (`pixel = row XOR
  col`), tek bir "cursor" register'ini piksel piksel artırarak. Machine mode, privilege geçişi
  yok. `./nevex` ile çalıştırılırsa deseni `nevex_fb.ppm`'e yazar; `nevex-gui` ile çalıştırılırsa
  canlı bir pencerede gösterir.
- `examples/snake.asm` — **oyun örneği**: framebuffer'ı hem ekran hem de (renk okuyarak) kendi
  çarpışma haritası olarak kullanan klasik bir yılan oyunu. `MMIO_KEY` ile yön okur (yalnızca
  `nevex-gui`'de dolu — düz `nevex`'te yılan hep varsayılan yönde gidip duvara çarpar, headless
  test için kullanışlı), `MMIO_RAND` ile boş bir hücre bulana kadar yem üretir, `MMIO_SLEEP_MS`
  ile gerçek zamanlı bir "tick" hızı sağlar. Gövde, dairesel bir tampon olarak `.space` ile
  ayrılmış `body_x`/`body_y` dizilerinde tutulur (kuyruk pikselini silmek için gerekli); kafa
  çarpışması ise ayrı bir dizi taraması yerine doğrudan hedef pikselin rengini okuyarak yapılır —
  video belleğini kendi çarpışma haritası olarak kullanmak, klasik bir donanım-seviyesi numara.
  `spawn_food`, kendi içinde `pixel_addr`'ı çağırdığı için `ra`'yı stack'e kaydedip geri
  yüklüyor (bkz. §6) — iç içe `call` yapan her alt-rutin için gerekli bir kural.
- `examples/font_test.asm` — `MMIO_CHAR_*` (§8.4) ile framebuffer'a metin yazan basit bir örnek;
  `nevexas`/`nevex` ile (GUI gerekmeden) çalıştırılıp `nevex_fb.ppm`'e bakarak fontun doğru
  render olduğu doğrulanabilir.
- `examples/desktop.asm` — framebuffer içinde **modern-OS tarzı** bir mini masaüstü ortamı: alt
  şeritte bir **taskbar** (koyu lacivert, `MMIO_MTIME` yerine kendi `tick_count`'undan `DIV`/`REM`
  ile hesapladığı gerçek zamanlı bir `MM:SS` saat + 3 uygulama ikonu), üstte 3 **sürüklenebilir
  pencere**: **Kalem** (çizim), **Top** (otomatik zıplayan "DVD logosu" animasyonu, sınırdan taşma
  `sub x,zero,x` ile eksen negatiflenerek tespit edilir), **Sayaç** (tıkladıkça büyüyen bir çubuk).
  - **Göster/gizle**: taskbar'daki bir ikona tıklamak o pencereyi açar/kapatır (`visible0/1/2`) —
    gerçek bir dock/taskbar'daki uygulama simgesi gibi.
  - **Z-order**: bir pencerenin başlık çubuğuna tıklamak (sürüklemeye başlamanın yanında) onu
    `front_win` yapar; her turun çizim sırası `front_win`'i en sona bırakacak şekilde ayarlanır,
    böylece üstüne tıkladığın pencere görsel olarak da öne gelir.
  - **Sürükleme**: başlık çubuğuna **yeni** basılan bir tık (`prev_btn` ile kenar/edge algılama)
    o pencereyi `drag0/1/2` bayrağıyla işaretler + tıklanan noktanın pencere köşesine göre ofseti
    kaydeder; tık basılı kaldığı sürece pencere fareyi takip eder, ekran/taskbar sınırlarına
    clamp'lenir.

  Her tur **tüm ekran temizlenip taskbar + görünür pencereler yeniden çizilir** (immediate-mode
  compositing — sürüklenen pencere iz bırakmasın, z-order her karede doğru olsun diye). Kalem
  penceresinin çizimi, pencereyle birlikte hareket etmesi için framebuffer'a değil `paint_buf`
  adlı pencere-yerel bir RAM tamponuna (`.space 1600`, 50×32) yazılır ve her turda `blit_paint`
  ile o anki pencere konumuna kopyalanır — gerçek bir pencere sisteminin "içerik pencereyle
  birlikte taşınır" davranışının minyatür hali. `draw_w0`/`draw_w1`/`draw_w2`, kendi `visibleN`
  bayrağını kontrol edip kapalıysa hemen `ret` eden birer sarmalayıcı; ana döngü, `front_win`'e
  göre hangisinin en son (en üstte) çizileceğine karar verip bu üçünü çağırıyor.

  `fill_rect`, `blit_paint` gibi değişken-boyutlu döngülerin **ön-test** (önce sınır kontrolü,
  sonra çiz) olarak yazılması önemli — ilk sürümde post-test (önce çiz, sonra kontrol et)
  yazılmıştı ve boyut 0 olduğunda bile en az 1 piksel çiziyordu (sayaç 0'ken bile görünen bir
  çubuk şeklinde ortaya çıktı, otomatik render testiyle yakalandı). Taskbar'ın ilk rengi de
  (RGB332 `60`) hesap hatasıyla parlak yeşil çıkmıştı — RGB332'nin `[7:5]=R,[4:2]=G,[1:0]=B`
  bit yerleşimini elle hesaplarken dikkatli olmak gerekiyor (bkz. §8.4).
  `draw_window_chrome`/`blit_paint`/`draw_taskbar`/`draw_w0-2` kendi içinde başka alt-rutin
  çağırdığı için (nested call) `ra`'yı (ve gerekirse `a0-a3`/`t1` gibi çağrıdan sonra hâlâ lazım
  olan register'ları) stack'e kaydedip geri yüklüyor — `spawn_food` ile aynı kural (bkz. §6).

Hepsi `nevexas` ile derlenip `nevex` (ya da framebuffer/fare/klavye gerektiren örnekler için
`nevex-gui`) ile doğrudan çalıştırılabilir.
