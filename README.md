# Flex Spin

본 코드는 Spin operator 그리고 4x Spin Registers의 Verilog DUT와 Testbench 코드입니다.

코드는 아래 논문을 참고해 작성되었으며, 학습 용도이기에 저자가 혹은 논문에서 사용된 실제 코드가 아님을 밝힙니다.

**[’24 JSSC] Flex-Spin: A CMOS Ising Machine With 256 Flexible Spin Processing Elements With 8-b Coefficients for Solving Combinatorial Optimization Problems**

### 1. File Overview

본 repository는 아래와 같이 구성되어 있습니다.

| **File** | **Description** |
| --- | --- |
| `flex_spin_top.v` | Top unit DUT for flex spin operation |
| `spin_operator.v` | MAC unit for spin and coefficient values |
| `four_spin_registers.v` | Spin register unit that contains MUX and DEMUX for spin I/O |
| `tb_ising_32x8x4.v` | Testbench file |
| `build.sh` | Shell build file to run code at linux OS |
| `Flexspin_visualization.py` | Python file for visualizing Ising Energy map |
| `Ising_Hamiltonian.py` | Python file for visualizing Ising Hamiltonian convergence |

Verilog 코드 Run을 통해 생성된 txt 파일을 python 파일과 동일 경로에 두면 됩니다.

### 2. Design Goal

`spin_operator.v`  파일은 Flex Spin Ising machine에서 local field accumulation을 수행합니다. 입력으로 들어오는 Spin value와 SRAM에 저장되어 있던 8-bit coeffcient를 곱해 local field를 MAC 연산 하는 것이 목적입니다. 해당 유닛의 구조는 아래와 같습니다.
<p align="center">
<img width="300" alt="Image" src="https://github.com/user-attachments/assets/3603c557-3080-4bc3-b1cc-5ac9db015355" />
</p> 

`four_spin_registers.v` 파일은 동서남북 4개의 Spin들의 값을 입력 받아 MAC unit으로 전달해주는 역할을 합니다. 이때 Flex Spin에서 구현된 reconfigurable성을 위해 Bypass 등을 수행할 수 있는 MUX가 존재합니다. 해당 유닛의 구조는 아래와 같습니다.
<p align="center">
<img width="400" alt="Image" src="https://github.com/user-attachments/assets/62c3ce04-82fc-4e6f-9f4e-eb6659ce5822" />
</p> 

`flex_spin_top.v` 파일은 `spin_operator.v` 와 `four_spin_registers.v` 을 이용한 DUT TOP 모듈입니다. 해당 TOP 유닛의 구조는 아래와 같습니다.

<p align="center">
<img width="600" alt="image" src="https://github.com/user-attachments/assets/38c48e4f-a041-4210-bbc6-e91fe42f5477" />
</p> 

### 3. File #1 : spin_operator.v

#### 3.1 Core Algorithm

`spin_operator.v`  파일은 KPI인 Ising Hamiltonian의 Effective Local Filed를 각 Spin에 대해 계산하는 역할을 수행한다. 수행되어야 하는 알고리즘은 아래와 같다.
<p align="center">
S←S+J⋅σ
</p>

- S : 12-bit accumulated Local field
- J : 8-bit signed coefficient
- σ : Spin value

Ising Hamilonian에서는 effective local field의 부호에 따라 update의 대상이 되는 Spin의 값이 결정된다.

<p align="center">
<img width="300" alt="image" src="https://github.com/user-attachments/assets/ec5d5431-523b-466b-b8c4-a976a926eb03" />
</p> 

Ising Hamiltonian으로부터 특정 Spin i에 대해 update를 수행한다고 할 때, 해당되는 Hamiltonian은 아래와 같다.

<p align="center">
<img width="250" alt="image" src="https://github.com/user-attachments/assets/2a855850-6843-46eb-a247-31d1788243f6" />
</p> 

