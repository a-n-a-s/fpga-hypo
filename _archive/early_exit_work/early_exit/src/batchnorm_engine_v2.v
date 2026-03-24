`timescale 1ns/1ps

module batchnorm_engine_v2 (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,
    input  wire [2047:0]     input_data,
    output reg               done,
    output reg [2047:0]      output_data
);

    // Pre-computed scale and shift parameters (Q8.8 format)
    // Loaded from .mem files - no runtime computation
    (* rom_style = "block" *) reg signed [15:0] scale [0:7];
    (* rom_style = "block" *) reg signed [15:0] shift [0:7];

    integer t;
    integer f;
    integer temp;

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
    initial begin
        for (f = 0; f < 8; f = f + 1) begin
            scale[f] = 16'sd256;  // Default: 1.0
            shift[f] = 16'sd0;    // Default: 0.0
        end
        $readmemh("bn1_scale.mem", scale);
        $readmemh("bn1_shift.mem", shift);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 1'b0;
            output_data <= 2048'd0;
        end else begin
            done <= 1'b0;
            if (start) begin
                for (t = 0; t < 16; t = t + 1) begin
                    for (f = 0; f < 8; f = f + 1) begin
                        // y = x * scale + shift (all Q8.8)
                        temp = (($signed(input_data[(((t*8)+f)*16) +: 16]) * scale[f]) >>> 8) + shift[f];
                        output_data[(((t*8)+f)*16) +: 16] <= sat16(temp);
                    end
                end
                done <= 1'b1;
            end
        end
    end

endmodule
