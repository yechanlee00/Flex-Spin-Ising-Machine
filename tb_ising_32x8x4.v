/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Flex-Spin : A CMOS Ising Machine With 256 Flexible Spin Processing Elements With 8-b
// Coefficients for Solving Combinatorial Optimization Problems
// Yuqi Su , Member, IEEE, Tony Tae-Hyoung Kim , Senior Member, IEEE, and Bongjin Kim , Senior Member, IEEE
// This is not a offcial code of paper
//
// Made by yechan LEE (논문 학습 및 이해를 위해 작성한 코드입니다.)
// tb_ising_32x8x4.v 파일은 생성형 AI를 이용해 작성 후 검증하였습니다.
// 32 x 8 PE array, 4 spin registers per PE, total 1024 logical spins
//
// Evaluation order:
// 1. Without annealing
// 2. Reset and restore the same initial spin state
// 3. With exponential annealing
/////////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_ising_32x8x4;

    localparam real CLK_PERIOD = 15.625;    // 64 MHz

    localparam integer N_PE_ROW       = 32;
    localparam integer N_PE_COL       = 8;
    localparam integer N_SPIN_PER_PE  = 4;
    localparam integer N_PE           = N_PE_ROW * N_PE_COL;
    localparam integer N_TOTAL_SPIN   = N_PE * N_SPIN_PER_PE;
    localparam integer N_LOGICAL_ROW  = N_PE_ROW;
    localparam integer N_LOGICAL_COL  = N_PE_COL * N_SPIN_PER_PE;
    localparam integer N_SWEEP        = 120;

    // 32 x 8 groups have internal horizontal edges
    localparam integer N_H_INTRA =
        N_PE_ROW * N_SPIN_PER_PE * (N_PE_COL - 1);

    // Right boundary of group g is connected to left boundary of group g+1
    localparam integer N_H_BOUNDARY =
        N_PE_ROW * (N_SPIN_PER_PE - 1);

    // Vertical edges exist independently in all four spin groups
    localparam integer N_V_EDGE =
        (N_PE_ROW - 1) * N_PE_COL * N_SPIN_PER_PE;

    localparam integer N_TOTAL_EDGE =
        N_H_INTRA + N_H_BOUNDARY + N_V_EDGE;

    localparam integer ANNEAL_INIT      = 127;
    localparam integer ANNEAL_FP_SHIFT  = 8;
    localparam integer ANNEAL_ALPHA_NUM = 247;
    localparam integer ANNEAL_ALPHA_DEN = 256;

    reg clk;
    reg rst_n;

    reg [N_PE-1:0] acc_clear;
    reg [N_PE-1:0] en;
    reg [N_PE-1:0] update_en;

    reg [7:0] J [0:N_PE-1];

    reg [N_PE-1:0] i_sigma_N;
    reg [N_PE-1:0] i_sigma_E;
    reg [N_PE-1:0] i_sigma_S;
    reg [N_PE-1:0] i_sigma_W;

    reg [N_PE-1:0] R_H;
    reg [N_PE-1:0] R_V;

    reg [1:0] mx_mode_sel    [0:N_PE-1];
    reg [1:0] mx_input_sel   [0:N_PE-1];
    reg [1:0] mx_spin_sel    [0:N_PE-1];
    reg       mx_bypass_sel  [0:N_PE-1];
    reg [1:0] dmx_output_sel [0:N_PE-1];
    reg [1:0] dmx_spin_sel   [0:N_PE-1];

    wire [N_PE-1:0] o_sigma_N;
    wire [N_PE-1:0] o_sigma_E;
    wire [N_PE-1:0] o_sigma_S;
    wire [N_PE-1:0] o_sigma_W;

    wire [11:0] S [0:N_PE-1];
    wire [N_PE-1:0] MSB_sign;

    // Physical organization:
    // spin_state[PE row][PE column][spin register]
    //
    // spin register:
    // 0 -> sigma_1
    // 1 -> sigma_2
    // 2 -> sigma_3
    // 3 -> sigma_4
    reg spin_state
        [0:N_PE_ROW-1]
        [0:N_PE_COL-1]
        [0:N_SPIN_PER_PE-1];

    // Initial spin state shared by both experiments
    reg initial_spin_state
        [0:N_PE_ROW-1]
        [0:N_PE_COL-1]
        [0:N_SPIN_PER_PE-1];

    // Horizontal coefficients inside each 32 x 8 spin group
    // J_H_INTRA[row][group][column edge]
    reg signed [7:0] J_H_INTRA
        [0:N_PE_ROW-1]
        [0:N_SPIN_PER_PE-1]
        [0:N_PE_COL-2];

    // Horizontal coefficients between consecutive spin groups
    // group 0 right edge <-> group 1 left edge
    // group 1 right edge <-> group 2 left edge
    // group 2 right edge <-> group 3 left edge
    reg signed [7:0] J_H_BOUNDARY
        [0:N_PE_ROW-1]
        [0:N_SPIN_PER_PE-2];

    // Vertical coefficients inside each spin group
    // J_V[row edge][PE column][group]
    reg signed [7:0] J_V
        [0:N_PE_ROW-2]
        [0:N_PE_COL-1]
        [0:N_SPIN_PER_PE-1];

    integer r;
    integer c;
    integer g;
    integer p;
    integer sweep;

    integer rand_seed;
    integer anneal_rand_seed;

    integer total_spin_ones;
    integer flip_count;
    integer anneal_weight;
    integer anneal_weight_fp;
    integer hamiltonian_value;

    integer hamiltonian_file_wo;
    integer hamiltonian_file_w;

    reg tmp_spin;
    reg old_spin;
    reg new_spin;
    reg rand_bit;

    genvar gi;

    // 256 PEs, each PE contains 4 spin registers
    generate
        for (gi = 0; gi < N_PE; gi = gi + 1) begin: PE_ARRAY
            spin_PE_top u_pe (
                .clk(clk),
                .rst_n(rst_n),

                .acc_clear(acc_clear[gi]),
                .en(en[gi]),
                .J(J[gi]),

                .i_sigma_N(i_sigma_N[gi]),
                .i_sigma_E(i_sigma_E[gi]),
                .i_sigma_S(i_sigma_S[gi]),
                .i_sigma_W(i_sigma_W[gi]),

                .R_H(R_H[gi]),
                .R_V(R_V[gi]),

                .mx_mode_sel(mx_mode_sel[gi]),
                .mx_input_sel(mx_input_sel[gi]),
                .mx_spin_sel(mx_spin_sel[gi]),
                .mx_bypass_sel(mx_bypass_sel[gi]),
                .dmx_output_sel(dmx_output_sel[gi]),
                .dmx_spin_sel(dmx_spin_sel[gi]),

                .update_en(update_en[gi]),

                .o_sigma_N(o_sigma_N[gi]),
                .o_sigma_E(o_sigma_E[gi]),
                .o_sigma_S(o_sigma_S[gi]),
                .o_sigma_W(o_sigma_W[gi]),

                .S(S[gi]),
                .MSB_sign(MSB_sign[gi])
            );
        end
    endgenerate

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2.0) clk = ~clk;
    end

    // Physical PE index:
    // PE array is organized as 32 rows x 8 columns
    function integer pe_idx_of;
        input integer row_idx;
        input integer col_idx;
        begin
            pe_idx_of = row_idx * N_PE_COL + col_idx;
        end
    endfunction

    // Select one of four spin registers inside a PE
    function [1:0] spin_sel_of;
        input integer spin_group;
        begin
            spin_sel_of = spin_group[1:0];
        end
    endfunction

    task random_negative_coeff;
        output signed [7:0] coeff;
        integer rand_val;
        begin
            rand_val = $random(rand_seed);

            if (rand_val < 0)
                rand_val = -rand_val;

            rand_val = (rand_val % 127) + 1;   // 1 ~ 127
            coeff = -rand_val;                 // -1 ~ -127
        end
    endtask

    task random_spin_bit;
        output value;
        integer rand_val;
        begin
            rand_val = $random(rand_seed);
            value = rand_val[0];
        end
    endtask

    task init_random_seed;
        begin
            if (!$value$plusargs("SEED=%d", rand_seed)) begin
                rand_seed = 32'h20260517;
                $display("No plusarg SEED found. Default seed is used.");
            end

            $display("-----------------------------------------------");
            $display("Random seed = %0d", rand_seed);
            $display("-----------------------------------------------");
        end
    endtask

    task init_coefficients;
        integer rr;
        integer cc;
        integer gg;
        begin
            // Horizontal coefficients inside each 32 x 8 group
            for (rr = 0; rr < N_PE_ROW; rr = rr + 1) begin
                for (gg = 0; gg < N_SPIN_PER_PE; gg = gg + 1) begin
                    for (cc = 0; cc < N_PE_COL-1; cc = cc + 1) begin
                        random_negative_coeff(
                            J_H_INTRA[rr][gg][cc]
                        );
                    end
                end
            end

            // Horizontal coefficients between consecutive spin groups
            for (rr = 0; rr < N_PE_ROW; rr = rr + 1) begin
                for (gg = 0; gg < N_SPIN_PER_PE-1; gg = gg + 1) begin
                    random_negative_coeff(
                        J_H_BOUNDARY[rr][gg]
                    );
                end
            end

            // Vertical coefficients inside each spin group
            for (rr = 0; rr < N_PE_ROW-1; rr = rr + 1) begin
                for (cc = 0; cc < N_PE_COL; cc = cc + 1) begin
                    for (gg = 0; gg < N_SPIN_PER_PE; gg = gg + 1) begin
                        random_negative_coeff(
                            J_V[rr][cc][gg]
                        );
                    end
                end
            end

            $display("-----------------------------------------------");
            $display("Random negative interaction coefficients");
            $display("Range: -1 to -127");
            $display("Horizontal intra-group edges: %0d", N_H_INTRA);
            $display("Horizontal group-boundary edges: %0d", N_H_BOUNDARY);
            $display("Vertical edges: %0d", N_V_EDGE);
            $display("Total edges: %0d", N_TOTAL_EDGE);
            $display("-----------------------------------------------");
        end
    endtask

    task clear_all_controls;
        begin
            for (p = 0; p < N_PE; p = p + 1) begin
                acc_clear[p] = 1'b0;
                en[p]        = 1'b0;
                update_en[p] = 1'b0;

                J[p] = 8'd0;

                i_sigma_N[p] = 1'b0;
                i_sigma_E[p] = 1'b0;
                i_sigma_S[p] = 1'b0;
                i_sigma_W[p] = 1'b0;

                R_H[p] = 1'b0;
                R_V[p] = 1'b0;

                mx_mode_sel[p]    = 2'b00;
                mx_input_sel[p]   = 2'b00;
                mx_spin_sel[p]    = 2'b00;
                mx_bypass_sel[p]  = 1'b0;
                dmx_output_sel[p] = 2'b00;
                dmx_spin_sel[p]   = 2'b00;
            end
        end
    endtask

    task reset_all_pes;
        begin
            rst_n = 1'b0;

            clear_all_controls();

            repeat (3) @(posedge clk);

            rst_n = 1'b1;
            #1;
        end
    endtask

    task clear_mac;
        input integer pe_idx;
        begin
            acc_clear[pe_idx] = 1'b1;
            en[pe_idx]        = 1'b0;

            @(posedge clk);
            #1;

            acc_clear[pe_idx] = 1'b0;
        end
    endtask

    task accumulate_term;
        input integer pe_idx;
        input [1:0] direction_sel;
        input signed [7:0] coeff;
        input spin_bit;
        begin
            i_sigma_N[pe_idx] = 1'b0;
            i_sigma_E[pe_idx] = 1'b0;
            i_sigma_S[pe_idx] = 1'b0;
            i_sigma_W[pe_idx] = 1'b0;

            if (direction_sel == 2'b00)
                i_sigma_N[pe_idx] = spin_bit;
            else if (direction_sel == 2'b01)
                i_sigma_E[pe_idx] = spin_bit;
            else if (direction_sel == 2'b10)
                i_sigma_S[pe_idx] = spin_bit;
            else
                i_sigma_W[pe_idx] = spin_bit;

            mx_mode_sel[pe_idx]  = 2'b00;          // interaction mode
            mx_input_sel[pe_idx] = direction_sel;
            J[pe_idx]            = coeff[7:0];

            en[pe_idx] = 1'b1;

            @(posedge clk);
            #1;

            en[pe_idx] = 1'b0;
        end
    endtask

    task accumulate_annealing_term;
        input integer pe_idx;
        input integer weight;
        begin
            if (weight > 0) begin
                random_spin_bit(rand_bit);

                R_H[pe_idx] = rand_bit;

                mx_mode_sel[pe_idx] = 2'b10;       // random-H mode
                J[pe_idx]           = weight[7:0];

                en[pe_idx] = 1'b1;

                @(posedge clk);
                #1;

                en[pe_idx] = 1'b0;
            end
        end
    endtask

    task write_spin;
        input integer row_idx;
        input integer col_idx;
        input integer group_idx;
        input value;

        integer pe_idx;
        begin
            pe_idx = pe_idx_of(row_idx, col_idx);

            clear_mac(pe_idx);

            mx_mode_sel[pe_idx] = 2'b01;           // local bias mode
            J[pe_idx]           = value ? 8'sd10 : -8'sd10;

            en[pe_idx] = 1'b1;

            @(posedge clk);
            #1;

            en[pe_idx] = 1'b0;

            mx_spin_sel[pe_idx]  = spin_sel_of(group_idx);
            dmx_spin_sel[pe_idx] = spin_sel_of(group_idx);
            update_en[pe_idx]    = 1'b1;

            @(posedge clk);
            #1;

            update_en[pe_idx] = 1'b0;

            spin_state[row_idx][col_idx][group_idx] = value;
        end
    endtask

    task generate_initial_spin_state;
        integer rr;
        integer cc;
        integer gg;
        begin
            // The initial spin state is generated only once.
            //
            // The same state is reused for:
            // 1. Without annealing
            // 2. With annealing
            for (gg = 0; gg < N_SPIN_PER_PE; gg = gg + 1) begin
                for (rr = 0; rr < N_PE_ROW; rr = rr + 1) begin
                    for (cc = 0; cc < N_PE_COL; cc = cc + 1) begin
                        random_spin_bit(tmp_spin);

                        initial_spin_state[rr][cc][gg] =
                            tmp_spin;

                        write_spin(
                            rr,
                            cc,
                            gg,
                            tmp_spin
                        );
                    end
                end
            end
        end
    endtask

    task restore_initial_spin_state;
        integer rr;
        integer cc;
        integer gg;
        begin
            // Clear the shadow spin map before restoration
            for (rr = 0; rr < N_PE_ROW; rr = rr + 1) begin
                for (cc = 0; cc < N_PE_COL; cc = cc + 1) begin
                    for (gg = 0; gg < N_SPIN_PER_PE; gg = gg + 1) begin
                        spin_state[rr][cc][gg] = 1'b0;
                    end
                end
            end

            // Restore the same initial spin state
            for (gg = 0; gg < N_SPIN_PER_PE; gg = gg + 1) begin
                for (rr = 0; rr < N_PE_ROW; rr = rr + 1) begin
                    for (cc = 0; cc < N_PE_COL; cc = cc + 1) begin
                        write_spin(
                            rr,
                            cc,
                            gg,
                            initial_spin_state[rr][cc][gg]
                        );
                    end
                end
            end
        end
    endtask

    task update_one_spin;
        input integer row_idx;
        input integer col_idx;
        input integer group_idx;
        input integer anneal_weight_in;

        integer pe_idx;
        begin
            pe_idx = pe_idx_of(row_idx, col_idx);

            old_spin =
                spin_state[row_idx][col_idx][group_idx];

            clear_mac(pe_idx);

            mx_spin_sel[pe_idx] =
                spin_sel_of(group_idx);

            // North neighbor in the same spin group
            if (row_idx > 0) begin
                accumulate_term(
                    pe_idx,
                    2'b00,
                    J_V[row_idx-1][col_idx][group_idx],
                    spin_state[row_idx-1][col_idx][group_idx]
                );
            end

            // East neighbor inside the same 32 x 8 spin group
            if (col_idx < N_PE_COL-1) begin
                accumulate_term(
                    pe_idx,
                    2'b01,
                    J_H_INTRA[row_idx][group_idx][col_idx],
                    spin_state[row_idx][col_idx+1][group_idx]
                );
            end
            // Right boundary of group g is connected to
            // left boundary of group g+1 using a register buffer
            else if (group_idx < N_SPIN_PER_PE-1) begin
                accumulate_term(
                    pe_idx,
                    2'b01,
                    J_H_BOUNDARY[row_idx][group_idx],
                    spin_state[row_idx][0][group_idx+1]
                );
            end

            // South neighbor in the same spin group
            if (row_idx < N_PE_ROW-1) begin
                accumulate_term(
                    pe_idx,
                    2'b10,
                    J_V[row_idx][col_idx][group_idx],
                    spin_state[row_idx+1][col_idx][group_idx]
                );
            end

            // West neighbor inside the same 32 x 8 spin group
            if (col_idx > 0) begin
                accumulate_term(
                    pe_idx,
                    2'b11,
                    J_H_INTRA[row_idx][group_idx][col_idx-1],
                    spin_state[row_idx][col_idx-1][group_idx]
                );
            end
            // Left boundary of group g is connected to
            // right boundary of group g-1 using a register buffer
            else if (group_idx > 0) begin
                accumulate_term(
                    pe_idx,
                    2'b11,
                    J_H_BOUNDARY[row_idx][group_idx-1],
                    spin_state[row_idx][N_PE_COL-1][group_idx-1]
                );
            end

            // Annealing perturbation
            //
            // If anneal_weight_in = 0, this task does not
            // perform any random perturbation.
            accumulate_annealing_term(
                pe_idx,
                anneal_weight_in
            );

            dmx_spin_sel[pe_idx] =
                spin_sel_of(group_idx);

            update_en[pe_idx] = 1'b1;

            @(posedge clk);
            #1;

            new_spin = ~MSB_sign[pe_idx];

            if (old_spin != new_spin)
                flip_count = flip_count + 1;

            spin_state[row_idx][col_idx][group_idx] =
                new_spin;

            update_en[pe_idx] = 1'b0;
        end
    endtask

    // Calculate the original Ising Hamiltonian
    //
    // H = -sum(J_ij * sigma_i * sigma_j)
    //
    // Annealing random terms are not included.
    // This allows direct comparison of solution quality.
    task calculate_ising_hamiltonian;
        output integer H_out;

        integer rr;
        integer cc;
        integer gg;
        begin
            H_out = 0;

            // Horizontal edges inside each spin group
            for (rr = 0; rr < N_PE_ROW; rr = rr + 1) begin
                for (gg = 0; gg < N_SPIN_PER_PE; gg = gg + 1) begin
                    for (cc = 0; cc < N_PE_COL-1; cc = cc + 1) begin
                        if (
                            spin_state[rr][cc][gg]
                            ==
                            spin_state[rr][cc+1][gg]
                        ) begin
                            H_out =
                                H_out
                                - $signed(
                                    J_H_INTRA[rr][gg][cc]
                                );
                        end
                        else begin
                            H_out =
                                H_out
                                + $signed(
                                    J_H_INTRA[rr][gg][cc]
                                );
                        end
                    end
                end
            end

            // Horizontal edges between consecutive spin groups
            for (rr = 0; rr < N_PE_ROW; rr = rr + 1) begin
                for (gg = 0; gg < N_SPIN_PER_PE-1; gg = gg + 1) begin
                    if (
                        spin_state[rr][N_PE_COL-1][gg]
                        ==
                        spin_state[rr][0][gg+1]
                    ) begin
                        H_out =
                            H_out
                            - $signed(
                                J_H_BOUNDARY[rr][gg]
                            );
                    end
                    else begin
                        H_out =
                            H_out
                            + $signed(
                                J_H_BOUNDARY[rr][gg]
                            );
                    end
                end
            end

            // Vertical edges inside each spin group
            for (rr = 0; rr < N_PE_ROW-1; rr = rr + 1) begin
                for (cc = 0; cc < N_PE_COL; cc = cc + 1) begin
                    for (gg = 0; gg < N_SPIN_PER_PE; gg = gg + 1) begin
                        if (
                            spin_state[rr][cc][gg]
                            ==
                            spin_state[rr+1][cc][gg]
                        ) begin
                            H_out =
                                H_out
                                - $signed(
                                    J_V[rr][cc][gg]
                                );
                        end
                        else begin
                            H_out =
                                H_out
                                + $signed(
                                    J_V[rr][cc][gg]
                                );
                        end
                    end
                end
            end
        end
    endtask

    // Save four 32 x 8 spin groups as one 32 x 32 logical lattice
    //
    // Output column arrangement:
    // [sigma_1 group][sigma_2 group][sigma_3 group][sigma_4 group]
    task save_spin_map_to_file;
        input [8*80-1:0] filename;

        integer fh;
        integer rr;
        integer cc;
        integer gg;
        begin
            fh = $fopen(filename, "w");

            for (rr = 0; rr < N_PE_ROW; rr = rr + 1) begin
                for (gg = 0; gg < N_SPIN_PER_PE; gg = gg + 1) begin
                    for (cc = 0; cc < N_PE_COL; cc = cc + 1) begin
                        $fwrite(
                            fh,
                            "%0d",
                            spin_state[rr][cc][gg]
                        );
                    end
                end

                $fwrite(fh, "\n");
            end

            $fclose(fh);
        end
    endtask

    task save_coefficients_to_file;
        input [8*80-1:0] filename;

        integer fh;
        integer rr;
        integer cc;
        integer gg;
        begin
            fh = $fopen(filename, "w");

            $fwrite(
                fh,
                "Horizontal intra-group coefficients, size 32 x 4 x 7\n"
            );

            for (gg = 0; gg < N_SPIN_PER_PE; gg = gg + 1) begin
                $fwrite(fh, "Spin group %0d\n", gg);

                for (rr = 0; rr < N_PE_ROW; rr = rr + 1) begin
                    for (cc = 0; cc < N_PE_COL-1; cc = cc + 1) begin
                        $fwrite(
                            fh,
                            "%0d ",
                            J_H_INTRA[rr][gg][cc]
                        );
                    end

                    $fwrite(fh, "\n");
                end
            end

            $fwrite(
                fh,
                "\nHorizontal group-boundary coefficients, size 32 x 3\n"
            );

            for (rr = 0; rr < N_PE_ROW; rr = rr + 1) begin
                for (gg = 0; gg < N_SPIN_PER_PE-1; gg = gg + 1) begin
                    $fwrite(
                        fh,
                        "%0d ",
                        J_H_BOUNDARY[rr][gg]
                    );
                end

                $fwrite(fh, "\n");
            end

            $fwrite(
                fh,
                "\nVertical coefficients, size 31 x 8 x 4\n"
            );

            for (gg = 0; gg < N_SPIN_PER_PE; gg = gg + 1) begin
                $fwrite(fh, "Spin group %0d\n", gg);

                for (rr = 0; rr < N_PE_ROW-1; rr = rr + 1) begin
                    for (cc = 0; cc < N_PE_COL; cc = cc + 1) begin
                        $fwrite(
                            fh,
                            "%0d ",
                            J_V[rr][cc][gg]
                        );
                    end

                    $fwrite(fh, "\n");
                end
            end

            $fclose(fh);
        end
    endtask

    task save_step_result;
        input integer step_num;
        input use_annealing;
        begin
            if (use_annealing == 1'b0) begin
                case (step_num)
                    1:
                        save_spin_map_to_file(
                            "step1_result_wo_annealing.txt"
                        );

                    10:
                        save_spin_map_to_file(
                            "step10_result_wo_annealing.txt"
                        );

                    20:
                        save_spin_map_to_file(
                            "step20_result_wo_annealing.txt"
                        );

                    30:
                        save_spin_map_to_file(
                            "step30_result_wo_annealing.txt"
                        );

                    60:
                        save_spin_map_to_file(
                            "step60_result_wo_annealing.txt"
                        );

                    90:
                        save_spin_map_to_file(
                            "step90_result_wo_annealing.txt"
                        );

                    120:
                        save_spin_map_to_file(
                            "step120_result_wo_annealing.txt"
                        );

                    default: begin
                    end
                endcase
            end
            else begin
                case (step_num)
                    1:
                        save_spin_map_to_file(
                            "step1_result.txt"
                        );

                    10:
                        save_spin_map_to_file(
                            "step10_result.txt"
                        );

                    20:
                        save_spin_map_to_file(
                            "step20_result.txt"
                        );

                    30:
                        save_spin_map_to_file(
                            "step30_result.txt"
                        );

                    60:
                        save_spin_map_to_file(
                            "step60_result.txt"
                        );

                    90:
                        save_spin_map_to_file(
                            "step90_result.txt"
                        );

                    120:
                        save_spin_map_to_file(
                            "step120_result.txt"
                        );

                    default: begin
                    end
                endcase
            end
        end
    endtask

    task run_ising_experiment;
        input use_annealing;
        input integer hamiltonian_file;
        begin
            if (use_annealing == 1'b1) begin
                anneal_weight_fp =
                    ANNEAL_INIT << ANNEAL_FP_SHIFT;

                anneal_weight = ANNEAL_INIT;
            end
            else begin
                anneal_weight_fp = 0;
                anneal_weight    = 0;
            end

            calculate_ising_hamiltonian(
                hamiltonian_value
            );

            // File format:
            // step Hamiltonian flip_count anneal_weight
            $fwrite(
                hamiltonian_file,
                "# step Hamiltonian flip_count anneal_weight\n"
            );

            $fwrite(
                hamiltonian_file,
                "%0d %0d %0d %0d\n",
                0,
                hamiltonian_value,
                0,
                anneal_weight
            );

            // Sequential asynchronous spin updates
            //
            // The four spin groups are activated sequentially,
            // similar to the on-chip scaling operation of FlexSpin.
            for (
                sweep = 0;
                sweep < N_SWEEP;
                sweep = sweep + 1
            ) begin
                flip_count = 0;

                if (use_annealing == 1'b1) begin
                    if (sweep == N_SWEEP - 1) begin
                        anneal_weight = 0;
                    end
                    else begin
                        anneal_weight =
                            anneal_weight_fp
                            >> ANNEAL_FP_SHIFT;

                        if (anneal_weight < 1)
                            anneal_weight = 1;
                    end
                end
                else begin
                    anneal_weight = 0;
                end

                // Group 0: sigma_1 of all PEs
                // Group 1: sigma_2 of all PEs
                // Group 2: sigma_3 of all PEs
                // Group 3: sigma_4 of all PEs
                for (
                    g = 0;
                    g < N_SPIN_PER_PE;
                    g = g + 1
                ) begin
                    for (
                        r = 0;
                        r < N_PE_ROW;
                        r = r + 1
                    ) begin
                        for (
                            c = 0;
                            c < N_PE_COL;
                            c = c + 1
                        ) begin
                            update_one_spin(
                                r,
                                c,
                                g,
                                anneal_weight
                            );
                        end
                    end
                end

                calculate_ising_hamiltonian(
                    hamiltonian_value
                );

                if (use_annealing == 1'b1) begin
                    $display(
                        "[With annealing] Step %0d / %0d, anneal_weight = %0d, flip_count = %0d, Hamiltonian = %0d",
                        sweep + 1,
                        N_SWEEP,
                        anneal_weight,
                        flip_count,
                        hamiltonian_value
                    );
                end
                else begin
                    $display(
                        "[Without annealing] Step %0d / %0d, flip_count = %0d, Hamiltonian = %0d",
                        sweep + 1,
                        N_SWEEP,
                        flip_count,
                        hamiltonian_value
                    );
                end

                $fwrite(
                    hamiltonian_file,
                    "%0d %0d %0d %0d\n",
                    sweep + 1,
                    hamiltonian_value,
                    flip_count,
                    anneal_weight
                );

                save_step_result(
                    sweep + 1,
                    use_annealing
                );

                if (use_annealing == 1'b1) begin
                    anneal_weight_fp =
                        (
                            anneal_weight_fp
                            * ANNEAL_ALPHA_NUM
                        )
                        / ANNEAL_ALPHA_DEN;
                end
            end
        end
    endtask

    task display_shadow_spin_map;
        begin
            $display("-----------------------------------------------");
            $display("32x32 logical spin map");
            $display("bit encoding: 1 = +1, 0 = -1");
            $display("columns 0-7   : sigma_1");
            $display("columns 8-15  : sigma_2");
            $display("columns 16-23 : sigma_3");
            $display("columns 24-31 : sigma_4");

            for (r = 0; r < N_PE_ROW; r = r + 1) begin
                $write("row %0d : ", r);

                for (
                    g = 0;
                    g < N_SPIN_PER_PE;
                    g = g + 1
                ) begin
                    for (
                        c = 0;
                        c < N_PE_COL;
                        c = c + 1
                    ) begin
                        $write(
                            "%0d",
                            spin_state[r][c][g]
                        );
                    end
                end

                $write("\n");
            end

            $display("-----------------------------------------------");
        end
    endtask

    task count_spin_ones;
        begin
            total_spin_ones = 0;

            for (r = 0; r < N_PE_ROW; r = r + 1) begin
                for (c = 0; c < N_PE_COL; c = c + 1) begin
                    for (
                        g = 0;
                        g < N_SPIN_PER_PE;
                        g = g + 1
                    ) begin
                        if (
                            spin_state[r][c][g]
                            == 1'b1
                        )
                            total_spin_ones =
                                total_spin_ones + 1;
                    end
                end
            end

            $display(
                "Number of spin bit 1s: %0d / %0d",
                total_spin_ones,
                N_TOTAL_SPIN
            );
        end
    endtask

    initial begin
        init_random_seed();
        init_coefficients();

        reset_all_pes();

        $display("===============================================");
        $display("32x8x4 FlexSpin Ising Lattice Testbench");
        $display("PE array          : %0d x %0d",
                 N_PE_ROW, N_PE_COL);
        $display("Spin registers/PE : %0d",
                 N_SPIN_PER_PE);
        $display("Total PEs         : %0d", N_PE);
        $display("Total spins       : %0d",
                 N_TOTAL_SPIN);
        $display("Logical 2D lattice: %0d x %0d",
                 N_LOGICAL_ROW, N_LOGICAL_COL);
        $display("Total coefficients: %0d",
                 N_TOTAL_EDGE);
        $display("All coefficients are negative and randomized.");
        $display("Evaluation order:");
        $display("1. Without annealing");
        $display("2. With exponential annealing");
        $display("===============================================");

        // Generate and load one shared initial spin state
        generate_initial_spin_state();

        // Save the random state after initialization.
        // The annealing run starts from this random sequence state.
        anneal_rand_seed = rand_seed;

        save_spin_map_to_file(
            "initial_spin.txt"
        );

        save_coefficients_to_file(
            "initial_coefficient.txt"
        );

        $display(
            "Initial spin state saved to initial_spin.txt"
        );

        $display(
            "Initial coefficients saved to initial_coefficient.txt"
        );

        count_spin_ones();

        hamiltonian_file_wo =
            $fopen(
                "Ising_Hamiltonian_wo_annealing.txt",
                "w"
            );

        hamiltonian_file_w =
            $fopen(
                "Ising_Hamiltonian_w_annealing.txt",
                "w"
            );

        if (
            hamiltonian_file_wo == 0
            || hamiltonian_file_w == 0
        ) begin
            $display(
                "ERROR: Failed to open Hamiltonian output files."
            );

            $finish;
        end

        // =====================================================
        // Experiment 1: Without annealing
        // =====================================================
        $display("===============================================");
        $display("Experiment 1: Without annealing");
        $display("===============================================");

        run_ising_experiment(
            1'b0,
            hamiltonian_file_wo
        );

        $display("===============================================");
        $display("Final spin values without annealing");

        display_shadow_spin_map();

        calculate_ising_hamiltonian(
            hamiltonian_value
        );

        $display(
            "Final Hamiltonian without annealing = %0d",
            hamiltonian_value
        );

        // =====================================================
        // Reset all PEs and restore the same initial spin state
        // =====================================================
        $display("===============================================");
        $display("Resetting all PEs");
        $display("Restoring the same initial spin state");
        $display("===============================================");

        reset_all_pes();

        restore_initial_spin_state();

        // Restore the random sequence used for annealing
        rand_seed = anneal_rand_seed;

        calculate_ising_hamiltonian(
            hamiltonian_value
        );

        $display(
            "Restored initial Hamiltonian = %0d",
            hamiltonian_value
        );

        // =====================================================
        // Experiment 2: With exponential annealing
        // =====================================================
        $display("===============================================");
        $display("Experiment 2: With exponential annealing");
        $display("===============================================");

        run_ising_experiment(
            1'b1,
            hamiltonian_file_w
        );

        $display("===============================================");
        $display("Final spin values with annealing");

        display_shadow_spin_map();

        calculate_ising_hamiltonian(
            hamiltonian_value
        );

        $display(
            "Final Hamiltonian with annealing = %0d",
            hamiltonian_value
        );

        count_spin_ones();

        $fclose(hamiltonian_file_wo);
        $fclose(hamiltonian_file_w);

        $display("===============================================");
        $display("Generated spin-map files");
        $display("-----------------------------------------------");
        $display("initial_spin.txt");
        $display("initial_coefficient.txt");

        $display("step1_result_wo_annealing.txt");
        $display("step10_result_wo_annealing.txt");
        $display("step20_result_wo_annealing.txt");
        $display("step30_result_wo_annealing.txt");
        $display("step60_result_wo_annealing.txt");
        $display("step90_result_wo_annealing.txt");
        $display("step120_result_wo_annealing.txt");

        $display("step1_result.txt");
        $display("step10_result.txt");
        $display("step20_result.txt");
        $display("step30_result.txt");
        $display("step60_result.txt");
        $display("step90_result.txt");
        $display("step120_result.txt");

        $display("-----------------------------------------------");
        $display("Generated Hamiltonian files");
        $display("-----------------------------------------------");
        $display("Ising_Hamiltonian_wo_annealing.txt");
        $display("Ising_Hamiltonian_w_annealing.txt");
        $display("===============================================");

        #50;
        $finish;
    end

endmodule
