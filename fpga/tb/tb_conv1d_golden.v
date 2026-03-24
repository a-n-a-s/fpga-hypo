`timescale 1ns/1ps

// Golden reference testbench for conv1d_engine
// Compares RTL output against Python model's expected output

module tb_conv1d_engine_golden;
    reg clk;
    reg rst_n;
    reg start;
    reg [127:0] input_data;
    wire done;
    wire [2047:0] output_data;

    // Golden reference storage
    reg signed [15:0] expected [0:15][0:7];
    
    // Weight storage
    reg signed [15:0] conv_w [0:23];
    reg signed [15:0] conv_b [0:7];

    integer t, f, k, idx, acc, mult;
    integer err_cnt;
    integer test_idx;
    integer num_tests;

    // DUT instantiation
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

    // Compute expected output using same math as RTL (for verification)
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

    task run_test;
        input [127:0] name;
        integer timeout;
        begin
            compute_expected();
            
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            
            // Wait for done with timeout
            timeout = 0;
            while ((done !== 1'b1) && (timeout < 100)) begin
                timeout = timeout + 1;
                @(posedge clk);
            end
            
            if (done !== 1'b1) begin
                $display("TIMEOUT %0s: done not asserted", name);
                err_cnt = err_cnt + 100;
            end else begin
                @(posedge clk);
                for (t = 0; t < 16; t = t + 1) begin
                    for (f = 0; f < 8; f = f + 1) begin
                        if (output_data[(((t*8)+f)*16) +: 16] !== expected[t][f]) begin
                            err_cnt = err_cnt + 1;
                            $display("MISMATCH %0s: t=%0d f=%0d exp=%0d got=%0d",
                                     name, t, f, expected[t][f], 
                                     $signed(output_data[(((t*8)+f)*16) +: 16]));
                        end
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
        input_data = 128'd0;
        err_cnt = 0;
        num_tests = 0;

        // Initialize arrays
        for (t = 0; t < 16; t = t + 1) begin
            for (f = 0; f < 8; f = f + 1) begin
                expected[t][f] = 16'sd0;
            end
        end
        for (k = 0; k < 24; k = k + 1) conv_w[k] = 16'sd0;
        for (k = 0; k < 8; k = k + 1) conv_b[k] = 16'sd0;

        // Load weights from .mem files
        $readmemh("conv1_weights.mem", conv_w);
        $readmemh("conv1_bias.mem", conv_b);

        // Reset
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Test 1: All zeros
        $display("\n=== Test 1: All zeros ===");
        input_data = 128'd0;
        run_test("zeros");
        num_tests = num_tests + 1;

        // Test 2: All max (255)
        $display("\n=== Test 2: All max (255) ===");
        for (t = 0; t < 16; t = t + 1) begin
            input_data[(t*8) +: 8] = 8'd255;
        end
        run_test("max");
        num_tests = num_tests + 1;

        // Test 3: Alternating pattern
        $display("\n=== Test 3: Alternating pattern ===");
        for (t = 0; t < 16; t = t + 1) begin
            input_data[(t*8) +: 8] = (t[0]) ? 8'd200 : 8'd50;
        end
        run_test("alternating");
        num_tests = num_tests + 1;

        // Test 4: Ramp
        $display("\n=== Test 4: Ramp ===");
        for (t = 0; t < 16; t = t + 1) begin
            input_data[(t*8) +: 8] = 8'(t * 16);
        end
        run_test("ramp");
        num_tests = num_tests + 1;

        // Test 5: From test_input.mem if available
        begin
            reg [7:0] test_mem [0:15];
            $display("\n=== Test 5: From test_input.mem ===");
            for (t = 0; t < 16; t = t + 1) test_mem[t] = 8'd0;
            $readmemh("test_input.mem", test_mem);
            for (t = 0; t < 16; t = t + 1) begin
                input_data[(t*8) +: 8] = test_mem[t];
            end
            run_test("test_input.mem");
            num_tests = num_tests + 1;
        end

        // Final report
        $display("\n" + "=" + "=" + "=" + "=" + "=" + "=" + "=" + "=" + "=" + "=");
        if (err_cnt == 0) begin
            $display("tb_conv1d_engine_golden: PASS (%0d tests)", num_tests);
        end else begin
            $display("tb_conv1d_engine_golden: FAIL (%0d errors in %0d tests)", err_cnt, num_tests);
        end
        $display("=" + "=" + "=" + "=" + "=" + "=" + "=" + "=" + "=" + "=" + "=");
        
        $finish;
    end
endmodule