괄호 안의 값을 Effective Local Field라 하며 해당 부분이 양수인 경우 σi는 양수(Spin up), 음수인 경우 σi는 음수(Spin down)으로 update되어야 한다.

**→ Hamiltonian을 줄이기 위해 update 대상 spin의 부호는 Effective Local Field의 부호와 같다.**

여기서 Spin 값은 1비트 encoding을 통해 up일 때는 +1, down일 때는 0으로 매핑된다.  


#### 3.2 MAC operation

**Background: XNOR based 2’s compliment operation and Accumulation**

디지털 논리회로에서 음수를  표현할 때는 2의 보수의 방법을 이용해서 표현합니다. 이때 음수로 표현되어야 하는 수는 모든 비트의 부호를 반전한 뒤, 1을 더해 표현하면 됩니다. 예를 들어 십진수 +3를 -3으로 바꾸려면,

(1) 십진수의 4비트 표현 : +3 → 0011

(2) 모든 비트 부호 반전 : 0101 → 1100

(3) 1을 더해 음수 표현 : 1010 +0001 = 1101

XNOR 연산에서는 1과의 피연산에서는 부호 유지, 0과의 피연산에서는 부호 반전이 된다.

Spin 값과 연결해보면,

- XNOR with Spin up(+1) and J[7:0] → J[7:0]
- XNOR with Spin down(0) and J[7:0] → -J[7:0]

하나의 J[7:0]과 Spin에 대한 multiply 연산이 완료되었다면 이를 Register에 저장하고 다음 CLK에서 들어오는 J의 값과 accumulation 한다. 이때 논문에서는 Ripple Carry Adder 형태로 가산기를 구현했다.

(1) Spin 값 입력 받음

(2) +1인 경우 부호 유지 (Jσ = J), 0인 경우 부호 반전 (Jσ = -J)

(3) 계산된 J 값을 레지스터에 저장 

(4) 다음 CLK에서 (1)~(2) 수행

(5) Full Adder에서 Accumulation 수행

이후 4-Bit Sign extenstion을 수행해서 MAC 과정에서 발생할 수 있는 overflow를 방지한다. Interaction coefficient J가 8-bit signed로 정의되므로 -128~+127까지 저장될 수 있고, 4-bit sign extension을 수행하면 12-bit까지 accumulation이 가능하다.

이를 S[11:0]이라 정의하고 이때 표현 가능한 범위는 -2048~+2047이다. S의 MSB는 부호를 나타내는데, 0인 경우 양수, 1인 경우 음수를 나타낸다.

#### 3.3 Spin Operator Architecture - Main module

<p align="center">
<img width="300" alt="Image" src="https://github.com/user-attachments/assets/3603c557-3080-4bc3-b1cc-5ac9db015355" />
</p> 

Input 신호는 아래와 같다.

| **Signal** | **Width** | **Description** |
| --- | --- | --- |
| `clk` | 1-bit | Clock signal. |
| `rst_n` | 1-bit | Active-low synchronous reset for the accumulator registers. |
| `acc_clear` | 1-bit | Clears the accumulated value S to zero. |
| `en` | 1-bit | Enables one MAC accumulation operation. |
| `J` | 8-bit | Signed interaction coefficient. |
| `spin` | 1-bit | Input spin value. |

Output 신호는 아래와 같다.

| **Signal** | **Width** | **Description** |
| --- | --- | --- |
| `S` | 12-bit | Accumulated local field value. |
| `MSB_sign` | 1-bit | Sign bit of S, equal to S[11] |

Internal 신호는 아래와 같다.

| **Signal** | **Width** | **Description** |
| --- | --- | --- |
| `spin_neg` | 1-bit | Inverted spin bit. Used to decide whether J should be converted to -J |
| `J_xnor` | 8-bit | XNOR-converted coefficient |
| `c` | 13-bit | Carry chain for the ripple-carry adder. |
| `rca_sum` | 12-bit | Output of the 12-bit ripple-carry accumulator. |
| `d_next` | 12-bit | Next value to be stored in the accumulator registers. |
| `reg_en` | 1-bit | Register enable signal. Activated when `en` or `acc_clear` is high. |

