`timescale 1ns/1ps

// Early Exit Comparator Module
// Determines if prediction is confident enough to exit early
//
// Exit conditions:
//   - Exit if probability >= HIGH_THRESH (confident HYPO)
//   - Exit if probability <= LOW_THRESH (confident SAFE)
//   - Otherwise, continue to Dense2

module early_exit_comparator (
    input  wire [15:0] early_probability,  // Q8.8 from early exit dense
    input  wire [15:0] high_thresh,         // High confidence threshold (default: 0.8 = 205 = 0x00CD)
    input  wire [15:0] low_thresh,          // Low confidence threshold (default: 0.2 = 51 = 0x0033)
    output wire early_exit_valid,           // 1 = can exit early
    output wire early_hypo_risk             // Early exit classification result
);

    // High confidence HYPO: prob >= 0.8
    wire confident_hypo = (early_probability >= high_thresh);
    
    // High confidence SAFE: prob <= 0.2
    wire confident_safe = (early_probability <= low_thresh);
    
    // Exit if confident in either direction
    assign early_exit_valid = confident_hypo || confident_safe;
    
    // Classification if exiting early
    // If confident_hypo, output 1 (HYPO)
    // If confident_safe, output 0 (SAFE)
    assign early_hypo_risk = confident_hypo ? 1'b1 : 1'b0;

endmodule
