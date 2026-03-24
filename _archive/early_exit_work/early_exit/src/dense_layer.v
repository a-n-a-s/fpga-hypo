module dense_layer #(
    parameter integer IN_SIZE = 8,
    parameter integer OUT_SIZE = 16,
    parameter integer USE_RELU = 1,
    parameter integer USE_SIGMOID = 0
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire [(IN_SIZE*16)-1:0] input_data,
    output reg                done,
    output reg [(OUT_SIZE*16)-1:0] output_data
);

    reg signed [15:0] w_mem [0:127];
    reg signed [15:0] b_mem [0:15];

    integer o;
    integer i;
    integer acc;
    integer x;
    integer idx;

    function automatic signed [15:0] sat16;
        input signed [31:0] v;
        begin
            if (v > 32767)
                sat16 = 16'sh7FFF;
            else if (v < -32768)
                sat16 = 16'sh8000;
            else
                sat16 = v[15:0];
        end
    endfunction

    function automatic [15:0] sigmoid_lut;
        input [5:0] lut_idx;
        begin
            case (lut_idx)
                6'd0:  sigmoid_lut = 16'd0;
                6'd1:  sigmoid_lut = 16'd0;
                6'd2:  sigmoid_lut = 16'd0;
                6'd3:  sigmoid_lut = 16'd0;
                6'd4:  sigmoid_lut = 16'd1;
                6'd5:  sigmoid_lut = 16'd1;
                6'd6:  sigmoid_lut = 16'd2;
                6'd7:  sigmoid_lut = 16'd3;
                6'd8:  sigmoid_lut = 16'd5;
                6'd9:  sigmoid_lut = 16'd8;
                6'd10: sigmoid_lut = 16'd12;
                6'd11: sigmoid_lut = 16'd19;
                6'd12: sigmoid_lut = 16'd31;
                6'd13: sigmoid_lut = 16'd47;
                6'd14: sigmoid_lut = 16'd69;
                6'd15: sigmoid_lut = 16'd97;
                6'd16: sigmoid_lut = 16'd128;
                6'd17: sigmoid_lut = 16'd159;
                6'd18: sigmoid_lut = 16'd187;
                6'd19: sigmoid_lut = 16'd209;
                6'd20: sigmoid_lut = 16'd225;
                6'd21: sigmoid_lut = 16'd237;
                6'd22: sigmoid_lut = 16'd244;
                6'd23: sigmoid_lut = 16'd248;
                6'd24: sigmoid_lut = 16'd251;
                6'd25: sigmoid_lut = 16'd253;
                6'd26: sigmoid_lut = 16'd254;
                6'd27: sigmoid_lut = 16'd255;
                6'd28: sigmoid_lut = 16'd255;
                6'd29: sigmoid_lut = 16'd255;
                6'd30: sigmoid_lut = 16'd255;
                6'd31: sigmoid_lut = 16'd255;
                default: sigmoid_lut = 16'd255;
            endcase
        end
    endfunction

    function automatic signed [15:0] sigmoid_pwl;
        input signed [31:0] xin;
        integer shifted;
        integer seg_idx;
        integer frac;
        integer y0;
        integer y1;
        integer interp;
        begin
            if (xin <= -2048) begin
                sigmoid_pwl = 16'sd0;
            end else if (xin >= 2048) begin
                sigmoid_pwl = 16'sd255;
            end else begin
                shifted = xin + 2048;            // 0..4095
                seg_idx = shifted >>> 7;         // 0..31 segment index
                frac = shifted[6:0];             // interpolation fraction
                y0 = sigmoid_lut(seg_idx[5:0]);
                y1 = sigmoid_lut((seg_idx + 1) & 6'h3F);
                interp = ((y0 * (128 - frac)) + (y1 * frac)) >>> 7;
                sigmoid_pwl = sat16(interp);
            end
        end
    endfunction

    initial begin
        for (i = 0; i < 128; i = i + 1) begin
            w_mem[i] = 16'sd0;
        end
        for (i = 0; i < 16; i = i + 1) begin
            b_mem[i] = 16'sd0;
        end

        if ((IN_SIZE == 8) && (OUT_SIZE == 16)) begin
            $readmemh("dense1_weights.mem", w_mem);
            $readmemh("dense1_bias.mem", b_mem);
        end else if ((IN_SIZE == 16) && (OUT_SIZE == 1)) begin
            $readmemh("output_weights.mem", w_mem);
            $readmemh("output_bias.mem", b_mem);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 1'b0;
            output_data <= {(OUT_SIZE*16){1'b0}};
        end else begin
            done <= 1'b0;
            if (start) begin
                for (o = 0; o < OUT_SIZE; o = o + 1) begin
                    acc = b_mem[o];
                    for (i = 0; i < IN_SIZE; i = i + 1) begin
                        idx = (i * OUT_SIZE) + o;
                        x = $signed(input_data[(i*16) +: 16]) * w_mem[idx];
                        acc = acc + (x >>> 8);
                    end

                    if (USE_SIGMOID != 0) begin
                        output_data[(o*16) +: 16] <= sigmoid_pwl(acc);
                    end else if (USE_RELU != 0) begin
                        if (acc < 0)
                            output_data[(o*16) +: 16] <= 16'sd0;
                        else
                            output_data[(o*16) +: 16] <= sat16(acc);
                    end else begin
                        output_data[(o*16) +: 16] <= sat16(acc);
                    end
                end
                done <= 1'b1;
            end
        end
    end

endmodule