인버터를 거친 `spin_neg` 및 carry, XNOR을 아래와 같이 assign 한다.

```verilog
    assign spin_neg = ~spin;            // if spin == 0, spin_neg == 1 and c[0] becomes 1 so that ~J + 1 becomes -J
                                        // if spin == 1, spin_neg == 0 and J remains with no sign conversion
    assign c[0] = spin_neg;
    assign J_xnor = ~(J ^ {8{spin}});   // XNOR based multiplier
```

S의 하위 8-bit는 Ripple Carry Adder로 구현된다.

```verilog
   genvar i;
    
    // 8-b Ripple Carry Adder with XNOR based multiplier
    generate
        for(i = 0; i < 8; i = i + 1) begin: RCA_8b_ACCUMULATOR
            full_adder lower_full_adder(
                .a(S[i]),
                .b(J_xnor[i]),
                .cin(c[i]),
                .sum(rca_sum[i]),
                .cout(c[i+1])
            );
        end
    endgenerate
```

S의 상위 4-bit는 마찬가지로 Ripple Carry Adder로 구현되나, J_xnor의 값은 sign extension이므로 J_xnor[7]로 동일하다.

```verilog
    // 4-b Ripple Carry Adder for sign extension
    generate
        for(i = 8; i < 12; i = i + 1) begin: RCA_4b_SIGN_EXTENSION
            full_adder upper_full_adder(
                .a(S[i]),
                .b(J_xnor[7]),
                .cin(c[i]),
                .sum(rca_sum[i]),
                .cout(c[i+1])
            );
        end
    endgenerate
```

`rca_sum` 은 Ripple Carry Adder의 출력으로, J와 σ의 곱연산을 수행한 뒤 Register에 저장되어야 한다. 한번의 Effective Local Field에 대해 MAC 연산이 수행되면 이후 `acc_clear` 에 의해 Register에 저장되는 값은 초기화 되어야 하므로 아래와 같은 논리식으로 작성될 수 있다.

```verilog
assign d_next = acc_clear ? 12'b0 : rca_sum;
assign reg_en = en | acc_clear;
```

`d_next` 는 `acc_clear`  가 1이면 0으로 초기화 되고, 그 외의 경우 `rca_sum` 과 연결되어 Register에 입력된다. Register는 `en`  신호 또는 `acc_clear` 신호를 받았을 경우에만 작동한다.

```verilog
    // D F/F generation
    generate
        for(i = 0; i < 12; i = i + 1) begin: REG_ACC
            d_ff d_ff_acc (
                .clk(clk),
                .rst_n(rst_n),
                .en(reg_en),            // if en(en), D F/F will not work for reseting it's value when acc_clear == 1
                .d(d_next[i]),
                .q(S[i])
            );
        end
    endgenerate
```

S의 MSB의 값은 부호를 나타내므로, `MSB_sign` 에 이를 할당하여 표현한다.

```verilog
assign MSB_sign = S[11];
```

#### 3.4 Spin Operator Architecture - Sub module

Full Adder 및 D Flip Flop의 기본 구조이다.

```verilog
module full_adder(
    input wire a,
    input wire b,
    input wire cin,
    output wire sum,
    output wire cout
);

    assign sum = a ^ b ^ cin;
    assign cout = (a & b) | (cin & (a ^ b));

endmodule

module d_ff(
    input wire clk,
    input wire rst_n,   // synchronous reset is required after one local term's calculation is done
    input wire en,      // MAC : Multiply -> Accumulate, enable signal is required for distinguishing each operation
    input wire d,
    output reg q
);

    always @(posedge clk) begin
        if(!rst_n) q <= 1'b0;
        else if(en) q <= d;
    end
```

### 4. File #2 : four_spin_registers.v

#### 4.1 Core Architecture

