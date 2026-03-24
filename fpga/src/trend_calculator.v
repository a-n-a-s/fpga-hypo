`timescale 1ns/1ps

// Trend Calculator for XAI
// Calculates glucose slope (trend) over 16 timesteps
// Output: slope in Q8.8 format (mg/dL per 5 min)

module trend_calculator (
    input  wire [127:0] glucose_in,  // 16 × 8-bit glucose values
    output reg [15:0] slope,         // Slope in Q8.8 format
    output reg trend_direction       // 0=stable/rising, 1=dropping
);

    integer i;
    reg signed [15:0] first_avg;
    reg signed [15:0] last_avg;
    reg signed [15:0] diff;
    
    // Calculate slope as (last_5_avg - first_5_avg)
    // Positive = rising, Negative = dropping
    
    always @(*) begin
        // Calculate average of first 5 readings
        first_avg = 0;
        for (i = 0; i < 5; i = i + 1) begin
            first_avg = first_avg + {8'd0, glucose_in[(i*8) +: 8]};
        end
        first_avg = first_avg / 5;
        
        // Calculate average of last 5 readings
        last_avg = 0;
        for (i = 11; i < 16; i = i + 1) begin
            last_avg = last_avg + {8'd0, glucose_in[(i*8) +: 8]};
        end
        last_avg = last_avg / 5;
        
        // Calculate difference (slope)
        diff = last_avg - first_avg;
        
        // Convert to Q8.8 format (multiply by 256)
        slope = diff <<< 8;
        
        // Set trend direction
        if (diff < -10) begin
            trend_direction = 1'b1;  // Dropping rapidly
        end else begin
            trend_direction = 1'b0;  // Stable or rising
        end
    end

endmodule
