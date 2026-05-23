# FlexSpin Spin Operator Verilog Simulation

This repository contains a Verilog implementation and testbench for a simplified **spin operator** used in an Ising-machine-style processing element.

The design is inspired by the paper:

> **Flex-Spin: A CMOS Ising Machine With 256 Flexible Spin Processing Elements With 8-b Coefficients for Solving Combinatorial Optimization Problems**

This code is not an official implementation of the paper.
It is written for educational purposes to understand how a spin interaction term can be accumulated using digital logic.

---

## 1. File Overview

| File                 | Description                                                                 |
| -------------------- | --------------------------------------------------------------------------- |
| `spin_operator.v`    | DUT file containing the spin operator, full adder, and D flip-flop modules. |
| `tb_spin_operator.v` | Testbench file that verifies the MAC-based spin accumulation operation.     |

---

## 2. Design Goal

The goal of this design is to implement the local field accumulation used in an Ising machine.  
It's over all structure looks like:  
<p align="center">
<img width="20%" alt="Image" src="https://github.com/user-attachments/assets/8f4402af-8bd3-4622-984f-77307d8bfe72" />
</p>
For a target spin $\sigma_i$, the local field is computed as:

$$
L_i = \sum_j J_{ij}\sigma_j
$$

where:

* $J_{ij}$ is the interaction coefficient between spin $i$ and spin $j$.
* $\sigma_j$ is the neighboring spin.
* $L_i$ is the accumulated local field.
* The sign of $L_i$ determines the next spin state.

The spin bit encoding used in this design is:

$$
\text{spin bit } 1 \rightarrow +1
$$

$$
\text{spin bit } 0 \rightarrow -1
$$

---

## 3. DUT: `spin_operator.v`

### 3.1 Module Description

The `spin_operator` module performs a multiply-accumulate operation for Ising spin updates.

The main operation is:

$$
S \leftarrow S + J \cdot \sigma
$$

where:

* `S` is the 12-bit accumulated local field.
* `J` is an 8-bit signed interaction coefficient.
* `spin` is the input spin bit.
* `spin = 1` represents $+1$.
* `spin = 0` represents $-1$.

The design use a XOR-based multiplier to calculate two's-complement sign conversion.

---

### 3.2 Top Module Interface

```verilog
module spin_operator(
    input wire clk,
    input wire rst_n,
    input wire acc_clear,
    input wire en,
    input wire [7:0] J,
    input wire spin,
    output wire [11:0] S,
    output wire MSB_sign
);
```

---

### 3.3 Input Ports

| Signal      | Width | Description                                                 |
| ----------- | ----: | ----------------------------------------------------------- |
| `clk`       | 1-bit | Clock signal.                                               |
| `rst_n`     | 1-bit | Active-low synchronous reset for the accumulator registers. |
| `acc_clear` | 1-bit | Clears the accumulated value `S` to zero.                   |
| `en`        | 1-bit | Enables one MAC accumulation operation.                     |
| `J`         | 8-bit | Signed interaction coefficient.                             |
| `spin`      | 1-bit | Input spin value. `1` means `+1`, and `0` means `-1`.       |

---

### 3.4 Output Ports

| Signal     |  Width | Description                                |
| ---------- | -----: | ------------------------------------------ |
| `S`        | 12-bit | Accumulated local field value.             |
| `MSB_sign` |  1-bit | Sign bit of `S`. This is equal to `S[11]`. |

---

### 3.5 Internal Signals

| Signal     |  Width | Description                                                                |
| ---------- | -----: | -------------------------------------------------------------------------- |
| `spin_neg` |  1-bit | Inverted spin bit. Used to decide whether `J` should be converted to `-J`. |
| `J_xor`    |  8-bit | XOR-converted coefficient. Represents either `J` or `~J`.                  |
| `c`        | 13-bit | Carry chain for the ripple-carry adder.                                    |
| `rca_sum`  | 12-bit | Output of the 12-bit ripple-carry accumulator.                             |
| `d_next`   | 12-bit | Next value to be stored in the accumulator registers.                      |
| `reg_en`   |  1-bit | Register enable signal. Activated when `en` or `acc_clear` is high.        |