`four_spin_registers.v`  파일은 Spin과 Interaction 하는 또 다른 Spin들을 입력 받고 계산되어 Update 되는 Spin 값을 출력하는 과정을 수행한다. 총 4개의 MUX와 2개의 DEMUX로 구성되어 있으며 전체 Architecture는 아래와 같다.

<p align="center">
<img width="500" alt="image" src="https://github.com/user-attachments/assets/d17a6d9b-127e-4f36-8530-03625f6b8b75" />
</p>

#### 4.2 MUX and DEMUX operations

입력 신호는 아래와 같다.

| Signal | Width | Description |
| --- | --- | --- |
| `clk` | 1-bit | Clock signal for the four spin registers. |
| `rst_n` | 1-bit | Active-low reset signal for the spin registers. |
| `i_sigma_N,E,S,W` | 1-bit | Incoming spin value from the North, East, South, West neighboring PE. |
| `R_H` | 1-bit | Random spin input used for the horizontal annealing mode. |
| `R_V` | 1-bit | Random spin input used for the vertical annealing mode. |
| `mx_mode_sel` | 2-bit | Selects the MAC spin-input mode: interaction, local bias, Random-H, or Random-V. |
| `mx_input_sel` | 2-bit | Selects one incoming spin among North, East, South, and West. |
| `mx_spin_sel` | 2-bit | Selects one of the four internal spin registers for output routing. |
| `mx_bypass_sel` | 1-bit | Selects either an internal spin register or the incoming spin bypass path. |
| `dmx_output_sel` | 2-bit | Selects the direction to which `spin_out` is routed. |
| `dmx_spin_sel` | 2-bit | Selects one of the four spin registers to be updated. |
| `update_en` | 1-bit | Enables the update of the selected spin register. |
| `spin_update_value` | 1-bit | New spin value generated from the MAC result sign. |

출력 신호는 아래와 같다.

| Signal | Width | Description |
| --- | --- | --- |
| `mac_spin_in` | 1-bit | Selected spin value delivered to the spin operator MAC input. |
| `o_sigma_N,E,S,W` | 1-bit | Spin output routed toward the North, East, South, West neighboring PE. |

내부 신호는 아래와 같다.

| Signal | Width | Description |
| --- | --- | --- |
| `sigma_1,2,3,4` | 1-bit | Stored spin value in the 1 ~ 4 internal spin register. |
| `selected_incoming_spin` | 1-bit | Neighboring spin selected by `spin_in_selection_mux`. |
| `selected_spin_reg` | 1-bit | Internal spin-register value selected by `spin_reg_selection_mux`. |
| `spin_out` | 1-bit | Output of the bypass MUX, routed to one neighboring direction. |
| `reg_en_1,2,3,4` | 1-bit | Write-enable signal for `sigma_1 ~ 4` |

각 MUX 및 DEMUX의 Control Signal과 이에 대한 할당은 아래와 같다.

| **Type** | **No** | **Name** | **Control Signal** | **Description** |
| --- | --- | --- | --- | --- |
| MUX | 1 | mode_selection | mx_mode_sel [1:0] | Interaction(00), Local bias(01), Random-H(10), Random-V(11) |
|  | 2 | spin_in_selection | mx_input_sel [1:0] | North(00), East(01), South(10), West(11) |
|  | 3 | spin_reg_selection | mx_spin_sel [1:0] | sigma_1(00), sigma_2(01), sigma_3(10), sigma_4(11) |
|  | 4 | bypass | mx_bypass_sel | spin(0), bypass(1) |
| DEMUX | 5 | output_spin | dmx_output_sel[1:0] | North(00), East(01), South(10), West(11) |
|  | 6 | spin_reg | dmx_spin_sel[1:0] | sigma_1(00), sigma_2(01), sigma_3(10), sigma_4(11) |

**①번 MUX**는 Effective Local Field를 계산할 때 4가지의 동작 모드 중 하나를 선택한다. 이 때,`R_H` 와 `R_V` 는 추후 Annealing Weight와 곱해져서 Local Field에 Hamiltonian이 빠지지 않도록 하는 역할을 수행한다.

