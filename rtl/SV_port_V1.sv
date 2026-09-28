

module significand_arithmetic(
    input logic [26:0] low,
    input logic [26:0] high,
    input logic sub,
    output logic [27:0] result
    );

    logic [27:0] sum;
    assign sum = {1'b0, low} + {1'b0, high};
    assign result = {sum[27] & ~sub, sum[26:0]};

endmodule



module exponent_diff(
    input logic [7:0] a,
    input logic [7:0] b,
    output logic a_ge_b,
    output logic [7:0] abs_diff
);

    always_comb begin
        if (a >= b) begin
            abs_diff = a - b;
            a_ge_b = 1'b1;
        end
        else begin
            abs_diff = b - a;
            a_ge_b = 1'b0;
        end
    end

endmodule



module classify(
    input logic [31:0] operand,
    output logic is_infinity,
    output logic is_nan
);

    logic exp_all_ones;
    logic sig_all_zeros;
    assign exp_all_ones = (operand[30:23] == 8'hFF);
    assign sig_all_zeros = (operand[22:0]  == 23'd0);

    assign is_infinity = exp_all_ones &  sig_all_zeros;
    assign is_nan = exp_all_ones & ~sig_all_zeros;

endmodule



module special_case(
    input logic a_sign,
    input logic b_sign,
    input logic a_inf,
    input logic b_inf,
    input logic a_nan,
    input logic b_nan,
    input logic [31:0] operand,
    output logic [31:0] result
);
    logic sign;
    logic [1:0] muxsel;

    always_comb begin
        sign = a_inf ? a_sign : b_sign;

        muxsel[0] = (a_nan || b_nan) || ((a_sign ^ b_sign) && a_inf && b_inf);
        muxsel[1] = !muxsel[0] && (a_inf || b_inf);

        case (muxsel)
            2'b00 : result = operand;
            2'b01 : result = 32'h7FC00000;
            2'b10 : result = {sign, 8'hFF, 23'd0}; // exponent all 1s, significand all 0s
            2'b11 : result = 32'h7FC00000;
        endcase
    end

endmodule



module handle_special_cases(
    input logic [31:0] a,
    input logic [31:0] b,
    input logic [31:0] arithmetic_output,
    input logic effective_b_sign,
    output logic [31:0] result
);

    logic classify_a_nan;
    logic classify_a_inf;
    logic classify_b_nan;
    logic classify_b_inf;

    classify u_classify_a(.operand (a), .is_nan (classify_a_nan), .is_infinity(classify_a_inf));
    classify u_classify_b(.operand (b), .is_nan (classify_b_nan), .is_infinity(classify_b_inf));

    special_case u_special_case_1(.operand (arithmetic_output), .result (result),
                                .a_nan (classify_a_nan), .a_inf (classify_a_inf), .a_sign (a[31]),
                                .b_nan (classify_b_nan), .b_inf (classify_b_inf), .b_sign (effective_b_sign));

endmodule





module pack(
    input logic [23:0] significand,
    input logic [7:0] exponent,
    input logic normal_result_sign,
    input logic a_sign,
    input logic effective_b_sign,
    input logic overflow,
    output logic [31:0] operand
);

    logic sign;
    logic [7:0] first_stage_exp_selection;
    logic [7:0] second_stage_exp_selection;

    always_comb begin
        if (!(|significand)) begin
            sign = a_sign && effective_b_sign;
            first_stage_exp_selection = 8'd0;
        end
        else begin
            sign = normal_result_sign;
            first_stage_exp_selection = exponent;
        end

        if (exponent == 8'd1 && !significand[23]) begin
            second_stage_exp_selection = 8'd0;
        end
        else begin
            second_stage_exp_selection = first_stage_exp_selection;
        end

        if (overflow) begin
            operand[30:0] = 31'h7F800000;
        end
        else begin
           operand[30:0] = {second_stage_exp_selection, significand[22:0]}; 
        end

        operand[31] = sign;
    end

endmodule



module round(
    input logic [26:0] significand,
    output logic [24:0] rounded_significand
);

    logic round_up;
    always_comb begin
        round_up = significand[2] && (significand[0] || significand[1] || significand[3]);
        if (round_up) begin
            rounded_significand = {1'b0, significand[26:3]} + 25'd1;
        end
        else begin
            rounded_significand = {1'b0, significand[26:3]};
        end
    end

endmodule


module operand_negation_extended(
    input logic sign_a,
    input logic sign_b,
    input logic [26:0] operand_a,
    input logic [26:0] operand_b,
    output logic sign,
    output logic sub,
    output logic [26:0] low,
    output logic [26:0] high
);

    logic high_sign;
    logic sign_comparison;

    logic [26:0] conditional_negate_input;

    always_comb begin

        if (operand_a >= operand_b) begin
            high = operand_a;
            conditional_negate_input = operand_b;
            high_sign = sign_a;
        end
        else begin
            high = operand_b;
            conditional_negate_input = operand_a;
            high_sign = sign_b;
        end

        sign_comparison = (sign_a != sign_b);
        sign = (sign_comparison) ? high_sign : sign_a;
        sub = sign_comparison;

        low = sign_comparison ? -conditional_negate_input : conditional_negate_input;

    end

endmodule



module unpack(
    input logic [31:0] operand,
    output logic sign,
    output logic [7:0] exponent,
    output logic [23:0] significand
);
    logic hidden_bit;
    always_comb begin
        sign = operand[31];
        if (operand[30:23] == 0) begin
            exponent = 8'd1;
            hidden_bit = 1'b0;
        end
        else begin
            exponent = operand[30:23];
            hidden_bit = 1'b1;
        end
        significand = {hidden_bit, operand[22:0]};
    end
    
endmodule



module lsr_extended(
    input logic [23:0] significand,
    input logic [7:0] shift,
    output logic [26:0] shifted_extended
);
    logic [26:0] shifted;
    logic [23:0] mask;

    always_comb begin
        if (shift < 8'd27) begin
            shifted = {significand, 3'b000} >> shift;
            shifted_extended[26:1] = shifted[26:1];
        end
        else begin
            shifted = 27'd0;
            shifted_extended[26:1] = 26'D0;
        end

        if (shift <= 8'd2) begin
            mask = 24'd0;
        end
        else if (shift >= 8'd26) begin
            mask = 24'hFFFFFF;
        end
        else begin
            mask = (24'd1 << (shift - 8'd2)) - 24'd1;
        end

        shifted_extended[0] = |(significand & mask);
    end

endmodule


module renormalise(
    input logic [24:0] significand,
    input logic [7:0] exponent,
    output logic [23:0] renormalised_significand,
    output logic [7:0] renormalised_exponent,
    output logic overflow
);

    logic [7:0] exponent_result;
    always_comb begin
        if (significand[24]) begin
            renormalised_significand = significand[24:1];
            exponent_result = exponent + 8'd1;
        end
        else begin
            renormalised_significand = significand[23:0];
            exponent_result = exponent;
        end

        renormalised_exponent = exponent_result;
        overflow = (exponent_result == 8'hFF);
    end


endmodule




module actual_shift_calculator(
    input logic [7:0] exponent,
    input logic [7:0] first_one_position,
    output logic [7:0] shift
);

    logic [7:0] exp_minus_one;
    always_comb begin
        exp_minus_one = exponent - 8'd1;

        shift =  (exp_minus_one >= first_one_position) ? 
        first_one_position : exp_minus_one;
    end

endmodule


module find_first_one_position(
    input logic [23:0] significand,
    output logic [7:0] first_one_position
);

    always_comb begin
        if (significand[23])
            first_one_position = 8'd0;
        else if (significand[22])
            first_one_position = 8'd1;
        else if (significand[21])
            first_one_position = 8'd2;
        else if (significand[20])
            first_one_position = 8'd3;
        else if (significand[19])
            first_one_position = 8'd4;
        else if (significand[18])
            first_one_position = 8'd5;
        else if (significand[17])
            first_one_position = 8'd6;
        else if (significand[16])
            first_one_position = 8'd7;
        else if (significand[15])
            first_one_position = 8'd8;
        else if (significand[14])
            first_one_position = 8'd9;
        else if (significand[13])
            first_one_position = 8'd10;
        else if (significand[12])
            first_one_position = 8'd11;
        else if (significand[11])
            first_one_position = 8'd12;
        else if (significand[10])
            first_one_position = 8'd13;
        else if (significand[9])
            first_one_position = 8'd14;
        else if (significand[8])
            first_one_position = 8'd15;
        else if (significand[7])
            first_one_position = 8'd16;
        else if (significand[6])
            first_one_position = 8'd17;
        else if (significand[5])
            first_one_position = 8'd18;
        else if (significand[4])
            first_one_position = 8'd19;
        else if (significand[3])
            first_one_position = 8'd20;
        else if (significand[2])
            first_one_position = 8'd21;
        else if (significand[1])
            first_one_position = 8'd22;
        else if (significand[0])
            first_one_position = 8'd23;
        else
            first_one_position = 8'd24;
    end

endmodule


/*
if non-rounding-related bits are all 0s
pick 24 or 25 depending on condition (!G && R)
otherwise use position of first 1
put this into actual_shift_calculator along with exponent
shift significand by this much

subtract actual shift amount from initial exponent
choose normalised exponent based on bit 27 of significand


for normalised significand,
choose between output of mux that chooses between
0 and shifted significand,
and assign msb of normalised significand based on msb of input,
G and R

*/
module normalise_extended_subnormal(
    input logic [27:0] significand,
    input logic [7:0] exponent,
    output logic [26:0] normalised_significand,
    output logic [7:0] normalised_exponent
);

    logic significand_nonzero;

    logic [7:0] detected_first_one_position;
    logic [7:0] first_one_position;
    logic [7:0] shift;
    logic [25:0] shifted;

    logic [7:0] first_stage_exponent_selection;
    logic [25:0] first_stage_significand_selection;

    logic [25:0] normalised_significand_msbs;
    logic normalised_significand_lsb;

    find_first_one_position u_find(.significand (significand[26:3]), 
                                   .first_one_position (detected_first_one_position));


    actual_shift_calculator u_shift(.first_one_position (first_one_position),
                                    .exponent (exponent), .shift(shift));

    always_comb begin   
        significand_nonzero = |significand[26:3];

        if (!(significand_nonzero)) begin
            if (!significand[2] && significand[1]) begin
                first_one_position = 8'd25;
            end
            else begin
                first_one_position = 8'd24;
            end
        end
        else begin
            first_one_position = detected_first_one_position;
        end

        shifted = significand[26:1] << shift;

        if (significand_nonzero) begin
            first_stage_exponent_selection = exponent - shift;
            first_stage_significand_selection = shifted;
        end
        else begin
            first_stage_exponent_selection = 8'd0;
            first_stage_significand_selection = 26'd0;
        end

        if (significand[27]) begin
            normalised_exponent = exponent + 8'd1;
            normalised_significand_msbs = significand[27:2];
        end
        else begin
            normalised_exponent = first_stage_exponent_selection;
            normalised_significand_msbs = first_stage_significand_selection;
        end

        normalised_significand_lsb = (significand[27] && significand[1]) || (significand[0]);

        normalised_significand = {normalised_significand_msbs, normalised_significand_lsb};
    end

endmodule




module add_sub_32 (
    input logic [31:0] a,
    input logic [31:0] b,
    input logic op,
    output logic [31:0] out
);

    // Input unpacking
    logic a_sign;
    logic b_sign;
    logic [23:0] a_significand;
    logic [23:0] b_significand;
    logic [7:0] a_exponent;
    logic [7:0] b_exponent;

    logic effective_b_sign;


    // Exponent comparison / alignment
    logic a_ge_b;
    logic [7:0] exponent_diff;

    logic [23:0] significand_to_shift;
    logic [26:0] aligned_significand;

    logic [7:0] arithmetic_exponent;


    // Operand selection / conditional negation
    logic unshifted_sign;
    logic shifted_sign;
    logic [26:0] unshifted_significand;

    logic arithmetic_sign;
    logic arithmetic_sub;
    logic [26:0] arithmetic_high;
    logic [26:0] arithmetic_low;


    // Significand arithmetic
    logic [27:0] arithmetic_result;


    // Normalisation
    logic [7:0] normalised_exponent;
    logic [26:0] normalised_significand;


    // Rounding
    logic [24:0] rounded_significand;


    // Post-round renormalisation
    logic [7:0] renormalised_exponent;
    logic [23:0] renormalised_significand;
    logic overflow;


    // Packing / special cases
    logic [31:0] packed_result;


    // Input preparation
    assign effective_b_sign = b[31] ^ op;


    unpack u_unpack_a (
        .operand (a),
        .sign (a_sign),
        .significand (a_significand),
        .exponent (a_exponent)
    );

    unpack u_unpack_b (
        .operand (b),
        .sign (b_sign),
        .significand (b_significand),
        .exponent (b_exponent)
    );


    // Exponent comparison and alignment preparation
    exponent_diff u_exp_diff (
        .a (a_exponent),
        .b (b_exponent),
        .a_ge_b (a_ge_b),
        .abs_diff (exponent_diff)
    );


    always_comb begin
        if (a_ge_b) begin
            unshifted_sign = a_sign;
            shifted_sign = effective_b_sign;

            significand_to_shift = b_significand;
            unshifted_significand = {a_significand, 3'b000};

            arithmetic_exponent = a_exponent;
        end
        else begin
            unshifted_sign = effective_b_sign;
            shifted_sign = a_sign;

            significand_to_shift = a_significand;
            unshifted_significand = {b_significand, 3'b000};

            arithmetic_exponent = b_exponent;
        end
    end


    lsr_extended u_lsr_extended (
        .significand (significand_to_shift),
        .shift (exponent_diff),
        .shifted_extended (aligned_significand)
    );


    // Sign handling / conditional negation
    operand_negation_extended u_operand_negation_extended (
        .sign_a (unshifted_sign),
        .sign_b (shifted_sign),
        .operand_a (unshifted_significand),
        .operand_b (aligned_significand),
        .sign (arithmetic_sign),
        .sub (arithmetic_sub),
        .low (arithmetic_low),
        .high (arithmetic_high)
    );


    // Significand arithmetic
    significand_arithmetic u_arithmetic (
        .high (arithmetic_high),
        .low (arithmetic_low),
        .sub (arithmetic_sub),
        .result (arithmetic_result)
    );


    // Normalisation
    normalise_extended_subnormal u_normalise (
        .exponent (arithmetic_exponent),
        .significand (arithmetic_result),
        .normalised_exponent (normalised_exponent),
        .normalised_significand (normalised_significand)
    );


    // Rounding
    round u_round (
        .significand (normalised_significand),
        .rounded_significand (rounded_significand)
    );


    // Post-round renormalisation
    renormalise u_renormalise (
        .exponent (normalised_exponent),
        .significand (rounded_significand),
        .renormalised_exponent (renormalised_exponent),
        .renormalised_significand (renormalised_significand),
        .overflow (overflow)
    );


    // Pack normal result
    pack u_pack (
        .exponent (renormalised_exponent),
        .significand (renormalised_significand),
        .overflow (overflow),
        .normal_result_sign(arithmetic_sign),
        .a_sign (a[31]),
        .effective_b_sign (effective_b_sign),
        .operand (packed_result)
    );


    // Final special-case handling
    handle_special_cases u_handle (
        .a (a),
        .b (b),
        .effective_b_sign (effective_b_sign),
        .arithmetic_output(packed_result),
        .result (out)
    );

endmodule




module testbench;

    logic [31:0] a;
    logic [31:0] b;
    logic op;
    logic [31:0] expected;
    logic [31:0] out;


    typedef struct packed {
        logic [31:0] a;
        logic [31:0] b;
        logic op;
        logic [31:0] expected;
    } test_case_t;

    test_case_t tests [0:NUM_TESTS-1];


    add_sub_32 dut (
        .a   (a),
        .b   (b),
        .op  (op),
        .out (out)
    );


    localparam int NUM_TESTS = 40;

    initial begin
        
        // Basic addition
        // 1.5 + 1.25 = 2.75
        tests[0].a        = 32'h3FC00000;
        tests[0].b        = 32'h3FA00000;
        tests[0].op       = 1'b0;
        tests[0].expected = 32'h40300000;

        // 5 + 3 = 8
        tests[1].a        = 32'h40A00000;
        tests[1].b        = 32'h40400000;
        tests[1].op       = 1'b0;
        tests[1].expected = 32'h41000000;


        
        // Basic subtraction / sign selection
        // 5 - 3 = 2
        tests[2].a        = 32'h40A00000;
        tests[2].b        = 32'h40400000;
        tests[2].op       = 1'b1;
        tests[2].expected = 32'h40000000;

        // 3 - 5 = -2
        tests[3].a        = 32'h40400000;
        tests[3].b        = 32'h40A00000;
        tests[3].op       = 1'b1;
        tests[3].expected = 32'hC0000000;

        // 1.5 - 1.25 = 0.25
        tests[4].a        = 32'h3FC00000;
        tests[4].b        = 32'h3FA00000;
        tests[4].op       = 1'b1;
        tests[4].expected = 32'h3E800000;


        
        // Negative operands
        // -5 + 3 = -2
        tests[5].a        = 32'hC0A00000;
        tests[5].b        = 32'h40400000;
        tests[5].op       = 1'b0;
        tests[5].expected = 32'hC0000000;

        // -5 - 3 = -8
        tests[6].a        = 32'hC0A00000;
        tests[6].b        = 32'h40400000;
        tests[6].op       = 1'b1;
        tests[6].expected = 32'hC1000000;


        
        // Cancellation / zero
        // 5 - 5 = +0
        tests[7].a        = 32'h40A00000;
        tests[7].b        = 32'h40A00000;
        tests[7].op       = 1'b1;
        tests[7].expected = 32'h00000000;

        // 0 - 0 = +0
        tests[8].a        = 32'h00000000;
        tests[8].b        = 32'h00000000;
        tests[8].op       = 1'b1;
        tests[8].expected = 32'h00000000;


        
        // Exponent alignment
        // 1 + 0.5 = 1.5
        tests[9].a        = 32'h3F800000;
        tests[9].b        = 32'h3F000000;
        tests[9].op       = 1'b0;
        tests[9].expected = 32'h3FC00000;


        
        // Rounding behaviour
        // 1 + 2^-23 = next representable float after 1
        tests[10].a        = 32'h3F800000;
        tests[10].b        = 32'h34000000;
        tests[10].op       = 1'b0;
        tests[10].expected = 32'h3F800001;

        // 1 + 2^-24 is exactly halfway between 1.0 and next float.
        // Round-to-nearest-even should return 1.0.
        tests[11].a        = 32'h3F800000;
        tests[11].b        = 32'h33800000;
        tests[11].op       = 1'b0;
        tests[11].expected = 32'h3F800000;


        
        // Special cases
        // +inf + 1 = +inf
        tests[12].a        = 32'h7F800000;
        tests[12].b        = 32'h3F800000;
        tests[12].op       = 1'b0;
        tests[12].expected = 32'h7F800000;

        // +inf - +inf = canonical qNaN in your design
        tests[13].a        = 32'h7F800000;
        tests[13].b        = 32'h7F800000;
        tests[13].op       = 1'b1;
        tests[13].expected = 32'h7FC00000;

        
        // More special cases: infinities
        // -inf + finite = -inf
        tests[14].a        = 32'hFF800000;
        tests[14].b        = 32'h3F800000; // 1.0
        tests[14].op       = 1'b0;
        tests[14].expected = 32'hFF800000;

        // finite + -inf = -inf
        tests[15].a        = 32'h3F800000;
        tests[15].b        = 32'hFF800000;
        tests[15].op       = 1'b0;
        tests[15].expected = 32'hFF800000;

        // +inf + -inf = qNaN
        tests[16].a        = 32'h7F800000;
        tests[16].b        = 32'hFF800000;
        tests[16].op       = 1'b0;
        tests[16].expected = 32'h7FC00000;

        // -inf + +inf = qNaN
        tests[17].a        = 32'hFF800000;
        tests[17].b        = 32'h7F800000;
        tests[17].op       = 1'b0;
        tests[17].expected = 32'h7FC00000;

        // +inf - -inf = +inf
        tests[18].a        = 32'h7F800000;
        tests[18].b        = 32'hFF800000;
        tests[18].op       = 1'b1;
        tests[18].expected = 32'h7F800000;

        // -inf - +inf = -inf
        tests[19].a        = 32'hFF800000;
        tests[19].b        = 32'h7F800000;
        tests[19].op       = 1'b1;
        tests[19].expected = 32'hFF800000;


        
        // Signed zero
        // +0 + -0 = +0
        tests[20].a        = 32'h00000000;
        tests[20].b        = 32'h80000000;
        tests[20].op       = 1'b0;
        tests[20].expected = 32'h00000000;

        // -0 + -0 = -0
        tests[21].a        = 32'h80000000;
        tests[21].b        = 32'h80000000;
        tests[21].op       = 1'b0;
        tests[21].expected = 32'h80000000;

        // -0 - +0 = -0
        tests[22].a        = 32'h80000000;
        tests[22].b        = 32'h00000000;
        tests[22].op       = 1'b1;
        tests[22].expected = 32'h80000000;

        // +0 - -0 = +0
        tests[23].a        = 32'h00000000;
        tests[23].b        = 32'h80000000;
        tests[23].op       = 1'b1;
        tests[23].expected = 32'h00000000;

        // -0 - -0 = +0
        tests[24].a        = 32'h80000000;
        tests[24].b        = 32'h80000000;
        tests[24].op       = 1'b1;
        tests[24].expected = 32'h00000000;

        // -5 - (-5) = +0
        tests[25].a        = 32'hC0A00000;
        tests[25].b        = 32'hC0A00000;
        tests[25].op       = 1'b1;
        tests[25].expected = 32'h00000000;


        
        // Large exponent differences / alignment
        // 1 + 2^-30 rounds to 1
        tests[26].a        = 32'h3F800000;
        tests[26].b        = 32'h30800000;
        tests[26].op       = 1'b0;
        tests[26].expected = 32'h3F800000;

        // 1 - 2^-30 also rounds to 1
        tests[27].a        = 32'h3F800000;
        tests[27].b        = 32'h30800000;
        tests[27].op       = 1'b1;
        tests[27].expected = 32'h3F800000;


        
        // Rounding: ties, sticky, carry
        // Slightly above halfway:
        // 1 + value slightly greater than 2^-24 -> next float
        tests[28].a        = 32'h3F800000;
        tests[28].b        = 32'h33800001;
        tests[28].op       = 1'b0;
        tests[28].expected = 32'h3F800001;

        // Exact halfway, but retained LSB is odd:
        // ties-to-even therefore rounds upward
        tests[29].a        = 32'h3F800001;
        tests[29].b        = 32'h33800000;
        tests[29].op       = 1'b0;
        tests[29].expected = 32'h3F800002;

        // Rounding carry into exponent:
        // largest float below 2 + half-ULP -> 2.0
        tests[30].a        = 32'h3FFFFFFF;
        tests[30].b        = 32'h33800000;
        tests[30].op       = 1'b0;
        tests[30].expected = 32'h40000000;


        
        // Subnormals / normal-subnormal boundary
        // Smallest subnormal + smallest subnormal
        tests[31].a        = 32'h00000001;
        tests[31].b        = 32'h00000001;
        tests[31].op       = 1'b0;
        tests[31].expected = 32'h00000002;

        // Largest subnormal + smallest subnormal = smallest normal
        tests[32].a        = 32'h007FFFFF;
        tests[32].b        = 32'h00000001;
        tests[32].op       = 1'b0;
        tests[32].expected = 32'h00800000;

        // Smallest normal - smallest subnormal = largest subnormal
        tests[33].a        = 32'h00800000;
        tests[33].b        = 32'h00000001;
        tests[33].op       = 1'b1;
        tests[33].expected = 32'h007FFFFF;

        // Largest subnormal + largest subnormal
        tests[34].a        = 32'h007FFFFF;
        tests[34].b        = 32'h007FFFFF;
        tests[34].op       = 1'b0;
        tests[34].expected = 32'h00FFFFFE;


        
        // NaN handling
        // qNaN + 1 -> canonical qNaN used by this design
        tests[35].a        = 32'h7FC00000;
        tests[35].b        = 32'h3F800000;
        tests[35].op       = 1'b0;
        tests[35].expected = 32'h7FC00000;

        // 1 + qNaN -> canonical qNaN
        tests[36].a        = 32'h3F800000;
        tests[36].b        = 32'h7FC00000;
        tests[36].op       = 1'b0;
        tests[36].expected = 32'h7FC00000;


        
        // Overflow
        // max finite + max finite = +inf
        tests[37].a        = 32'h7F7FFFFF;
        tests[37].b        = 32'h7F7FFFFF;
        tests[37].op       = 1'b0;
        tests[37].expected = 32'h7F800000;

        // -max finite + -max finite = -inf
        tests[38].a        = 32'hFF7FFFFF;
        tests[38].b        = 32'hFF7FFFFF;
        tests[38].op       = 1'b0;
        tests[38].expected = 32'hFF800000;

        // max finite - (-max finite) = +inf
        tests[39].a        = 32'h7F7FFFFF;
        tests[39].b        = 32'hFF7FFFFF;
        tests[39].op       = 1'b1;
        tests[39].expected = 32'h7F800000;

    end

    integer i;
    integer passed;
    integer failed;

    initial begin
        passed = 0;
        failed = 0;
        #1;
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            a  = tests[i].a;
            b  = tests[i].b;
            op = tests[i].op;
            expected = tests[i].expected;

            #1;

            if (out === expected) begin
                passed = passed + 1;
            end
            else begin
                failed = failed + 1;
                $error(
                    "Test %0d failed: a=%h b=%h op=%b expected=%h got=%h",
                    i, a, b, op, expected, out
                );
            end
        end
        $display("Total tests: %0d", NUM_TESTS);
        $display("Tests passed: %0d", passed);
        $display("Tests failed: %0d", failed);

        $finish;
    end

endmodule