---

## 4. Core Algorithm

### 4.1 Spin-Controlled Multiplication

The design computes:

$$
J \cdot \sigma
$$

where:

$$
\sigma \in {+1, -1}
$$

Because the spin is represented as a single bit, multiplication by $+1$ or $-1$ is implemented using XOR and two's-complement arithmetic.

```verilog
assign spin_neg = ~spin;
assign c[0] = spin_neg;
assign J_xor = J ^ {8{spin_neg}};
```

If `spin = 1`, then:

```text
spin_neg = 0
J_xor = J
c[0] = 0
```

Therefore, the module performs:

$$
S \leftarrow S + J
$$

If `spin = 0`, then:

```text
spin_neg = 1
J_xor = ~J
c[0] = 1
```

Therefore, the module performs:

$$
S \leftarrow S + \sim J + 1 = S - J
$$

As a result, the module implements:

$$
S \leftarrow S + J\sigma
$$

without using a conventional multiplier.

---

### 4.2 Ripple-Carry Accumulation

The lower 8 bits perform the main addition between the current accumulator value and the spin-controlled coefficient.

```verilog
generate
    for(i = 0; i < 8; i = i + 1) begin: RCA_8b_ACCUMULATOR
        full_adder lower_full_adder(
            .a(S[i]),
            .b(J_xor[i]),
            .cin(c[i]),
            .sum(rca_sum[i]),
            .cout(c[i+1])
        );
    end
endgenerate
```

This part computes the lower 8 bits of:

$$
S + J\sigma
$$

---

### 4.3 Sign Extension

The coefficient `J` is 8-bit, but the accumulator `S` is 12-bit.

Therefore, the upper 4 bits are used for sign extension.

```verilog
generate
    for(i = 8; i < 12; i = i + 1) begin: RCA_4b_SIGN_EXTENSION
        full_adder upper_full_adder(
            .a(S[i]),
            .b(J_xor[7]),
            .cin(c[i]),
            .sum(rca_sum[i]),
            .cout(c[i+1])
        );
    end
endgenerate
```

The sign bit `J_xor[7]` is repeatedly used in the upper 4 bits.
This extends the sign of the 8-bit coefficient into the 12-bit accumulation range.

---

### 4.4 Accumulator Register Update

The next accumulator value is selected by:

```verilog
assign d_next = acc_clear ? 12'b0 : rca_sum;
assign reg_en = en | acc_clear;
```

This behavior can be summarized as:

$$
S_{\text{next}} =
\begin{cases}
0, & \text{if } acc_clear = 1 \
S + J\sigma, & \text{if } en = 1 \
S, & \text{if } en = 0
\end{cases}
$$

The accumulator register updates only when:

```verilog
reg_en = 1
```

This happens when either:

* `en = 1`
* `acc_clear = 1`

---

### 4.5 Sign Bit Output

The sign bit of the accumulated local field is directly assigned to `MSB_sign`.

```verilog
assign MSB_sign = S[11];
```

The spin update rule is:

$$
L_i > 0 \Rightarrow \sigma_i = +1
$$

$$
L_i < 0 \Rightarrow \sigma_i = -1
$$

Since the spin bit encoding is:

```text
1 = +1
0 = -1
```

the next spin value can be computed as:

```verilog
spin_update_value = ~MSB_sign;
```

The interpretation is:

| `MSB_sign` | Local Field Sign | Updated Spin Bit | Updated Spin Value |
| ---------: | ---------------- | ---------------: | -----------------: |
|        `0` | Positive         |              `1` |               `+1` |
|        `1` | Negative         |              `0` |               `-1` |

---

## 5. Submodules

### 5.1 `full_adder`

The `full_adder` module implements a 1-bit full adder.

