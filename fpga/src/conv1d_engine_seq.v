`timescale 1ns/1ps

// Sequential Conv1D Engine - Icarus-Compatible Version
// Uses 1 DSP

module conv1d_engine_seq (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,
    input  wire [127:0]      input_data,
    output reg               done,
    output reg [2047:0]      output_data
);

    // Weights
    reg signed [15:0] conv_w [0:23];
    reg signed [15:0] conv_b [0:7];

    // Counters
    reg [4:0] t;
    reg [2:0] f;
    reg [1:0] k;
    reg [5:0] idx;

    // Accumulator
    reg signed [31:0] acc;
    reg signed [31:0] result_temp;

    // Multiplier
    (* use_dsp = "yes" *) wire signed [31:0] mult_out;
    (* use_dsp = "yes" *) reg signed [15:0] mult_a;
    (* use_dsp = "yes" *) reg signed [15:0] mult_b;
    assign mult_out = mult_a * mult_b;

    // Weight initialization
    initial begin
        $readmemh("conv1_weights.mem", conv_w);
        $readmemh("conv1_bias.mem", conv_b);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 1'b0;
            t <= 0;
            f <= 0;
            k <= 0;
            idx <= 0;
            acc <= 0;
            output_data <= 0;
            mult_a <= 0;
            mult_b <= 0;
            result_temp <= 0;
        end else begin
            done <= 1'b0;
            
            // Compute index
            idx <= t + k - 1;
            
            if (start) begin
                t <= 0;
                f <= 0;
                k <= 0;
                acc <= 0;
            end else begin
                // Multiply
                if ((idx >= 0) && (idx < 16)) begin
                    mult_a <= {24'd0, input_data[(idx*8) +: 8]};
                    mult_b <= conv_w[(k*8) + f];
                    acc <= acc + (mult_out >>> 8);
                end

                // Advance kernel
                if (k == 2) begin
                    // Store result
                    result_temp <= acc + conv_b[f];
                    if (result_temp > 32767)
                        result_temp <= 32767;
                    else if (result_temp < -32768)
                        result_temp <= -32768;
                    output_data[(((t*8)+f)*16) +: 16] <= result_temp[15:0];

                    // Advance
                    if (f == 7) begin
                        if (t == 15) begin
                            done <= 1'b1;
                        end else begin
                            t <= t + 1;
                        end
                        f <= 0;
                    end else begin
                        f <= f + 1;
                    end
                    k <= 0;
                    acc <= 0;
                end else begin
                    k <= k + 1;
                end
            end
        end
    end

endmodule
