# Spin Operator Verilog Implementation

## Overview

This project implements a hardware-based spin accumulation operator inspired by the local field calculation used in CMOS Ising Machines.  
(To study Flex-Spin : A CMOS Ising Machine With 256 Flexible Spin Processing Elements With 8-b Coefficients for Solving Combinatorial Optimization Problems)  
The module performs signed accumulation of weighted neighboring spin values using:

- XOR-based sign inversion
- Multiple Ripple Carry Adders (RCA)
- Sequential accumulation register
- Synchronous D Flip-Flops

The testbench verifies the MAC behavior cycle-by-cycle using directional spin interactions.

---

# File Structure

| File | Description |
|---|---|
| `spin_operator.v` | DUT (Device Under Test) implementing signed spin accumulation |
| `tb_spin_operator.v` | Testbench verifying sequential MAC accumulation behavior |

---

# DUT : `spin_operator.v`

## Module Description

The `spin_operator` module calculates the accumulated local field:

\[
S = \sum (J_{ij} \times \sigma_j)
\]

where:

- \( J_{ij} \) : signed coupling coefficient
- \( \sigma_j \) : neighboring spin value
    - `spin = 1` → \( +1 \)
    - `spin = 0` → \( -1 \)

The accumulated result is stored in a 12-bit register.

---

# Main Algorithm

## 1. XOR-Based Signed Multiplication

Instead of using a multiplier, sign inversion is implemented using XOR and carry-in logic.

### Case

| spin | Meaning | Operation |
|---|---|---|
| `1` | +1 | \( +J \) |
| `0` | -1 | \( -J \) |

### Logic

```verilog
assign spin_neg = ~spin;
assign c[0] = spin_neg;
assign J_xor = J ^ {8{spin_neg}};