```verilog
module full_adder(
    input wire a,
    input wire b,
    input wire cin,
    output wire sum,
    output wire cout
);
```

The logic equations are:

$$
sum = a \oplus b \oplus cin
$$

$$
cout = ab + cin(a \oplus b)
$$

The Verilog implementation is simple Full adder logic:

```verilog
assign sum = a ^ b ^ cin;
assign cout = (a & b) | cin & (a ^ b);
```

---

### 5.2 `d_ff`

The `d_ff` module implements a D flip-flop with active-low reset and enable.

```verilog
module d_ff(
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire d,
    output reg q
);
```

The operation is:

```verilog
always @(posedge clk) begin
    if(!rst_n) q <= 1'b0;
    else if(en) q <= d;
end
```

Therefore:

* If `rst_n = 0`, the output is reset to `0`.
* If `rst_n = 1` and `en = 1`, the input `d` is stored.
* If `rst_n = 1` and `en = 0`, the previous value is held.

---

## 6. Testbench: `tb_spin_operator.v`

### 6.1 Purpose

The testbench verifies whether the `spin_operator` correctly accumulates multiple Ising interaction terms.

The target spin is assumed to be:

$$
\sigma_5
$$

The neighboring spins and coefficients are:

| Direction |   Neighbor Spin | Spin Bit | Coefficient | Expected Contribution |
| --------- | --------------: | -------: | ----------: | --------------------: |
| North     | $\sigma_2 = +1$ |      `1` |        `+2` |                  `+2` |
| East      | $\sigma_6 = -1$ |      `0` |        `+3` |                  `-3` |
| South     | $\sigma_8 = -1$ |      `0` |        `-4` |                  `+4` |
| West      | $\sigma_4 = -1$ |      `0` |        `-5` |                  `+5` |

Therefore, the expected accumulated local field is:

$$
S = 2 - 3 + 4 + 5 = 8
$$

---

### 6.2 Testbench Interface Signals

| Signal      | Type   |  Width | Description                                    |
| ----------- | ------ | -----: | ---------------------------------------------- |
| `clk`       | `reg`  |  1-bit | Clock signal generated by the testbench.       |
| `rst_n`     | `reg`  |  1-bit | Reset signal connected to the DUT.             |
| `acc_clear` | `reg`  |  1-bit | Accumulator clear signal connected to the DUT. |
| `en`        | `reg`  |  1-bit | MAC enable signal connected to the DUT.        |
| `J`         | `reg`  |  8-bit | Coefficient input connected to the DUT.        |
| `spin`      | `reg`  |  1-bit | Spin input connected to the DUT.               |
| `S`         | `wire` | 12-bit | Accumulated output from the DUT.               |
| `MSB_sign`  | `wire` |  1-bit | Sign bit output from the DUT.                  |

---

### 6.3 Directional Test Variables

| Signal   | Description                    |
| -------- | ------------------------------ |
| `spin_N` | North spin value.              |
| `spin_E` | East spin value.               |
| `spin_S` | South spin value.              |
| `spin_W` | West spin value.               |
| `J_N`    | North interaction coefficient. |
| `J_E`    | East interaction coefficient.  |
| `J_S`    | South interaction coefficient. |
| `J_W`    | West interaction coefficient.  |

The testbench initializes these variables as paper's figure:  
<p align="center">
<img width="40%" alt="Image" src="https://github.com/user-attachments/assets/050f8b07-d6ff-4ada-8360-bdf05a59e782" />
</p>

```verilog
spin_N = 1'b1;
J_N    = 8'sd2;

spin_E = 1'b0;
J_E    = 8'sd3;

spin_S = 1'b0;
J_S    = -8'sd4;

spin_W = 1'b0;
J_W    = -8'sd5;
```

---

### 6.4 Clock Generation

The testbench uses a 64 MHz clock as paper has performed.

```verilog
localparam real CLK_PERIOD = 15.625;
```

