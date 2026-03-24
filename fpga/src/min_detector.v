`timescale 1ns/1ps

// Minimum Detector for XAI
// Finds minimum glucose value and its position in 16-timestep window

module min_detector (
    input  wire [127:0] glucose_in,  // 16 × 8-bit glucose values
    output reg [7:0] min_value,      // Minimum glucose value
    output reg [3:0] min_index,      // Timestep where minimum occurred (0-15)
    output reg recent_low            // 1 if min in last 4 readings < 70
);

    integer i;
    reg [7:0] current_min;
    reg [3:0] current_index;
    
    always @(*) begin
        // Initialize with first value
        current_min = glucose_in[7:0];
        current_index = 4'd0;
        
        // Find minimum value and its index
        for (i = 1; i < 16; i = i + 1) begin
            if (glucose_in[(i*8) +: 8] < current_min) begin
                current_min = glucose_in[(i*8) +: 8];
                current_index = i[3:0];
            end
        end
        
        min_value = current_min;
        min_index = current_index;
        
        // Check if minimum occurred in last 4 readings (20 minutes)
        // and if it's below 70 mg/dL
        if ((current_index >= 12) && (current_min < 70)) begin
            recent_low = 1'b1;
        end else begin
            recent_low = 1'b0;
        end
    end

endmodule
