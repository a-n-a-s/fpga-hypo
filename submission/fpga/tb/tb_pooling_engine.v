`timescale 1ns/1ps

module tb_pooling_engine;
    reg clk;
    reg rst_n;
    reg start;
    reg [2047:0] input_data;
    wire done;
    wire [127:0] output_data;

    reg signed [15:0] expected [0:7];

    integer f;
    integer t;
    integer a;
    integer b;
    integer m;
    integer sum;
    integer err_cnt;

    pooling_engine dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .input_data(input_data),
        .done(done),
        .output_data(output_data)
    );

    task compute_expected;
        begin
            for (f = 0; f < 8; f = f + 1) begin
                sum = 0;
                for (t = 0; t < 8; t = t + 1) begin
                    a = $signed(input_data[(((2*t*8)+f)*16) +: 16]);
                    b = $signed(input_data[(((2*t+1)*8+f)*16) +: 16]);
                    if (a > b) m = a;
                    else m = b;
                    sum = sum + m;
                end
                expected[f] = (sum >>> 3);
            end
        end
    endtask

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        err_cnt = 0;

        // Initialize input with test pattern
        input_data = 2048'd0;
        for (t = 0; t < 16; t = t + 1) begin
            for (f = 0; f < 8; f = f + 1) begin
                if (t[0] == 1'b0)
                    input_data[(((t*8)+f)*16) +: 16] = (f * 20) + t;
                else
                    input_data[(((t*8)+f)*16) +: 16] = (f * 20) - t;
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

        for (f = 0; f < 8; f = f + 1) begin
            if (output_data[(f*16) +: 16] !== expected[f]) begin
                err_cnt = err_cnt + 1;
                $display("FAIL: f=%0d exp=%0d got=%0d", f, expected[f], output_data[(f*16) +: 16]);
            end
        end

        if (err_cnt == 0) begin
            $display("tb_pooling_engine: PASS");
        end else begin
            $display("tb_pooling_engine: FAIL (%0d mismatches)", err_cnt);
        end
        $finish;
    end
endmodule