The clock is generated by:

```verilog
initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2.0) clk = ~clk;
end
```

Therefore:

$$
T = 15.625 \text{ ns}
$$

$$
f = 64 \text{ MHz}
$$

---

### 6.5 Cycle-by-Cycle Monitor

The testbench includes a monitor that prints `S[11:0]` at every positive clock edge.

```verilog
always @(posedge clk) begin
    #1;

    cycle_count = cycle_count + 1;

    $display("[Cycle %0d | %0t ns] rst_n=%0b, acc_clear=%0b, en=%0b, J=%0d, spin=%0b, S[11:0]=%012b, S_signed=%0d, MSB_sign=%0b",
             cycle_count,
             $time,
             rst_n,
             acc_clear,
             en,
             $signed(J),
             spin,
             S,
             $signed(S),
             MSB_sign);
end
```

This monitor shows:

* Current cycle number
* Simulation time
* Reset state
* Accumulator clear signal
* Enable signal
* Current coefficient
* Current spin input
* Binary value of `S[11:0]`
* Signed decimal value of `S`
* Sign bit `MSB_sign`

The `#1` delay is used to print the updated value after the flip-flop output changes at the positive clock edge.

---

### 6.6 MAC Input Task

The task `apply_mac_input` applies one interaction term for one clock cycle.

```verilog
task apply_mac_input;
    input signed [7:0] coeff;
    input spin_value;
    input [8*8-1:0] direction_name;
    begin
        J         = coeff;
        spin      = spin_value;
        en        = 1'b1;
        acc_clear = 1'b0;

        @(posedge clk);
        #1;

        $display("[%0t ns] %0s: J = %0d, spin_bit = %0b, accumulated S = %0d, MSB_sign = %0b",
                 $time,
                 direction_name,
                 $signed(J),
                 spin,
                 $signed(S),
                 MSB_sign);
    end
endtask
```

This task performs the following sequence:

1. Assign the coefficient to `J`.
2. Assign the neighboring spin bit to `spin`.
3. Set `en = 1`.
4. Wait for one positive clock edge.
5. Print the accumulated result.

---

## 7. Testbench Operation Sequence

### 7.1 Initialization

The testbench first initializes all control and input signals.

```verilog
rst_n     = 1'b0;
acc_clear = 1'b0;
en        = 1'b0;
J         = 8'd0;
spin      = 1'b0;
```

---

### 7.2 Set Test Inputs

The directional spin values and coefficients are assigned.

```verilog
spin_N = 1'b1;
J_N    = 8'sd2;

spin_E = 1'b0;
J_E    = 8'sd3;

spin_S = 1'b0;
J_S    = -8'sd4;

spin_W = 1'b0;
J_W    = -8'sd5;
```

---

### 7.3 Reset DUT

The DUT is reset for two clock cycles.

```verilog
repeat (2) @(posedge clk);
rst_n = 1'b1;
```

During reset, the accumulator value becomes:

$$
S = 0
$$

---

### 7.4 Clear Accumulator

Before starting the MAC sequence, the accumulator is cleared.

```verilog
acc_clear = 1'b1;
en        = 1'b0;
@(posedge clk);
#1;
acc_clear = 1'b0;
```

This ensures that:

$$
S = 0
$$

before accumulating local interaction terms.

---

### 7.5 Sequential MAC Accumulation

The testbench applies four interaction terms sequentially.

```verilog
apply_mac_input(J_N, spin_N, "North");
apply_mac_input(J_E, spin_E, "East");
apply_mac_input(J_S, spin_S, "South");
apply_mac_input(J_W, spin_W, "West");
```

The accumulation sequence is:

$$
S_0 = 0
$$

$$
S_1 = S_0 + 2 = 2
$$

$$
S_2 = S_1 - 3 = -1
$$

$$
S_3 = S_2 + 4 = 3
$$

$$
S_4 = S_3 + 5 = 8
$$

Therefore, the expected final value is:

