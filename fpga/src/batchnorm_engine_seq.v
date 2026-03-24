`timescale 1ns/1ps

// Sequential BatchNorm Engine - Resource Optimized
// Uses 1 DSP instead of 86+ parallel multipliers
// Latency: 16 × 8 = 128 cycles

module batchnorm_engine_seq (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,
    input  wire [2047:0]     input_data,  // 16 × 8 × 16-bit
    output reg               done,
    output reg [2047:0]      output_data
);

    // Pre-computed scale and shift parameters (Q8.8 format)
    reg signed [15:0] scale [0:7];
    reg signed [15:0] shift [0:7];

    // Datapath registers
    reg signed [31:0] temp;
    reg [4:0] t_idx;                // Timestep counter (0-15)
    reg [2:0] f_idx;                // Filter counter (0-7)
    reg [7:0] state;

    // Single multiplier with DSP inference
    (* use_dsp = "yes" *) wire signed [31:0] mult_result;
    (* use_dsp = "yes" *) reg signed [15:0] mult_input;
    (* use_dsp = "yes" *) reg signed [15:0] mult_scale;

    assign mult_result = mult_input * mult_scale;

    function automatic signed [15:0] sat16;
        input signed [31:0] x;
        begin
            if (x > 32767)
                sat16 = 16'sh7FFF;
            else if (x < -32768)
                sat16 = 16'sh8000;
            else
                sat16 = x[15:0];
        end
    endfunction

    // Load pre-computed scale and shift values
    integer i;
    initial begin
        for (i = 0; i < 8; i = i + 1) begin
            scale[i] = 16'sd256;  // Default: 1.0
            shift[i] = 16'sd0;    // Default: 0.0
        end
        $readmemh("bn1_scale.mem", scale);
        $readmemh("bn1_shift.mem", shift);
    end

    // FSM states
    localparam [2:0] S_IDLE   = 3'd0;
    localparam [2:0] S_COMPUTE = 3'd1;
    localparam [2:0] S_STORE  = 3'd2;
    localparam [2:0] S_DONE   = 3'd3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 1'b0;
            t_idx <= 5'd0;
            f_idx <= 3'd0;
            output_data <= 2048'd0;
            mult_input <= 16'sd0;
            mult_scale <= 16'sd0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        t_idx <= 5'd0;
                        f_idx <= 3'd0;
                        state <= S_COMPUTE;
                    end
                end

                S_COMPUTE: begin
                    // Set multiplier inputs
                    mult_input <= $signed(input_data[(((t_idx*8)+f_idx)*16) +: 16]);
                    mult_scale <= scale[f_idx];
                    
                    // Compute and store result next cycle
                    temp <= (mult_result >>> 8) + shift[f_idx];
                    state <= S_STORE;
                end

                S_STORE: begin
                    output_data[(((t_idx*8)+f_idx)*16) +: 16] <= sat16(temp[15:0]);
                    
                    // Move to next element
                    if (f_idx == 3'd7) begin
                        if (t_idx == 5'd15) begin
                            state <= S_DONE;
                        end else begin
                            t_idx <= t_idx + 1;
                            f_idx <= 3'd0;
                            state <= S_COMPUTE;
                        end
                    end else begin
                        f_idx <= f_idx + 1;
                        state <= S_COMPUTE;
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
