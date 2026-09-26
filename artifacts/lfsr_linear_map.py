#!/usr/bin/env python3
"""SN76489 15-bit LFSR intertwiner: Fibonacci basin <-> Galois basin.

Clean-room math from public descriptions of the TI SN76489 noise LFSR.
Fibonacci form: right-shift, feedback = bit0 XOR bit1 (period 32767).
Galois form: reciprocal poly x^15 + x^14 + 1, right-shift mask 0x6000.

These are the same maximal orbit ("pocket universe") in two coordinate basins.
The linear map P satisfies G P = P F over GF(2), rank 15.
TI reset 0x4000 and Sega 16-bit seed 0x8000 (via >>1 -> 0x4000) both map to
Galois start 0x0002.

Architectural noise output is the LSB in both forms.
"""
from __future__ import annotations

import numpy as np

N = 15
MASK15 = 0x7FFF
GAL_MASK = 0x6000  # (poly x^15+x^14+1) >> 1


def bits_to_vec(x: int) -> np.ndarray:
    return np.array([(x >> i) & 1 for i in range(N)], dtype=np.uint8)


def vec_to_bits(v: np.ndarray) -> int:
    x = 0
    for i, b in enumerate(np.asarray(v).flat):
        if int(b) & 1:
            x |= 1 << i
    return int(x)


def fib_step(s: int) -> int:
    bit = (s ^ (s >> 1)) & 1
    return ((s >> 1) | (bit << 14)) & MASK15


def gal_step(s: int) -> int:
    lsb = s & 1
    s >>= 1
    if lsb:
        s ^= GAL_MASK
    return s & MASK15


def companion(step):
    M = np.zeros((N, N), dtype=np.uint8)
    for j in range(N):
        M[:, j] = bits_to_vec(step(1 << j))
    return M


def gf2_inv(M: np.ndarray):
    n = M.shape[0]
    Aug = np.concatenate([M.copy().astype(np.uint8), np.eye(n, dtype=np.uint8)], axis=1)
    for col in range(n):
        piv = next((r for r in range(col, n) if Aug[r, col]), None)
        if piv is None:
            return None
        if piv != col:
            Aug[[col, piv]] = Aug[[piv, col]]
        for r in range(n):
            if r != col and Aug[r, col]:
                Aug[r] = (Aug[r] + Aug[col]) % 2
    return Aug[:, n:]


def intertwiner(f_seed: int = 0x4000, g_seed: int = 0x0002) -> np.ndarray:
    cols_in, cols_out = [], []
    v, w = f_seed & MASK15, g_seed & MASK15
    for _ in range(N):
        cols_in.append(bits_to_vec(v))
        cols_out.append(bits_to_vec(w))
        v, w = fib_step(v), gal_step(w)
    A = np.stack(cols_in, axis=1)
    B = np.stack(cols_out, axis=1)
    Ainv = gf2_inv(A)
    if Ainv is None:
        raise RuntimeError("Fibonacci orbit basis not invertible")
    return ((B @ Ainv) % 2).astype(np.uint8)


def apply_P(P: np.ndarray, x: int) -> int:
    return vec_to_bits((P @ bits_to_vec(x & MASK15)) % 2)


def period(step, seed: int) -> int:
    s0 = seed & MASK15
    s = step(s0)
    n = 1
    while s != s0 and n < 40000:
        s = step(s)
        n += 1
    return n


def main() -> None:
    F = companion(fib_step)
    G = companion(gal_step)
    P = intertwiner()

    print("P (rows = Galois bits 0..14, cols = Fibonacci bits 0..14) over GF(2):")
    for r in range(N):
        print(" ".join(str(int(P[r, c])) for c in range(N)))

    p_ti = apply_P(P, 0x4000)
    p_sega = apply_P(P, (0x8000 >> 1) & MASK15)
    gp_pf = np.array_equal((G @ P) % 2, (P @ F) % 2)
    rank = int(np.linalg.matrix_rank(P.astype(float)))
    per_f = period(fib_step, 0x4000)
    per_g = period(gal_step, 0x0002)

    print()
    print(f"P @ TI reset 0x4000      = 0x{p_ti:04X}  (expect 0x0002)  {'PASS' if p_ti == 2 else 'FAIL'}")
    print(f"P @ Sega 0x8000>>1       = 0x{p_sega:04X}  (expect 0x0002)  {'PASS' if p_sega == 2 else 'FAIL'}")
    print(f"G P == P F               {'PASS' if gp_pf else 'FAIL'}")
    print(f"rank(P) == {N}              {'PASS' if rank == N else 'FAIL'} (rank={rank})")
    print(f"Fibonacci period         {per_f}  {'PASS' if per_f == 32767 else 'FAIL'}")
    print(f"Galois period from 0x2   {per_g}  {'PASS' if per_g == 32767 else 'FAIL'}")
    print("Noise tap: architectural LSB in both forms (FORM selects basin, not tap).")
    print("ASSUMED: fib bit0^bit1 + gal mask 0x6000 as reciprocal pair; verify against silicon if needed.")

    ok = all([p_ti == 2, p_sega == 2, gp_pf, rank == N, per_f == 32767, per_g == 32767])
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
