`timescale 1ns/1ps

// Hypoglycemia Predictor with XAI (Explainable AI)
// Combines CNN prediction with interpretable explanations
//
// Outputs:
//   - hypo_risk: Binary classification (1 = HYPO, 0 = SAFE)
//   - probability: Raw probability (Q8.8)
//   - reason_code: 3-bit XAI explanation
//   - slope: Glucose trend (Q8.8)
//   - min_value: Minimum glucose in window
//   - recent_low: Flag for recent low glucose

module hypoglycemia_predictor_xai (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [127:0] glucose_in,
    output reg         valid,
    output reg         hypo_risk,
    output reg [15:0]  probability,
    output wire [2:0]   reason_code,      // XAI: 3-bit reason code
    output wire [15:0]  slope,            // XAI: Glucose trend
    output wire [7:0]   min_value,        // XAI: Minimum glucose
    output wire         recent_low,       // XAI: Recent low flag
    output wire         trend_direction,  // XAI: 0=stable, 1=dropping
    output wire        busy
);

    // CNN module wires
    wire cnn_valid;
    wire cnn_hypo_risk;
    wire [15:0] cnn_probability;
    wire cnn_busy;

    // XAI module wires
    wire xai_rapid_drop;
    wire [2:0] xai_reason_code;
    
    // CNN Predictor (baseline)
    hypoglycemia_predictor_opt u_cnn (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .glucose_in(glucose_in),
        .valid(cnn_valid),
        .hypo_risk(cnn_hypo_risk),
        .probability(cnn_probability),
        .busy(cnn_busy)
    );

    // XAI Modules (combinational - run in parallel with CNN)
    trend_calculator u_trend (
        .glucose_in(glucose_in),
        .slope(slope),
        .trend_direction(trend_direction)
    );

    min_detector u_min (
        .glucose_in(glucose_in),
        .min_value(min_value),
        .min_index(),  // Not exposed at top level
        .recent_low(recent_low)
    );

    rate_of_change u_rate (
        .glucose_in(glucose_in),
        .rate(),  // Internal use only
        .rapid_drop(xai_rapid_drop)
    );

    reason_encoder u_reason (
        .slope(slope),
        .min_value(min_value),
        .current_value(glucose_in[127:120]),  // Last reading
        .rapid_drop(xai_rapid_drop),
        .recent_low(recent_low),
        .reason_code(xai_reason_code)
    );
    
    // Assign reason_code from XAI
    assign reason_code = xai_reason_code;

    // Output register (synchronize CNN output with XAI)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid       <= 1'b0;
            probability <= 16'h0000;
            hypo_risk   <= 1'b0;
        end else begin
            valid <= cnn_valid;
            if (cnn_valid) begin
                probability <= cnn_probability;
                hypo_risk   <= cnn_hypo_risk;
            end
        end
    end

    // Busy signal from CNN
    assign busy = cnn_busy;

endmodule
