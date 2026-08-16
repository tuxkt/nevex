# Nevex

Nevex, sıfırdan tasarlanmış register-based bir ISA (Instruction Set Architecture), bu ISA için yazılmış bir sanal makine (VM), assembler ve C-benzeri küçük bir dil için compiler içeren bir projedir. Uzun vadeli hedef, ISA'yı FPGA üzerinde gerçek donanıma taşımak ve üzerinde basit bir işletim sistemi çalıştırmaktır.

> Proje ilk olarak "Vex" adıyla planlandı, ancak GitHub'da VexRiscv ve eski HP VEX ISA ile isim çakışması nedeniyle "Nevex" olarak değiştirildi.

## Neden

Çoğu hobi-VM projesi stack-based bir sanal makineyle sınırlı kalıyor. Nevex, gerçek donanım CPU tasarımına daha yakın bir öğrenme/deney zemini sunmak için register-based bir mimari seçiyor — RISC-V ve ARM'ın tasarım felsefesine yakın durarak, ileride FPGA'ya taşınabilir bir temel oluşturmayı hedefliyor.

## Mimari

- **Tip:** Register-based (RISC-V/ARM tarzı, stack-based değil)
- **Bellek modeli:** Flat memory — MMU veya sanal bellek yok
- **Ayrıcalık seviyeleri:** User mode / kernel mode ayrımı var, bunun ötesinde donanım karmaşıklığı yok

Bu kısıtlar bilinçli: hem VM üzerinde hem de ileride gerçek FPGA donanımında birebir aynı davranışı sağlamak için mimari baştan minimal tutuluyor.

## Bileşenler

| Bileşen | Açıklama | Durum |
|---|---|---|
| ISA spesifikasyonu | Register seti, instruction encoding, adresleme modları | |
| NevexVM | ISA'yı yorumlayan/emüle eden sanal makine (C) | |
| Assembler | Nevex assembly → makine kodu | |
| Compiler | C-benzeri küçük bir dil → Nevex assembly/makine kodu | |
| Nevex OS | VM (ve ileride FPGA) üzerinde çalışacak basit işletim sistemi | Planlanıyor |

## Yol Haritası

1. ISA spesifikasyonunun sabitlenmesi (register sayısı, instruction formatları, opcode tablosu)
2. NevexVM — temel fetch-decode-execute döngüsü
3. Assembler
4. Basit compiler (C-benzeri dil → Nevex ISA)
5. Nevex OS — user/kernel mode ayrımı, temel syscall arayüzü
6. FPGA'ya taşıma (Verilog/VHDL ile donanım implementasyonu)

## Derleme

```sh
git clone https://github.com/<kullanici>/nevex.git
cd nevex
make
```

*(Build sistemi ve bağımlılıklar netleştikçe bu bölüm güncellenecek.)*

## Lisans

*(Lisans belirlenecek — OSS olarak planlanıyor.)*

## Katkıda Bulunma

Proje henüz erken aşamada. ISA tasarımı ve mimari kararlar üzerine tartışma/issue açmak için katkı memnuniyetle karşılanır.
