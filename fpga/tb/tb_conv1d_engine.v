`timescale 1ns/1ps

module tb_conv1d_engine;
    reg clk;
    reg rst_n;
    reg start;
    reg [127:0] input_data;
    wire done;
    wire [2047:0] output_data;

    reg [7:0] test_input_mem [0:15];
    reg signed [15:0] conv_w [0:23];
    reg signed [15:0] conv_b [0:7];
    reg signed [15:0] expected [0:15][0:7];

    integer t;
    integer f;
    integer k;
    integer idx;
    integer acc;
    integer mult;
    integer err_cnt;

    conv1d_engine dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .input_data(input_data),
        .done(done),
        .output_data(output_data)
    );

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

    task compute_expected;
        begin
            for (t = 0; t < 16; t = t + 1) begin
                for (f = 0; f < 8; f = f + 1) begin
                    acc = 0;
                    for (k = 0; k < 3; k = k + 1) begin
                        idx = t + k - 1;
                        if ((idx >= 0) && (idx < 16)) begin
                            mult = $signed(input_data[(idx*8) +: 8]) * conv_w[(k*8) + f];
                            acc = acc + (mult >>> 8);
                        end
                    end
                    expected[t][f] = sat16(acc + conv_b[f]);
                end
            end
        end
    endtask

    task run_case;
        input [127:0] name;
        begin
            compute_expected();
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
                        $display("FAIL %0s: t=%0d f=%0d exp=%0d got=%0d",
                                 name, t, f, expected[t][f], output_data[(((t*8)+f)*16) +: 16]);
                    end
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

        input_data = 128'd0;
        for (t = 0; t < 16; t = t + 1) begin
            test_input_mem[t] = 8'd0;
        end

        for (k = 0; k < 24; k = k + 1) conv_w[k] = 16'sd0;
        for (k = 0; k < 8; k = k + 1) conv_b[k] = 16'sd0;

        $readmemh("conv1_weights.mem", conv_w);
        $readmemh("conv1_bias.mem", conv_b);
        $readmemh("test_input.mem", test_input_mem);

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Test case 1: from file
        for (t = 0; t < 16; t = t + 1) begin
            input_data[(t*8) +: 8] = test_input_mem[t];
        end
        run_case("test_input.mem");

        // Test case 2: ramp input
        for (t = 0; t < 16; t = t + 1) begin
            input_data[(t*8) +: 8] = 8'd80 + t;
        end
        run_case("ramp_input");

        if (err_cnt == 0) begin
            $display("tb_conv1d_engine: PASS");
        end else begin
            $display("tb_conv1d_engine: FAIL (%0d mismatches)", err_cnt);
        end
        $finish;
    end
endmodule