```verilog
    // No.1
    mux4_1 mode_selection_mux (
        .in0(selected_incoming_spin),   // interaction mode : spin interaction
        .in1(1'b1),                     // local bias mode : adding value h
        .in2(R_H),                      // random-H mode : Horizontal Random annealing
        .in3(R_V),                      // random-V mode : Vertical Random Annealing
        .sel(mx_mode_sel),
        .out(mac_spin_in)
    );
```

**②번 MUX**는 들어오는 4가지 방향의 Spin 중 Interaction 할 Spin을 선택한다.

```verilog
    // No.2
    mux4_1 spin_in_selection_mux (
        .in0(i_sigma_N),
        .in1(i_sigma_E),
        .in2(i_sigma_S),
        .in3(i_sigma_W),
        .sel(mx_input_sel),
        .out(selected_incoming_spin)
    );

```

**③번 MUX**는 4개의 저장된 Spin Register 중 특정 Register을 선택하여 update된 Spin을 출력하거나 Bypass가 가능한 ④번 MUX로 보내는 역할을 한다. 4개의 Spin Register들을 배치하면서 전체 시스템의 Logical Spin의 수를 4배 증가 시킬 수 있다. (256 Spin PE X 4 Spin State / PE → Total 1024 Spins)

```verilog
    // No.3
    mux4_1 spin_reg_selection_mux (
        .in0(sigma_1),
        .in1(sigma_2),
        .in2(sigma_3),
        .in3(sigma_4),
        .sel(mx_spin_sel),
        .out(selected_spin_reg)
    );
```

**④번 MUX**는 Bypass 동작 혹은 Spin을 출력하는 동작을 수행한다. Flex-Spin을 위해 각 Spin이 인접한 N,E,S,W 이외에도 멀리 떨어져 있는 Spin과 Interaction 할 수 있도록 Bypass 동작을 가능하게 한다.

```verilog
    // No.4
    mux2_1 bypass_mux (
        .in0(selected_spin_reg),
        .in1(selected_incoming_spin),
        .sel(mx_bypass_sel),
        .out(spin_out)
    );
```

**⑤번 DEMUX**는 Update된 Spin 값을 저장할 Register을 선택한다.

```verilog
    // No.5
    demux1_4 output_spin_demux (
        .in(spin_out),
        .sel(dmx_output_sel),
        .out0(o_sigma_N),
        .out1(o_sigma_E),
        .out2(o_sigma_S),
        .out3(o_sigma_W)
    );
```

**⑥번 DEMUX**는 Bypass 혹은 Update된 Spin 값을 출력으로 보낼 Spin 방향을 선택한다.

```verilog
    // No.6
    demux1_4 spin_reg_demux (
        .in(update_en),
        .sel(dmx_spin_sel),
        .out0(reg_en_1),
        .out1(reg_en_2),
        .out2(reg_en_3),
        .out3(reg_en_4)
    );
```

4개의 Register와 2:1 MUX, 4:1 DEMUX, 1:4 DEMUX Submodule은 아래와 같이 구현한다.

**4x Registers**

```verilog
    // 4x Register
    d_ff spin_reg_1 (
        .clk(clk),
        .rst_n(rst_n),
        .en(reg_en_1),
        .d(spin_update_value),
        .q(sigma_1)
    );

    d_ff spin_reg_2 (
        .clk(clk),
        .rst_n(rst_n),
        .en(reg_en_2),
        .d(spin_update_value),
        .q(sigma_2)
    );

    d_ff spin_reg_3 (
        .clk(clk),
        .rst_n(rst_n),
        .en(reg_en_3),
        .d(spin_update_value),
        .q(sigma_3)
    );

    d_ff spin_reg_4 (
        .clk(clk),
        .rst_n(rst_n),
        .en(reg_en_4),
        .d(spin_update_value),
        .q(sigma_4)
    );
```

