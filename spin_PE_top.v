/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Flex-Spin : A CMOS Ising Machine With 256 Flexible Spin Processing Elements With 8-b
// Coefficients for Solving Combinatorial Optimization Problems
// Yuqi Su , Member, IEEE, Tony Tae-Hyoung Kim , Senior Member, IEEE, and Bongjin Kim , Senior Member, IEEE
// This is not a offcial code of paper

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
