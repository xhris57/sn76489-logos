# sn76489-logos

Clean-room, cycle-oriented Verilog recreation of the **TI SN76489** PSG, centered on the **15-bit LFSR noise channel**.

Built from public documentation and datasheets (no proprietary dump). Theological / "pocket universe" language in surrounding notes is framing only; this tree is engineering.

## Proven in this repo

| Claim | Evidence |
|-------|----------|
| Fibonacci LFSR period 32767 | `tb/tb_lfsr_period.v` + `artifacts/lfsr_linear_map.py` |
| Galois LFSR period 32767 | same |
| Intertwiner `G P = P F`, `rank(P)=15` | `python3 artifacts/lfsr_linear_map.py` |
| `P @ 0x4000 = 0x0002` | same |
| Sega `0x8000 >> 1` shares TI basin | same |

**Assumed (not silicon-proven here):** Fibonacci feedback `bit0^bit1` paired with Galois mask `0x6000` (poly `x^15+x^14+1`) as reciprocal basins. Tone attenuator curve is a teaching approx.

## Layout

- `sn76489_lfsr.v` — 15-bit LFSR, `FORM` (0=Fib/TI, 1=Galois), rate tick input
- `sn76489.v` — chip skeleton: 3 tones + noise + attenuators + mixer, `FORM=0`,`SEIT=0` defaults
- `artifacts/lfsr_linear_map.py` — computes intertwiner P + verifies seeds/rank/period
- `tb/tb_lfsr_period.v` — iverilog self-check for maximal period both forms

## Quick check

```bash
python3 artifacts/lfsr_linear_map.py
iverilog -g2012 -o /tmp/tb sn76489_lfsr.v tb/tb_lfsr_period.v && vvp /tmp/tb
```