**MUXs and DEMUX**

```verilog
module mux4_1 (
    input  wire in0,
    input  wire in1,
    input  wire in2,
    input  wire in3,
    input  wire [1:0] sel,
    output reg  out
);

    always @(*) begin
        case (sel)
            2'b00: out = in0;
            2'b01: out = in1;
            2'b10: out = in2;
            2'b11: out = in3;
            default: out = 1'b0;
        endcase
    end

endmodule

module demux1_4 (
    input  wire       in,
    input  wire [1:0] sel,
    output reg        out0,
    output reg        out1,
    output reg        out2,
    output reg        out3
);

    always @(*) begin
        out0 = 1'b0;
        out1 = 1'b0;
        out2 = 1'b0;
        out3 = 1'b0;                   // To prevent latches

        case (sel)
            2'b00: out0 = in;
            2'b01: out1 = in;
            2'b10: out2 = in;
            2'b11: out3 = in;
            default: begin
                out0 = 1'b0;
                out1 = 1'b0;
                out2 = 1'b0;
                out3 = 1'b0;
            end
        endcase
    end
```

### 5. File #3 : flex_spin_top.v

`flex_spin_top.v` 파일은 `spin_operator.v` 와 `four_spin_registers.v` 를 instance 한 TOP DUT 모듈이며, 각 두 개의 파일에 있는 모듈들의 연결을 수행했습니다. S의 최상위 비트를 반전하는 것이 Ising Hamiltonian을 낮추는 방향으로 작용하므로, 아래 할당이 추가되었습니다.

```verilog
assign spin_update_value = ~MSB_sign;
```

### 6. File #4 : tb_flex_spin.v

`tb_flex_spin.v` 파일은 논문에서 사용된 64Mhz CLK을 생성하고 120번의 Sweep 동안 Ising Model을 updating 하는 testbench 파일입니다. 해당 testbench 코드는 생성형 AI를 이용하였으며, 실제 시뮬레이션으로 검증하였음을 밝힙니다.

Github에 업로드 된 기준으로는 Random Negative Coefficient를 가져 결과가 Checkerboard 형태의 Ising Map로 나오게 되어있습니다. 사용자는 Random Positive 또는 사전에 정의 된 J 값을 생성하는 코드를 추가하여 Map 결과를 자유롭게 변경할 수 있습니다.

초기 annealing weight는 127로 설정되었고, exponential하게 감소되는 형태입니다.

1, 10, 20, 30, 60, 90, 120 Sweep에서 Ising Map을 추후 python으로 시각화 할 수 있도록 txt 파일로 저장 할 수 있는 task문을 사용합니다.

### 7. Simulated Result with visualization (Python code)

아래 그림은 Ising Map으로, Annealing 과정을 수행했을 때와 지수적으로 온도를 낮춰 Annealing 과정을 수행했을 때의 결과를 비교합니다.

<img width="1587" height="473" alt="image" src="https://github.com/user-attachments/assets/26995ed9-f622-45ac-b798-79b15c600cae" />
<img width="989" height="590" alt="image" src="https://github.com/user-attachments/assets/e8718641-c941-4d5b-abad-a8f0d1c5f950" />


실제로 Ising Hamiltonian을 보게 되면, Annealing을 수행하지 않을 경우 local minima에 갇히게 되어 Annealing을 수행했을 때 보다 더 높은 Hamiltonian을 가지는 것을 알 수 있습니다.

시각화에 사용된 python 코드는 각각 아래와 같습니다. Google Colab 환경에서 작동되기 위해 Drive Mount 관련 코드가 사용되었으나 Local PC의 Python에서 사용을 원할 경우 적절히 변경 가능합니다.

Verilog에서 출력된 txt 파일을  python 코드인 `Flexspin_visualization.py`및`Ising_Hamiltonian.py`와 동일한 파일 경로에 저장하고 실행 바랍니다.
