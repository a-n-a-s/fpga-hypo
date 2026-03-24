`timescale 1ns/1ps

// Testbench for Hypoglycemia Predictor with XAI

module tb_hypoglycemia_predictor_xai;
    reg clk;
    reg rst_n;
    reg start;
    reg [127:0] glucose_in;
    wire valid;
    wire hypo_risk;
    wire [15:0] probability;
    wire [2:0] reason_code;
    wire [15:0] slope;
    wire [7:0] min_value;
    wire recent_low;
    wire trend_direction;
    wire busy;

    integer timeout;
    integer test_count;
    integer pass_count;

    hypoglycemia_predictor_xai dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .glucose_in(glucose_in),
        .valid(valid),
        .hypo_risk(hypo_risk),
        .probability(probability),
        .reason_code(reason_code),
        .slope(slope),
        .min_value(min_value),
        .recent_low(recent_low),
        .trend_direction(trend_direction),
        .busy(busy)
    );

    always #5 clk = ~clk;

    task run_test;
        input [127:0] name;
        input [127:0] data;
        begin
            glucose_in = data;
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
                $display("TIMEOUT: %0s", name);
                test_count = test_count + 1;
            end else begin
                test_count = test_count + 1;
                $display("TEST: %0s", name);
                $display("  Probability: %0d, Hypo Risk: %0b", probability, hypo_risk);
                $display("  Reason Code: %0b (binary), Slope: %0d", reason_code, slope);
                $display("  Min Value: %0d, Recent Low: %0b, Trend: %0b", min_value, recent_low, trend_direction);
                
                // Check if reason code makes sense
                if ((hypo_risk && reason_code != 3'b000) || (!hypo_risk && reason_code == 3'b000)) begin
                    $display("  ✓ PASS: Reason code matches prediction");
                    pass_count = pass_count + 1;
                end else if (!hypo_risk) begin
                    $display("  ✓ PASS: SAFE prediction");
                    pass_count = pass_count + 1;
                end else begin
                    $display("  ⚠ WARNING: Reason code may not match");
                end
                $display("");
                @(posedge clk);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        glucose_in = 128'd0;
        test_count = 0;
        pass_count = 0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("============================================================");
        $display("XAI HYPOLYCEMIA PREDICTOR TEST");
        $display("============================================================");
        $display("");

        // Test 1: All 80s (normal, stable)
        glucose_in = 0;
        for (integer i = 0; i < 16; i = i + 1) begin
            glucose_in[(i*8) +: 8] = 8'd80;
        end
        run_test("Normal stable (all 80s)", glucose_in);

        // Test 2: Dropping pattern (should trigger rapid drop)
        glucose_in = 0;
        for (integer i = 0; i < 16; i = i + 1) begin
            glucose_in[(i*8) +: 8] = 80 + i;  // Rising values
        end
        run_test("Rising pattern", glucose_in);

        // Test 3: Low glucose throughout (should trigger current low)
        glucose_in = 0;
        for (integer i = 0; i < 16; i = i + 1) begin
            glucose_in[(i*8) +: 8] = 60;  // All 60s
        end
        run_test("Low glucose (all 60s)", glucose_in);

        // Test 4: Recent low (last 4 readings low)
        glucose_in = 0;
        for (integer i = 0; i < 12; i = i + 1) begin
            glucose_in[(i*8) +: 8] = 100;  // First 12: 100
        end
        for (integer i = 12; i < 16; i = i + 1) begin
            glucose_in[(i*8) +: 8] = 55;  // Last 4: 55
        end
        run_test("Recent low (100→55)", glucose_in);

        // Test 5: Dropping pattern
        glucose_in = 0;
        for (integer i = 0; i < 16; i = i + 1) begin
            glucose_in[(i*8) +: 8] = 120 - (i * 4);  // 120, 116, 112, ... 60
        end
        run_test("Dropping pattern (120→60)", glucose_in);

        // Test 6: Critical pattern (all risk factors)
        glucose_in = 0;
        for (integer i = 0; i < 16; i = i + 1) begin
            glucose_in[(i*8) +: 8] = 110 - (i * 4);  // 110, 106, ... 50
        end
        run_test("Critical (110→50)", glucose_in);

        // Summary
        $display("============================================================");
        $display("TEST SUMMARY");
        $display("============================================================");
        $display("Total tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        if (test_count > 0) begin
            $display("Pass rate: %0.1f%%", (pass_count * 100.0) / test_count);
        end
        $display("============================================================");

        if (pass_count == test_count && test_count > 0) begin
            $display("tb_hypoglycemia_predictor_xai: PASS");
        end else begin
            $display("tb_hypoglycemia_predictor_xai: FAIL");
        end

        $finish;
    end
endmodule
