/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Flex-Spin : A CMOS Ising Machine With 256 Flexible Spin Processing Elements With 8-b
// Coefficients for Solving Combinatorial Optimization Problems
// Yuqi Su , Member, IEEE, Tony Tae-Hyoung Kim , Senior Member, IEEE, and Bongjin Kim , Senior Member, IEEE
// This is not a offcial code of paper!

// Made by yechan LEE (논문 학습 및 이해를 위해 작성한 코드입니다.)
// Last update : 2026-05-22
// spin_PE_top.v 파일은 생성형 AI을 사용하지 않았습니다. (No AI was used for this code)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

module spin_PE_top (
    input  wire clk,
    input  wire rst_n,

    input  wire acc_clear,              // accumulation reset
    input  wire en,
    input  wire [7:0] J,

    input  wire i_sigma_N,
    input  wire i_sigma_E,
    input  wire i_sigma_S,
    input  wire i_sigma_W,

    input  wire R_H,
    input  wire R_V,

    input  wire [1:0] mx_mode_sel,       // mode_selection_mux -> Interaction(00), Local bias(01), Random-H(10), Random-V(11)
    input  wire [1:0] mx_input_sel,      // spin_in_selection_mux -> North(00), East(01), South(10), West(11)
    input  wire [1:0] mx_spin_sel,       // spin_reg_selection_mux -> sigma_1(00), sigma_2(01), sigma_3(10), sigma_4(11)
    input  wire       mx_bypass_sel,     // bypass_mux -> spin(0), bypass(1)
    input  wire [1:0] dmx_output_sel,    // output_spin_demux -> North(00), East(01), South(10), West(11)
    input  wire [1:0] dmx_spin_sel,      // spin_reg_demux -> sigma_1(00), sigma_2(01), sigma_3(10), sigma_4(11)

    input  wire update_en,               // hold current spin values(0), update selected spin register(1)

    output wire o_sigma_N,
    output wire o_sigma_E,
    output wire o_sigma_S,
    output wire o_sigma_W,

    output wire [11:0] S,
    output wire MSB_sign
);

    wire mac_spin_in;
    wire spin_update_value;

    // MAC result negative -> MSB_sign = 1 -> spin_update_value = 0(down)
    // MAC result positive -> MSB_sign = 0 -> spin_update_value = 1
    assign spin_update_value = ~MSB_sign;

    four_spin_registers_IO u_four_spin_registers_IO (
        .clk(clk),
        .rst_n(rst_n),

        .i_sigma_N(i_sigma_N),
        .i_sigma_E(i_sigma_E),
        .i_sigma_S(i_sigma_S),
        .i_sigma_W(i_sigma_W),

        .R_H(R_H),
        .R_V(R_V),

        .mx_mode_sel(mx_mode_sel),
        .mx_input_sel(mx_input_sel),
        .mx_spin_sel(mx_spin_sel),
        .mx_bypass_sel(mx_bypass_sel),
        .dmx_output_sel(dmx_output_sel),
        .dmx_spin_sel(dmx_spin_sel),

        .update_en(update_en),
        .spin_update_value(spin_update_value),

        .mac_spin_in(mac_spin_in),

        .o_sigma_N(o_sigma_N),
        .o_sigma_E(o_sigma_E),
        .o_sigma_S(o_sigma_S),
        .o_sigma_W(o_sigma_W)
    );

    spin_operator u_spin_operator (
        .clk(clk),
        .rst_n(rst_n),
        .acc_clear(acc_clear),
        .en(en),
        .J(J),
        .spin(mac_spin_in),
        .S(S),
        .MSB_sign(MSB_sign)
    );

endmodule

module spin_operator(
    input wire clk,
    input wire rst_n,        // d_ff reset
    input wire acc_clear,    // accumulation reset
    input wire en,
    input wire [7:0] J,
    input wire spin,
    output wire [11:0] S,
    output wire MSB_sign
);

    wire spin_neg;
    wire [7:0] J_xor;
    wire [12:0] c;
    wire [11:0] rca_sum;
    wire [11:0] d_next;
    wire reg_en;

    assign spin_neg = ~spin;            // if spin == 0, spin_neg == 1 and it becomes input of first full_adder so that J becomes -J
                                        // if spin == 1, spin_neg == 0 and J remains with no sign conversion
    assign c[0] = spin_neg;
    assign J_xor = J ^ {8{spin_neg}};   // XOR based multiplier

    genvar i;

    // 8-b Ripple Carry Adder with XOR based multiplier
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

    // 4-b Ripple Carry Adder for sign extension
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

    assign d_next = acc_clear ? 12'b0 : rca_sum;

    assign reg_en = en | acc_clear;     // D F/F is activated when en == 1 or acc_clear == 1

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

    assign MSB_sign = S[11];

