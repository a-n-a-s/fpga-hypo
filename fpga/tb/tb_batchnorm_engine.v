`timescale 1ns/1ps

module tb_batchnorm_engine;
    reg clk;
    reg rst_n;
    reg start;
    reg [2047:0] input_data;
    wire done;
    wire [2047:0] output_data;

    reg signed [15:0] gamma [0:7];
    reg signed [15:0] beta  [0:7];
    reg signed [15:0] mean  [0:7];
    reg signed [15:0] var   [0:7];
    reg signed [15:0] scale [0:7];
    reg signed [15:0] shift [0:7];
    reg signed [15:0] expected [0:15][0:7];

    integer t;
    integer f;
    integer i;
    integer temp;
    integer var_eps;
    integer sqrt_q8_8;
    integer inv_sqrt_q8_8;
    integer err_cnt;

    localparam signed [15:0] EPSILON_Q8_8 = 16'sd1;

    batchnorm_engine dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .input_data(input_data),
        .done(done),
        .output_data(output_data)
    );

    function automatic [15:0] isqrt32;
        input [31:0] x;
        reg [31:0] op;
        reg [31:0] res;
        reg [31:0] one;
        begin
            op = x;
            res = 0;
            one = 32'h40000000;
            while (one > op) one = one >> 2;
            while (one != 0) begin
                if (op >= (res + one)) begin
                    op = op - (res + one);
                    res = res + (one << 1);
                end
                res = res >> 1;
                one = one >> 2;
            end
            isqrt32 = res[15:0];
        end
    endfunction

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

    task compute_scale_shift;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                var_eps = var[i] + EPSILON_Q8_8;
                if (var_eps <= 0) var_eps = 1;
                sqrt_q8_8 = isqrt32(var_eps <<< 8);
                if (sqrt_q8_8 == 0) sqrt_q8_8 = 1;
                inv_sqrt_q8_8 = 65536 / sqrt_q8_8;
                scale[i] = sat16((gamma[i] * inv_sqrt_q8_8) >>> 8);
                shift[i] = sat16(beta[i] - ((mean[i] * scale[i]) >>> 8));
            end
        end
    endtask

    task compute_expected;
        begin
            for (t = 0; t < 16; t = t + 1) begin
                for (f = 0; f < 8; f = f + 1) begin
                    temp = (($signed(input_data[(((t*8)+f)*16) +: 16]) * scale[f]) >>> 8) + shift[f];
                    expected[t][f] = sat16(temp);
                end
            end
        end
    endtask

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        err_cnt = 0;

        $readmemh("bn1_gamma.mem", gamma);
        $readmemh("bn1_beta.mem", beta);
        $readmemh("bn1_mean.mem", mean);
        $readmemh("bn1_variance.mem", var);
        compute_scale_shift();

        // Initialize input with test pattern
        input_data = 2048'd0;
        for (t = 0; t < 16; t = t + 1) begin
            for (f = 0; f < 8; f = f + 1) begin
                input_data[(((t*8)+f)*16) +: 16] = (t * 16) - (f * 9);
            end
        end
        compute_expected();

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        wait(done == 1'b1);
        @(posedge clk);

        for (t = 0; t < 16; t = t + 1) begin
            for (f = 0; f < 8; f = f + 1) begin
                if (output_data[(((t*8)+f)*16) +: 16] !== expected[t][f]) begin
                    err_cnt = err_cnt + 1;
                    $display("FAIL: t=%0d f=%0d exp=%0d got=%0d",
                             t, f, expected[t][f], output_data[(((t*8)+f)*16) +: 16]);
                end
            end
        end

        if (err_cnt == 0) begin
            $display("tb_batchnorm_engine: PASS");
        end else begin
            $display("tb_batchnorm_engine: FAIL (%0d mismatches)", err_cnt);
        end
        $finish;
    end
endmodule