$$
S = 8
$$

---

### 7.6 Disable Accumulation

After applying all interaction terms, the enable signal is disabled.

```verilog
en = 1'b0;
```

This prevents unintended additional accumulation.

---

### 7.7 Check Final Result

The testbench checks whether the final accumulated result is equal to `8`.

```verilog
if ($signed(S) == 12'sd8)
    $display("TEST PASSED: Final S is correct.");
else
    $display("TEST FAILED: Expected S = 8, but got S = %0d", $signed(S));
```

If the result is correct, the testbench prints:

```text
TEST PASSED: Final S is correct.
```

---

### 7.8 Interpret Spin Update

The sign bit is used to determine the next spin value.

```verilog
if (MSB_sign == 1'b0)
    $display("Local field is positive -> sigma_5 updates to +1.");
else
    $display("Local field is negative -> sigma_5 updates to -1.");
```

Since the expected final value is:

$$
S = 8
$$

the local field is positive.

Therefore:

$$
\sigma_5 \rightarrow +1
$$

In bit encoding:

```text
updated spin bit = 1
```

---

## 8. Expected Console Output

A typical output includes cycle-by-cycle monitoring and final test result messages.

```text
===============================================
Test bench of spin operator
Target spin: sigma_5
Clock frequency: 64 MHz
Clock period   : 15.625 ns
===============================================

[Cycle 1 | ... ns] rst_n=0, acc_clear=0, en=0, J=0, spin=0, S[11:0]=000000000000, S_signed=0, MSB_sign=0
[Cycle 2 | ... ns] rst_n=0, acc_clear=0, en=0, J=0, spin=0, S[11:0]=000000000000, S_signed=0, MSB_sign=0

===============================================
Input sequence
North: sigma_2 = +1, J = +2 -> +2
East : sigma_6 = -1, J = +3 -> -3
South: sigma_8 = -1, J = -4 -> +4
West : sigma_4 = -1, J = -5 -> +5
Expected final S = 2 - 3 + 4 + 5 = 8
===============================================

TEST PASSED: Final S is correct.
Local field is positive -> sigma_5 updates to +1.
```

The exact simulation time may differ depending on the simulator formatting.

---

## 9. Why `en` Is Required

The `en` signal is required because the accumulator should update only when a valid MAC input is applied.

If `en` remains high for multiple cycles with the same `J` and `spin`, the same interaction term will be accumulated repeatedly.

For example, if:

```verilog
J = 8'sd2;
spin = 1'b1;
en = 1'b1;
```

and `en` stays high for several cycles, then:

$$
S = 0 \rightarrow 2 \rightarrow 4 \rightarrow 6 \rightarrow \cdots
$$

This is not the intended behavior.

Therefore:

* `en = 1` means one valid MAC operation is performed.
* `en = 0` means the accumulator holds its current value.

---

## 10. Why `acc_clear` Is Required

The `acc_clear` signal is required to start each local field calculation from zero.

Before calculating a new target spin's local field:

$$
S = 0
$$

must be guaranteed.

Without `acc_clear`, the previous accumulated local field could remain in the accumulator and corrupt the next computation.

---

## 11. Expected Final Result

The testbench is designed to produce:

$$
S = 8
$$

The final sign bit should be:

$$
MSB_sign = 0
$$

Therefore, the target spin should update to:

$$
\sigma_5 = +1
$$

In bit encoding:

```text
updated spin bit = 1
```

---

## 12. Notes

* This project is intended for simulation and educational understanding.
* The DUT is synthesizable, but the testbench is not synthesizable.
* The design does not use a conventional multiplier.
* Multiplication by the spin value is implemented using XOR and two's-complement arithmetic.
* The accumulator width is 12 bits to support a wider local field range than the 8-bit coefficient input.
* The sign bit `S[11]` is used to determine the next spin state.
* The spin encoding is `1 = +1` and `0 = -1`.
* The expected final test result is `S = 8`.
