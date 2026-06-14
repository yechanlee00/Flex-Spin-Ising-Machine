/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Flex-Spin : A CMOS Ising Machine With 256 Flexible Spin Processing Elements With 8-b
// Coefficients for Solving Combinatorial Optimization Problems
// Yuqi Su , Member, IEEE, Tony Tae-Hyoung Kim , Senior Member, IEEE, and Bongjin Kim , Senior Member, IEEE
// This is not a offcial code of paper!

// Made by yechan LEE (논문 학습 및 이해를 위해 작성한 코드입니다.)
// Last update : 2026-05-23
// No AI tool was used
/////////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module spin_operator(
	input wire clk,
	input wire rst_n,		// d_ff reset
	input wire acc_clear,		// accumulation reset
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
	

	assign spin_neg = ~spin; 			// if spin == 0, spin_neg == 1 and it becomes input of first full_adder so that J becomes -J
							 			// if spin == 1, spin_neg == 0 and J remains with no sign conversion
	assign c[0] = spin_neg;
	//assign J_total = {{4{J[7]}}, J}; 	// sign extension
	assign J_xor = J ^ {8{spin_neg}};		// XOR based multipier

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

	assign reg_en = en | acc_clear; 	// D F/F is activated when en == 1 or acc_clear == 1
	
	// D F/F generation
	generate
		for(i = 0; i < 12; i = i + 1) begin: REG_ACC
			d_ff d_ff_acc (
				.clk(clk),
				.rst_n(rst_n), 
				.en(reg_en),			// if en(en), D F/F will not work for reseting it's value when acc_clear == 1
				.d(d_next[i]),
				.q(S[i])
			);
		end
	endgenerate

	assign MSB_sign = S[11];
		
endmodule

module full_adder(

	input wire a,
	input wire b,
	input wire cin,
	output wire sum,
	output wire cout
);

	assign sum = a ^ b ^ cin;
	assign cout = (a & b) | cin & (a ^ b); 

endmodule

module d_ff(
	input wire clk,
	input wire rst_n, 	// synchronous reset is required after one local term's calculation is done 
	input wire en,		// MAC : Multiply -> Accumulate, enable signal is required for distinguishing each operation
	input wire d,
	output reg q
);

	always @(posedge clk) begin
		if(!rst_n) q <= 1'b0; 
		else if(en) q <= d;
	end

endmodule
