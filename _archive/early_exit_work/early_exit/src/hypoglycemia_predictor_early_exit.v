`timescale 1ns/1ps

// Hypoglycemia Predictor with Early Exit
// 
// Architecture:
// Input → Conv1D → BatchNorm → Pool → GAP → Dense1 → [Early Exit] → Dense2 → Output
//                                                     ↓
//                                    Exit if confident (saves latency)
//
// Outputs:
//   - valid: Output data valid
//   - hypo_risk: Binary classification (1 = HYPO, 0 = SAFE)
//   - probability: Raw probability (Q8.8)
//   - early_exit_used: 1 if early exit was taken
//   - exit_stage: 1 = exited after Dense1, 2 = went through Dense2

module hypoglycemia_predictor_early_exit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [127:0] glucose_in,
    output reg         valid,
    output reg         hypo_risk,
    output reg [15:0]  probability,
    output wire        busy,
    output wire        early_exit_used,
    output wire [1:0]  exit_stage
);

    // Control signals
    wire load_input;
    wire conv_start;
    wire bn_start;
    wire pool_start;
    wire dense1_start;
    wire dense2_start;
    wire output_valid;

    wire conv_done;
    wire bn_done;
    wire pool_done;
    wire dense1_done;
    wire dense2_done;
    wire early_exit_done;

    // Data signals
    wire [127:0] input_data;
    wire [2047:0] conv_data;
    wire [2047:0] bn_data;
    wire [127:0] pool_data;
    wire [255:0] dense1_data;
    wire [15:0] dense2_data;
    wire [15:0] early_exit_prob;
    wire early_exit_valid;
    wire early_hypo_risk;
    wire hypo_risk_w;

    // Control Unit with early exit support
    control_unit_early_exit u_control (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .conv_done(conv_done),
        .bn_done(bn_done),
        .pool_done(pool_done),
        .dense1_done(dense1_done),
        .dense2_done(dense2_done),
        .early_exit_valid(early_exit_valid),
        .load_input(load_input),
        .conv_start(conv_start),
        .bn_start(bn_start),
        .pool_start(pool_start),
        .dense1_start(dense1_start),
        .dense2_start(dense2_start),
        .output_valid(output_valid),
        .busy(busy)
    );

    // Input Buffer
    input_buffer u_input_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .load(load_input),
        .glucose_in(glucose_in),
        .glucose_out(input_data)
    );

    // Conv1D Engine
    conv1d_engine u_conv1d (
        .clk(clk),
        .rst_n(rst_n),
        .start(conv_start),
        .input_data(input_data),
        .done(conv_done),
        .output_data(conv_data)
    );

    // BatchNorm Engine
    batchnorm_engine u_batchnorm (
        .clk(clk),
        .rst_n(rst_n),
        .start(bn_start),
        .input_data(conv_data),
        .done(bn_done),
        .output_data(bn_data)
    );

    // Pooling Engine
    pooling_engine u_pool (
        .clk(clk),
        .rst_n(rst_n),
        .start(pool_start),
        .input_data(bn_data),
        .done(pool_done),
        .output_data(pool_data)
    );

    // Dense Layer 1 (8→16, ReLU)
    dense_layer #(
        .IN_SIZE(8),
        .OUT_SIZE(16),
        .USE_RELU(1),
        .USE_SIGMOID(0)
    ) u_dense1 (
        .clk(clk),
        .rst_n(rst_n),
        .start(dense1_start),
        .input_data(pool_data),
        .done(dense1_done),
        .output_data(dense1_data)
    );

    // Early Exit Dense Layer (8→1, Sigmoid)
    // Runs in parallel with Dense1
    early_exit_dense u_early_exit_dense (
        .clk(clk),
        .rst_n(rst_n),
        .start(dense1_start),  // Start with Dense1
        .input_data(pool_data),  // 8×16 = 128 bits (GAP output)
        .done(early_exit_done),
        .output_data(early_exit_prob)
    );

    // Early Exit Comparator
    early_exit_comparator u_early_exit_cmp (
        .early_probability(early_exit_prob),
        .high_thresh(16'h00CD),  // 0.8 = 205
        .low_thresh(16'h0033),   // 0.2 = 51
        .early_exit_valid(early_exit_valid),
        .early_hypo_risk(early_hypo_risk)
    );

    // Dense Layer 2 (16→1, Sigmoid) - only if not exiting early
    dense_layer #(
        .IN_SIZE(16),
        .OUT_SIZE(1),
        .USE_RELU(0),
        .USE_SIGMOID(1)
    ) u_dense2 (
        .clk(clk),
        .rst_n(rst_n),
        .start(dense2_start),
        .input_data(dense1_data),
        .done(dense2_done),
        .output_data(dense2_data)
    );

    // Output Comparator (for final output)
    output_comparator u_cmp (
        .probability(dense2_data),
        .hypo_risk(hypo_risk_w)
    );

    // Output Register with Early Exit MUX
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid         <= 1'b0;
            probability   <= 16'h0000;
            hypo_risk     <= 1'b0;
        end else begin
            valid <= output_valid;
            if (output_valid) begin
                if (early_exit_valid) begin
                    // Early exit was taken
                    probability <= early_exit_prob;
                    hypo_risk   <= early_hypo_risk;
                end else begin
                    // Full model was used
                    probability <= dense2_data;
                    hypo_risk   <= hypo_risk_w;
                end
            end
        end
    end

    // Early exit status outputs
    assign early_exit_used = early_exit_valid;
    assign exit_stage = early_exit_valid ? 2'd1 : 2'd2;

endmodule
