`timescale 1ns/1ps

// Golden reference testbench for conv1d_engine
// Dumps RTL outputs for comparison with Python model

module tb_conv1d_engine_golden;
    reg clk;
    reg rst_n;
    reg start;
    reg [127:0] input_data;
    wire done;
    wire [2047:0] output_data;

    // Weight storage
    reg signed [15:0] conv_w [0:23];
    reg signed [15:0] conv_b [0:7];

    // Test memory
    reg [7:0] test_mem [0:15];

    // For capturing output
    integer t, f, k, i;
    integer err_cnt;
    integer test_num;
    integer timeout;

    // DUT instantiation
    conv1d_engine_seq dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .input_data(input_data),
        .done(done),
        .output_data(output_data)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        input_data = 128'd0;
        err_cnt = 0;
        test_num = 0;
        t = 0; f = 0; k = 0; i = 0;
        timeout = 0;

        // Initialize arrays
        for (i = 0; i < 16; i = i + 1) begin
            test_mem[i] = 8'd0;
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

        $display("=== RTL CONV1D OUTPUT DUMP ===");
        $display("Format: TEST[name] output[t][f]=value");
        $display("");

        // Test 1: From test_input.mem (matches Python golden vector #0)
        for (i = 0; i < 16; i = i + 1) test_mem[i] = 8'd0;
        $readmemh("test_input.mem", test_mem);
        for (i = 0; i < 16; i = i + 1) begin
            input_data[(i*8) +: 8] = test_mem[i];
        end
        
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        
        timeout = 0;
        while ((done !== 1'b1) && (timeout < 100)) begin
            timeout = timeout + 1;
            @(posedge clk);
        end
        
        if (done !== 1'b1) begin
            $display("TIMEOUT test_input_mem");
        end else begin
            @(posedge clk);
            for (t = 0; t < 16; t = t + 1) begin
                for (f = 0; f < 8; f = f + 1) begin
                    $display("TEST[test_input_mem] output[%0d][%0d]=%0d", 
                             t, f, $signed(output_data[(((t*8)+f)*16) +: 16]));
                end
            end
        end
        test_num = test_num + 1;

        // Test 2: All zeros
        input_data = 128'd0;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        
        timeout = 0;
        while ((done !== 1'b1) && (timeout < 100)) begin
            timeout = timeout + 1;
            @(posedge clk);
        end
        
        @(posedge clk);
        for (t = 0; t < 16; t = t + 1) begin
            for (f = 0; f < 8; f = f + 1) begin
                $display("TEST[zeros] output[%0d][%0d]=%0d", 
                         t, f, $signed(output_data[(((t*8)+f)*16) +: 16]));
            end
        end
        test_num = test_num + 1;

        // Test 3: All max (255)
        for (t = 0; t < 16; t = t + 1) begin
            input_data[(t*8) +: 8] = 8'd255;
        end
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        
        timeout = 0;
        while ((done !== 1'b1) && (timeout < 100)) begin
            timeout = timeout + 1;
            @(posedge clk);
        end
        
        @(posedge clk);
        for (t = 0; t < 16; t = t + 1) begin
            for (f = 0; f < 8; f = f + 1) begin
                $display("TEST[max] output[%0d][%0d]=%0d", 
                         t, f, $signed(output_data[(((t*8)+f)*16) +: 16]));
            end
        end
        test_num = test_num + 1;

        // Test 4: Ramp
        for (t = 0; t < 16; t = t + 1) begin
            input_data[(t*8) +: 8] = t * 16;
        end
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        
        timeout = 0;
        while ((done !== 1'b1) && (timeout < 100)) begin
            timeout = timeout + 1;
            @(posedge clk);
        end
        
        @(posedge clk);
        for (t = 0; t < 16; t = t + 1) begin
            for (f = 0; f < 8; f = f + 1) begin
                $display("TEST[ramp] output[%0d][%0d]=%0d", 
                         t, f, $signed(output_data[(((t*8)+f)*16) +: 16]));
            end
        end
        test_num = test_num + 1;

        $display("");
        $display("=== END RTL OUTPUT (%0d tests) ===", test_num);
        
        $finish;
    end
endmodule
