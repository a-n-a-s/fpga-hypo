`timescale 1ns/1ps

// Debug testbench to check weight loading

module tb_conv1d_debug;
    reg clk;
    reg rst_n;
    reg start;
    reg [127:0] input_data;
    wire done;
    wire [2047:0] output_data;

    // Weight storage - use packed array
    wire signed [15:0] conv_w [0:23];
    wire signed [15:0] conv_b [0:7];

    integer k;

    // DUT instantiation
    conv1d_engine dut (
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

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        
        // Wait and dump weights
        repeat (10) @(posedge clk);
        
        $display("=== WEIGHT DUMP ===");
        for (k = 0; k < 24; k = k + 1) begin
            $display("conv_w[%0d] = %0d (0x%04h)", k, dut.conv_w[k], dut.conv_w[k]);
        end
        $display("");
        for (k = 0; k < 8; k = k + 1) begin
            $display("conv_b[%0d] = %0d (0x%04h)", k, dut.conv_b[k], dut.conv_b[k]);
        end
        $display("");
        
        // Set input and trigger
        input_data = 128'h3870033D0039367100340039376D003A;  // test_input.mem values
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        
        wait(done == 1'b1);
        @(posedge clk);
        
        $display("=== OUTPUT DUMP ===");
        for (k = 0; k < 8; k = k + 1) begin
            $display("output[0][%0d] = %0d", k, $signed(output_data[(k*16) +: 16]));
        end
        
        $finish;
    end
endmodule
