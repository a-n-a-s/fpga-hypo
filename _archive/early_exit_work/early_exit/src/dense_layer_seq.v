`timescale 1ns/1ps

// Sequential Dense Layer - Resource Optimized (FIXED)
// Uses 1 DSP with proper inference

module dense_layer_seq #(
    parameter integer IN_SIZE = 8,
    parameter integer OUT_SIZE = 16,
    parameter integer USE_RELU = 1,
    parameter integer USE_SIGMOID = 0
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire [(IN_SIZE*16)-1:0] input_data,
    output reg                  done,
    output reg [(OUT_SIZE*16)-1:0] output_data
);

    // Weight storage in distributed RAM
    localparam MEM_SIZE = IN_SIZE * OUT_SIZE;
    reg signed [15:0] w_mem [0:MEM_SIZE-1];
    reg signed [15:0] b_mem [0:OUT_SIZE-1];

    // Datapath registers
    reg signed [31:0] acc;
    reg [7:0] out_idx;
    reg [7:0] in_idx;
    reg [7:0] state;
    reg signed [31:0] result;

    // Single multiplier with DSP inference
    (* use_dsp = "yes" *) wire signed [31:0] mult_result;
    (* use_dsp = "yes" *) reg signed [15:0] mult_input;
    (* use_dsp = "yes" *) reg signed [15:0] mult_weight;

    assign mult_result = mult_input * mult_weight;

    // FSM states
    localparam [2:0] S_IDLE   = 3'd0;
    localparam [2:0] S_INIT   = 3'd1;
    localparam [2:0] S_MAC    = 3'd2;
    localparam [2:0] S_ACT    = 3'd3;
    localparam [2:0] S_DONE   = 3'd4;

    // Load weights from .mem files
    integer i;
    initial begin
        for (i = 0; i < MEM_SIZE; i = i + 1) w_mem[i] = 16'sd0;
        for (i = 0; i < OUT_SIZE; i = i + 1) b_mem[i] = 16'sd0;

        if ((IN_SIZE == 8) && (OUT_SIZE == 16)) begin
            $readmemh("dense1_weights.mem", w_mem);
            $readmemh("dense1_bias.mem", b_mem);
        end else if ((IN_SIZE == 16) && (OUT_SIZE == 1)) begin
            $readmemh("output_weights.mem", w_mem);
            $readmemh("output_bias.mem", b_mem);
        end else if ((IN_SIZE == 8) && (OUT_SIZE == 1)) begin
            $readmemh("early_exit_weights.mem", w_mem);
            $readmemh("early_exit_bias.mem", b_mem);
        end
    end

    // Sigmoid LUT
    function automatic [15:0] sigmoid_lut;
        input [5:0] lut_idx;
        begin
            case (lut_idx)
                6'd0:  sigmoid_lut = 16'd0;   6'd1:  sigmoid_lut = 16'd0;
                6'd2:  sigmoid_lut = 16'd0;   6'd3:  sigmoid_lut = 16'd0;
                6'd4:  sigmoid_lut = 16'd1;   6'd5:  sigmoid_lut = 16'd1;
                6'd6:  sigmoid_lut = 16'd2;   6'd7:  sigmoid_lut = 16'd3;
                6'd8:  sigmoid_lut = 16'd5;   6'd9:  sigmoid_lut = 16'd8;
                6'd10: sigmoid_lut = 16'd12;  6'd11: sigmoid_lut = 16'd19;
                6'd12: sigmoid_lut = 16'd31;  6'd13: sigmoid_lut = 16'd47;
                6'd14: sigmoid_lut = 16'd69;  6'd15: sigmoid_lut = 16'd97;
                6'd16: sigmoid_lut = 16'd128; 6'd17: sigmoid_lut = 16'd159;
                6'd18: sigmoid_lut = 16'd187; 6'd19: sigmoid_lut = 16'd209;
                6'd20: sigmoid_lut = 16'd225; 6'd21: sigmoid_lut = 16'd237;
                6'd22: sigmoid_lut = 16'd244; 6'd23: sigmoid_lut = 16'd248;
                6'd24: sigmoid_lut = 16'd251; 6'd25: sigmoid_lut = 16'd253;
                6'd26: sigmoid_lut = 16'd254; 6'd27: sigmoid_lut = 16'd255;
                default: sigmoid_lut = 16'd255;
            endcase
        end
    endfunction

    function automatic signed [15:0] sigmoid_pwl;
        input signed [31:0] xin;
        integer shifted, seg_idx, frac, y0, y1, interp;
        begin
            if (xin <= -2048) sigmoid_pwl = 16'sd0;
            else if (xin >= 2048) sigmoid_pwl = 16'sd255;
            else begin
                shifted = xin + 2048;
                seg_idx = shifted >>> 7;
                frac = shifted[6:0];
                y0 = sigmoid_lut(seg_idx[5:0]);
                y1 = sigmoid_lut((seg_idx + 1) & 6'h3F);
                interp = ((y0 * (128 - frac)) + (y1 * frac)) >>> 7;
                sigmoid_pwl = interp[15:0];
            end
        end
    endfunction

    function automatic signed [15:0] sat16;
        input signed [31:0] v;
        begin
            if (v > 32767) sat16 = 16'sh7FFF;
            else if (v < -32768) sat16 = 16'sh8000;
            else sat16 = v[15:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 1'b0;
            out_idx <= 8'd0;
            in_idx <= 8'd0;
            acc <= 32'sd0;
            output_data <= {(OUT_SIZE*16){1'b0}};
            mult_input <= 16'sd0;
            mult_weight <= 16'sd0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        out_idx <= 8'd0;
                        state <= S_INIT;
                    end
                end

                S_INIT: begin
                    acc <= {b_mem[out_idx][15:0], 16'd0};
                    in_idx <= 8'd0;
                    state <= S_MAC;
                end

                S_MAC: begin
                    mult_input <= $signed(input_data[(in_idx*16) +: 16]);
                    mult_weight <= w_mem[(in_idx*OUT_SIZE) + out_idx];
                    acc <= acc + (mult_result <<< 8);
                    in_idx <= in_idx + 1;

                    if (in_idx == IN_SIZE - 1) begin
                        state <= S_ACT;
                    end
                end

                S_ACT: begin
                    result = acc >>> 16;

                    if (USE_SIGMOID != 0) begin
                        output_data[(out_idx*16) +: 16] <= sigmoid_pwl(result);
                    end else if (USE_RELU != 0) begin
                        if (result < 0)
                            output_data[(out_idx*16) +: 16] <= 16'sd0;
                        else
                            output_data[(out_idx*16) +: 16] <= sat16(result);
                    end else begin
                        output_data[(out_idx*16) +: 16] <= sat16(result);
                    end

                    if (out_idx == OUT_SIZE - 1) begin
                        state <= S_DONE;
                    end else begin
                        out_idx <= out_idx + 1;
                        state <= S_INIT;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
