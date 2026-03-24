`timescale 1ns/1ps

// Reason Encoder for XAI
// Encodes 3-bit reason code based on glucose features

module reason_encoder (
    input  wire [15:0] slope,         // From trend_calculator (Q8.8)
    input  wire [7:0] min_value,      // From min_detector
    input  wire [7:0] current_value,  // Current glucose (last reading)
    input  wire rapid_drop,           // From rate_of_change
    input  wire recent_low,           // From min_detector
    output reg [2:0] reason_code      // 3-bit reason code
);

    // Reason code encoding:
    // Bit 0: Rapid drop detected (slope < -10 mg/dL/min OR rapid_drop flag)
    // Bit 1: Recent low detected (min in last 20 min < 70 mg/dL)
    // Bit 2: Current value low (current < 80 mg/dL)
    
    wire rapid_drop_flag;
    
    // Check if slope indicates rapid drop (< -10 mg/dL/min)
    // In Q8.8, -10 = -2560
    assign rapid_drop_flag = (slope < -10'd2560) || rapid_drop;
    
    always @(*) begin
        reason_code[0] = rapid_drop_flag;     // Bit 0: Rapid drop
        reason_code[1] = recent_low;           // Bit 1: Recent low
        reason_code[2] = (current_value < 80); // Bit 2: Current low
    end

endmodule
