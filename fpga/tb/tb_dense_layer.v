`timescale 1ns/1ps

module tb_dense_layer;
    reg clk;
    reg rst_n;
    reg start1;
    reg start2;

    reg [127:0] in_dense1;
    wire done1;
    wire [255:0] out_dense1;

    wire done2;
    wire [15:0] out_dense2;

    reg signed [15:0] dense1_w [0:127];
    reg signed [15:0] dense1_b [0:15];
    reg signed [15:0] out_w    [0:127];
    reg signed [15:0] out_b    [0:15];

    reg signed [15:0] exp_dense1 [0:15];
    reg signed [15:0] exp_dense2;

    integer i;
    integer o;
    integer acc;
    integer x;
    integer idx;
    integer err_cnt;

    dense_layer #(
        .IN_SIZE(8),
        .OUT_SIZE(16),
        .USE_RELU(1),
        .USE_SIGMOID(0)
    ) dut_dense1 (
        .clk(clk),
        .rst_n(rst_n),
        .start(start1),
        .input_data(in_dense1),
        .done(done1),
        .output_data(out_dense1)
    );

    dense_layer #(
        .IN_SIZE(16),
        .OUT_SIZE(1),
        .USE_RELU(0),
        .USE_SIGMOID(1)
    ) dut_dense2 (
        .clk(clk),
        .rst_n(rst_n),
        .start(start2),
        .input_data(out_dense1),
        .done(done2),
        .output_data(out_dense2)
    );

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
                shifted = xin + 2048;
                seg_idx = shifted >>> 7;
                frac = shifted[6:0];
                y0 = sigmoid_lut(seg_idx[5:0]);
                y1 = sigmoid_lut((seg_idx + 1) & 6'h3F);
                interp = ((y0 * (128 - frac)) + (y1 * frac)) >>> 7;
                sigmoid_pwl = sat16(interp);
            end
        end
    endfunction

    task compute_dense1_expected;
        begin
            for (o = 0; o < 16; o = o + 1) begin
                acc = dense1_b[o];
                for (i = 0; i < 8; i = i + 1) begin
                    idx = (i * 16) + o;
                    x = $signed(in_dense1[(i*16) +: 16]) * dense1_w[idx];
                    acc = acc + (x >>> 8);
                end
                if (acc < 0) exp_dense1[o] = 16'sd0;
                else exp_dense1[o] = sat16(acc);
            end
        end
    endtask

    task compute_dense2_expected;
        begin
            acc = out_b[0];
            for (i = 0; i < 16; i = i + 1) begin
                x = exp_dense1[i] * out_w[i];
                acc = acc + (x >>> 8);
            end
            exp_dense2 = sigmoid_pwl(acc);
        end
    endtask

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start1 = 1'b0;
        start2 = 1'b0;
        err_cnt = 0;

        for (i = 0; i < 128; i = i + 1) begin
            dense1_w[i] = 16'sd0;
            out_w[i] = 16'sd0;
        end
        for (i = 0; i < 16; i = i + 1) begin
            dense1_b[i] = 16'sd0;
            out_b[i] = 16'sd0;
        end

        $readmemh("dense1_weights.mem", dense1_w);
        $readmemh("dense1_bias.mem", dense1_b);
        $readmemh("output_weights.mem", out_w);
        $readmemh("output_bias.mem", out_b);

        // Initialize input
        in_dense1 = 128'd0;
        for (i = 0; i < 8; i = i + 1) begin
            in_dense1[(i*16) +: 16] = (i * 24) - 40;
        end
        compute_dense1_expected();
        compute_dense2_expected();

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Test dense1
        @(negedge clk);
        start1 = 1'b1;
        @(negedge clk);
        start1 = 1'b0;
        wait(done1 == 1'b1);
        @(posedge clk);

        for (o = 0; o < 16; o = o + 1) begin
            if (out_dense1[(o*16) +: 16] !== exp_dense1[o]) begin
                err_cnt = err_cnt + 1;
                $display("FAIL dense1: o=%0d exp=%0d got=%0d", o, exp_dense1[o], out_dense1[(o*16) +: 16]);
            end
        end

        // Test dense2
        @(negedge clk);
        start2 = 1'b1;
        @(negedge clk);
        start2 = 1'b0;
        wait(done2 == 1'b1);
        @(posedge clk);

        if (out_dense2 !== exp_dense2) begin
            err_cnt = err_cnt + 1;
            $display("FAIL dense2: exp=%0d got=%0d", exp_dense2, out_dense2);
        end

        if (err_cnt == 0) begin
            $display("tb_dense_layer: PASS");
        end else begin
            $display("tb_dense_layer: FAIL (%0d mismatches)", err_cnt);
        end
        $finish;
    end
endmodule
