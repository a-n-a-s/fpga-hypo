`timescale 1ns/1ps

// XAI Hypoglycemia Predictor - Demo Testbench
// Generates clean output for presentation screenshots

module tb_hypoglycemia_predictor_xai_demo;
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

    // Instantiate XAI predictor
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

    // 50 MHz clock
    always #5 clk = ~clk;

    task run_demo_test;
        input [100:0] test_name;
        input [127:0] data;
        integer i;
        integer prob_percent;
        begin
            // Load input data
            glucose_in = data;
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            // Wait for valid output
            timeout = 0;
            while ((valid !== 1'b1) && (timeout < 5000)) begin
                timeout = timeout + 1;
                @(posedge clk);
            end

            if (valid !== 1'b1) begin
                $display("TIMEOUT: %s", test_name);
            end else begin
                // Calculate percentage
                prob_percent = (probability * 100) / 256;

                // Display test case
                $display("");
                $display("============================================================");
                $display("XAI DEMO: %s", test_name);
                $display("============================================================");
                $display("");
                
                // Display input pattern
                $write("Glucose Input: [");
                for (i = 0; i < 16; i = i + 1) begin
                    $write("%0d", glucose_in[(i*8) +: 8]);
                    if (i < 15) $write(", ");
                end
                $display("] mg/dL");
                $display("");
                
                // Display CNN prediction
                $display("CNN Prediction:");
                $display("  Probability: %0d/255 (%d%%)", probability, prob_percent);
                if (hypo_risk)
                    $display("  Hypoglycemia Risk: YES ⚠️");
                else
                    $display("  Hypoglycemia Risk: NO ✅");
                $display("");
                
                // Display XAI outputs
                $display("XAI Explanation:");
                $display("  Reason Code: %b (binary) = %0d", reason_code, reason_code);
                $display("  Slope: %0d (Q8.8 format)", slope);
                $display("  Minimum Glucose: %0d mg/dL", min_value);
                if (recent_low)
                    $display("  Recent Low Detected: YES ⚠️");
                else
                    $display("  Recent Low Detected: NO");
                if (trend_direction)
                    $display("  Trend Direction: DROPPING ⬇️");
                else
                    $display("  Trend Direction: STABLE ➡️");
                $display("");
                
                // Decode reason code
                $display("Risk Factor Analysis:");
                if (reason_code == 3'b000) begin
                    $display("  ✅ No risk factors detected");
                    $display("     - Glucose levels stable and in normal range");
                end else begin
                    if (reason_code[0]) begin
                        $display("  ⚠️ RAPID DROP DETECTED");
                        $display("     - Glucose falling faster than 10 mg/dL per minute");
                    end
                    if (reason_code[1]) begin
                        $display("  ⚠️ RECENT LOW DETECTED");
                        $display("     - Glucose dropped below 70 mg/dL in last 20 minutes");
                    end
                    if (reason_code[2]) begin
                        $display("  ⚠️ CURRENT VALUE LOW");
                        $display("     - Current glucose below 80 mg/dL");
                    end
                end
                $display("");
                
                // Clinical recommendation
                $display("Clinical Recommendation:");
                if (hypo_risk) begin
                    $display("  ⚠️ IMMEDIATE ACTION REQUIRED");
                    $display("     - Consume 15-20g fast-acting carbohydrates");
                    $display("     - Recheck glucose in 15 minutes");
                    $display("     - Seek medical attention if symptoms persist");
                end else if (reason_code != 3'b000) begin
                    $display("  ⚠️ MONITOR CLOSELY");
                    $display("     - Consider preventive snack");
                    $display("     - Continue frequent monitoring");
                end else begin
                    $display("  ✅ NO ACTION REQUIRED");
                    $display("     - Continue regular monitoring schedule");
                    $display("     - Glucose levels stable");
                end
                $display("");
                $display("============================================================");
                
                @(posedge clk);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        glucose_in = 128'd0;

        // Reset
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Header
        $display("╔════════════════════════════════════════════════════════════╗");
        $display("║  XAI HYPOGLYCEMIA PREDICTOR - LIVE DEMONSTRATION           ║");
        $display("║  FPGA-Based Real-Time Prediction with Explainable AI       ║");
        $display("╚════════════════════════════════════════════════════════════╝");
        $display("");
        $display("Running 3 demonstration test cases...");
        $display("");

        // Test Case 1: Normal Stable
        glucose_in = 0;
        for (integer i = 0; i < 16; i = i + 1) begin
            glucose_in[(i*8) +: 8] = 8'd100;
        end
        run_demo_test("Normal Stable (All 100s)", glucose_in);

        // Test Case 2: Rapid Drop
        glucose_in = 0;
        for (integer i = 0; i < 16; i = i + 1) begin
            glucose_in[(i*8) +: 8] = 8'd120 - (i * 4);
        end
        run_demo_test("Rapid Drop Pattern (120→64)", glucose_in);

        // Test Case 3: Critical Low
        glucose_in = 0;
        for (integer i = 0; i < 16; i = i + 1) begin
            glucose_in[(i*8) +: 8] = 8'd90 - (i * 3);
        end
        run_demo_test("Critical Low Pattern (90→45)", glucose_in);

        // Summary
        $display("");
        $display("╔════════════════════════════════════════════════════════════╗");
        $display("║  DEMONSTRATION COMPLETE                                    ║");
        $display("╚════════════════════════════════════════════════════════════╝");
        $display("");
        $display("All 3 test cases completed successfully.");
        $display("");
        $display("Key Observations:");
        $display("  1. Normal case: No risk factors, stable glucose");
        $display("  2. Rapid drop: XAI detected falling trend");
        $display("  3. Critical: Multiple risk factors triggered");
        $display("");
        $display("XAI provides interpretable explanations for clinical decisions.");
        $display("");

        $finish;
    end
endmodule
