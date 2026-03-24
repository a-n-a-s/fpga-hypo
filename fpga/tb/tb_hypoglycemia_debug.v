`timescale 1ns/1ps

module tb_hypoglycemia_predictor_debug;
    reg clk;
    reg rst_n;
    reg start;
    reg [127:0] glucose_in;
    wire valid;
    wire hypo_risk;
    wire [15:0] probability;
    wire busy;
    wire [2:0] current_state;

    integer timeout;

    hypoglycemia_predictor_opt dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .glucose_in(glucose_in),
        .valid(valid),
        .hypo_risk(hypo_risk),
        .probability(probability),
        .busy(busy),
        .current_state(current_state)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        glucose_in = 128'd0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Simple test: all 80s (should give reasonable output)
        $display("=== Test: All 80s input ===");
        for (integer i = 0; i < 16; i = i + 1) begin
            glucose_in[(i*8) +: 8] = 8'd80;
        end
        
        $display("Input: All 80s");
        $display("Starting inference at time %0t", $time);
        
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        
        timeout = 0;
        while ((valid !== 1'b1) && (timeout < 5000)) begin
            timeout = timeout + 1;
            @(posedge clk);
        end
        
        if (valid !== 1'b1) begin
            $display("TIMEOUT: valid not asserted after %0d cycles", timeout);
        end else begin
            $display("DONE at time %0t", $time);
            $display("Probability: %0d (0x%0h)", probability, probability);
            $display("Hypo Risk: %0b", hypo_risk);
            $display("Classification: %s", (hypo_risk ? "HYPO" : "SAFE"));
            
            // Expected: probability around 150-200 for mid-range input
            if (probability > 100 && probability < 255) begin
                $display("RESULT: Reasonable output ✓");
            end else if (probability == 0) begin
                $display("RESULT: ERROR - Output is 0 (likely bug) ✗");
            end else begin
                $display("RESULT: Unexpected but non-zero ✓");
            end
        end
        
        $finish;
    end
endmodule