endmodule

module four_spin_registers_IO (

    //Input
    input  wire clk,
    input  wire rst_n,

    input  wire i_sigma_N,
    input  wire i_sigma_E,
    input  wire i_sigma_S,
    input  wire i_sigma_W,              // Spin inputs from neighboring PEs

    input  wire R_H,
    input  wire R_V,                    // Random mode for annealing

    // Control Signal
    input  wire [1:0] mx_mode_sel,      // mode_selection_mux -> Interaction(00), Local bias(01), Random-H(10), Random-V(11)

    input  wire [1:0] mx_input_sel,     // spin_in_selection_mux -> North(00), East(01), South(10), West(11)

    input  wire [1:0] mx_spin_sel,      // spin_reg_selection_mux -> sigma_1(00), sigma_2(01), sigma_3(10), sigma_4(11)

    input  wire mx_bypass_sel,          // bypass_mux -> spin(0),bypass(1)

    input  wire [1:0] dmx_output_sel,   // output_spin_demux -> North(00), East(01), South(10), West(11)

    input  wire [1:0] dmx_spin_sel,     // spin_reg_demux -> sigma_1(00), sigma_2(01), sigma_3(10), sigma_4(11)

    input  wire update_en,              // hold current spin values(0), update selected spin register(1)
    input  wire spin_update_value,      // MAC result negative -> MSB_sign = 1 -> spin_update_value = 0(down)
                                        // MAC result positive -> MSB_sign = 0 -> spin_update_value = 1
    //Output
    output wire mac_spin_in,

    output wire o_sigma_N,
    output wire o_sigma_E,
    output wire o_sigma_S,
    output wire o_sigma_W
);
    wire sigma_1;
    wire sigma_2;
    wire sigma_3;
    wire sigma_4;

    wire selected_incoming_spin;
    wire selected_spin_reg;
    wire spin_out;

    wire reg_en_1;
    wire reg_en_2;
    wire reg_en_3;
    wire reg_en_4;

    // No.1
    mux4_1 mode_selection_mux (
        .in0(selected_incoming_spin),   // interaction mode
        .in1(1'b1),                     // local bias mode
        .in2(R_H),                      // random-H mode
        .in3(R_V),                      // random-V mode
        .sel(mx_mode_sel),
        .out(mac_spin_in)
    );

    // No.2
    mux4_1 spin_in_selection_mux (
        .in0(i_sigma_N),
        .in1(i_sigma_E),
        .in2(i_sigma_S),
        .in3(i_sigma_W),
        .sel(mx_input_sel),
        .out(selected_incoming_spin)
    );

    // No.3
    mux4_1 spin_reg_selection_mux (
        .in0(sigma_1),
        .in1(sigma_2),
        .in2(sigma_3),
        .in3(sigma_4),
        .sel(mx_spin_sel),
        .out(selected_spin_reg)
    );

    // No.4
    mux2_1 bypass_mux (
        .in0(selected_spin_reg),
        .in1(selected_incoming_spin),
        .sel(mx_bypass_sel),
        .out(spin_out)
    );

    // No.5
    demux1_4 output_spin_demux (
        .in(spin_out),
        .sel(dmx_output_sel),
        .out0(o_sigma_N),
        .out1(o_sigma_E),
        .out2(o_sigma_S),
        .out3(o_sigma_W)
    );

    // No.6
    demux1_4 spin_reg_demux (
        .in(update_en),
        .sel(dmx_spin_sel),
        .out0(reg_en_1),
        .out1(reg_en_2),
        .out2(reg_en_3),
        .out3(reg_en_4)
    );

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

endmodule

module mux2_1 (
    input  wire in0,
    input  wire in1,
    input  wire sel,
    output wire out
);

    assign out = sel ? in1 : in0;

endmodule

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

endmodule

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

endmodule
