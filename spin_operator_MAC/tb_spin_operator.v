/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Flex-Spin : A CMOS Ising Machine With 256 Flexible Spin Processing Elements With 8-b
// Coefficients for Solving Combinatorial Optimization Problems
// Yuqi Su , Member, IEEE, Tony Tae-Hyoung Kim , Senior Member, IEEE, and Bongjin Kim , Senior Member, IEEE
// This is not a offcial code of paper!

// Made by yechan LEE (논문 학습 및 이해를 위해 작성한 코드입니다.)
// Last update : 2026-05-23
// spin_PE_top.v 파일은 생성형 AI을 사용하여 작성되었습니다. (Gen AI was used for this code)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_spin_operator;

    // 64 MHz clock
    // T = 1 / 64 MHz = 15.625 ns
    localparam real CLK_PERIOD = 15.625;

    reg clk;
    reg rst_n;
    reg acc_clear;
    reg en;

    reg [7:0] J;
    reg spin;

    wire [11:0] S;
    wire MSB_sign;

    // Directional spin values
    reg spin_N;
    reg spin_E;
    reg spin_S;
    reg spin_W;

    // Directional coefficients
    reg signed [7:0] J_N;
    reg signed [7:0] J_E;
    reg signed [7:0] J_S;
    reg signed [7:0] J_W;

    // DUT instance
    spin_operator dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .acc_clear (acc_clear),
        .en        (en),
        .J         (J),
        .spin      (spin),
        .S         (S),
        .MSB_sign  (MSB_sign)
    );

    // 64 MHz clock generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2.0) clk = ~clk;
    end

    // Apply one MAC input per clock cycle
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

    initial begin
        // Initial values
        rst_n     = 1'b0;
        acc_clear = 1'b0;
        en        = 1'b0;
        J         = 8'd0;
        spin      = 1'b0;

        // Directional input settings based on the figure
        // spin = 1 -> +1
        // spin = 0 -> -1

        // North: sigma_2 = +1, J_25 = +2
        spin_N = 1'b1;
        J_N    = 8'sd2;

        // East: sigma_6 = -1, J_56 = +3
        spin_E = 1'b0;
        J_E    = 8'sd3;

        // South: sigma_8 = -1, J_58 = -4
        spin_S = 1'b0;
        J_S    = -8'sd4;

        // West: sigma_4 = -1, J_45 = -5
        spin_W = 1'b0;
        J_W    = -8'sd5;

        $display("===============================================");
        $display("Spin Operator MAC Testbench");
        $display("Target spin: sigma_5");
        $display("Clock frequency: 64 MHz");
        $display("Clock period   : 15.625 ns");
        $display("===============================================");

        // Reset
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // Clear accumulator
        acc_clear = 1'b1;
        en        = 1'b0;
        @(posedge clk);
        #1;

        $display("[%0t ns] Accumulator cleared: S = %0d", $time, $signed(S));

        acc_clear = 1'b0;

        $display("===============================================");
        $display("Input sequence based on the figure");
        $display("North: sigma_2 = +1, J = +2 -> +2");
        $display("East : sigma_6 = -1, J = +3 -> -3");
        $display("South: sigma_8 = -1, J = -4 -> +4");
        $display("West : sigma_4 = -1, J = -5 -> +5");
        $display("Expected final S = 2 - 3 + 4 + 5 = 8");
        $display("===============================================");

        // Sequential MAC accumulation
        apply_mac_input(J_N, spin_N, "North");
        apply_mac_input(J_E, spin_E, "East");
        apply_mac_input(J_S, spin_S, "South");
        apply_mac_input(J_W, spin_W, "West");

        // Disable accumulation
        en = 1'b0;

        @(posedge clk);
        #1;

        $display("===============================================");
        $display("Final accumulated result S = %0d", $signed(S));
        $display("Final MSB_sign = %0b", MSB_sign);

        if ($signed(S) == 12'sd8)
            $display("TEST PASSED: Final S is correct.");
        else
            $display("TEST FAILED: Expected S = 8, but got S = %0d", $signed(S));

        if (MSB_sign == 1'b0)
            $display("Local field is positive -> sigma_5 updates to +1.");
        else
            $display("Local field is negative -> sigma_5 updates to -1.");

        $display("===============================================");

        #50;
        $finish;
    end

endmodule
