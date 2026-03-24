`timescale 1ns/1ps

// Testbench for Early Exit Hypoglycemia Predictor
// Tests early exit functionality and compares with full model

module tb_hypoglycemia_predictor_early_exit;
    reg clk;
    reg rst_n;
    reg start;
    reg [127:0] glucose_in;
    wire valid;
    wire hypo_risk;
    wire [15:0] probability;
    wire busy;
    wire early_exit_used;
    wire [1:0] exit_stage;

    integer timeout;
    integer early_exit_count;
    integer full_model_count;
    integer total_tests;

    // Test input memory
    reg [7:0] test_mem [0:15];

    hypoglycemia_predictor_early_exit dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .glucose_in(glucose_in),
        .valid(valid),
        .hypo_risk(hypo_risk),
        .probability(probability),
        .busy(busy),
        .early_exit_used(early_exit_used),
        .exit_stage(exit_stage)
    );

    always #5 clk = ~clk;

    task run_test;
        input [127:0] name;
        begin
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
            end else begin
                total_tests = total_tests + 1;
                if (early_exit_used) begin
                    early_exit_count = early_exit_count + 1;
                    $display("EARLY EXIT: %0s - prob=%0d, hypo=%0b", name, probability, hypo_risk);
                end else begin
                    full_model_count = full_model_count + 1;
                    $display("FULL MODEL: %0s - prob=%0d, hypo=%0b", name, probability, hypo_risk);
                end
            end
            @(posedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        glucose_in = 128'd0;
        early_exit_count = 0;
        full_model_count = 0;
        total_tests = 0;

        // Load test input
        for (integer i = 0; i < 16; i = i + 1) test_mem[i] = 8'd0;
        $readmemh("test_input.mem", test_mem);

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("============================================================");
        $display("EARLY EXIT HYPOLYCEMIA PREDICTOR TEST");
        $display("============================================================");

        // Test 1: From test_input.mem
        for (integer i = 0; i < 16; i = i + 1) glucose_in[(i*8) +: 8] = test_mem[i];
        run_test("test_input.mem");

        // Test 2: All 80s (mid-range, might not exit early)
        for (integer i = 0; i < 16; i = i + 1) glucose_in[(i*8) +: 8] = 8'd80;
        run_test("all_80s");

        // Test 3: All 200s (high glucose, likely SAFE - should exit early)
        for (integer i = 0; i < 16; i = i + 1) glucose_in[(i*8) +: 8] = 8'd200;
        run_test("all_200s");

        // Test 4: All 50s (low glucose, likely HYPO - should exit early)
        for (integer i = 0; i < 16; i = i + 1) glucose_in[(i*8) +: 8] = 8'd50;
        run_test("all_50s");

        // Test 5: Dropping pattern (likely HYPO)
        glucose_in = {8'd40, 8'd45, 8'd50, 8'd55, 8'd60, 8'd65, 8'd70, 8'd75,
                      8'd80, 8'd85, 8'd90, 8'd95, 8'd100, 8'd105, 8'd110, 8'd115};
        run_test("dropping_pattern");

        // Test 6: Rising pattern (likely SAFE)
        glucose_in = {8'd115, 8'd110, 8'd105, 8'd100, 8'd95, 8'd90, 8'd85, 8'd80,
                      8'd75, 8'd70, 8'd65, 8'd60, 8'd55, 8'd50, 8'd45, 8'd40};
        run_test("rising_pattern");

        // Report
        $display("");
        $display("============================================================");
        $display("TEST SUMMARY");
        $display("============================================================");
        $display("Total tests: %0d", total_tests);
        $display("Early exits: %0d (%0.1f%%)", early_exit_count, 
                 (early_exit_count * 100.0) / total_tests);
        $display("Full model:  %0d (%0.1f%%)", full_model_count,
                 (full_model_count * 100.0) / total_tests);
        $display("============================================================");

        if (total_tests > 0 && early_exit_count > 0) begin
            $display("tb_hypoglycemia_predictor_early_exit: PASS");
        end else begin
            $display("tb_hypoglycemia_predictor_early_exit: FAIL");
        end

        $finish;
    end
endmodule
