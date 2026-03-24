`timescale 1ns/1ps

// Rate of Change Calculator for XAI
// Calculates glucose rate of change in mg/dL per minute

module rate_of_change (
    input  wire [127:0] glucose_in,  // 16 × 8-bit glucose values (80 minutes)
    output reg [15:0] rate,          // Rate in Q8.8 format (mg/dL per minute)
    output reg rapid_drop            // 1 if rate < -10 mg/dL/min
);

    reg signed [15:0] first_value;
    reg signed [15:0] last_value;
    reg signed [15:0] diff;
    
    // Calculate rate as (last - first) / 80 minutes
    // Simplified: just use difference scaled appropriately
    
    always @(*) begin
        first_value = {8'd0, glucose_in[7:0]};
        last_value = {8'd0, glucose_in[127:120]};
        
        // Calculate difference
        diff = last_value - first_value;
        
        // Convert to rate per minute (divide by 80, then scale to Q8.8)
        // Simplified: diff * 256 / 80 = diff * 3.2 ≈ diff * 3
        rate = (diff * 3) <<< 1;  // Approximate division by 80
        
        // Check for rapid drop (< -10 mg/dL/min)
        // In Q8.8, -10 = -2560
        if (rate < -10'd2560) begin
            rapid_drop = 1'b1;
        end else begin
            rapid_drop = 1'b0;
        end
    end

endmodule
