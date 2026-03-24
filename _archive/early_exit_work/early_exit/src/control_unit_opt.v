`timescale 1ns/1ps

// Control Unit for Optimized Hypoglycemia Predictor
// Handles multi-cycle sequential modules

module control_unit_opt (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire conv_done,
    input  wire bn_done,
    input  wire pool_done,
    input  wire dense1_done,
    input  wire dense2_done,
    output reg  load_input,
    output reg  conv_start,
    output reg  bn_start,
    output reg  pool_start,
    output reg  dense1_start,
    output reg  dense2_start,
    output reg  output_valid,
    output reg  busy,
    // Debug state output
    output reg [2:0] current_state
);

    localparam [2:0] S_IDLE      = 3'd0;
    localparam [2:0] S_LOAD      = 3'd1;
    localparam [2:0] S_CONV      = 3'd2;
    localparam [2:0] S_BN        = 3'd3;
    localparam [2:0] S_POOL      = 3'd4;
    localparam [2:0] S_DENSE1    = 3'd5;
    localparam [2:0] S_DENSE2    = 3'd6;
    localparam [2:0] S_OUTPUT    = 3'd7;

    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            current_state <= S_IDLE;
            load_input   <= 1'b0;
            conv_start   <= 1'b0;
            bn_start     <= 1'b0;
            pool_start   <= 1'b0;
            dense1_start <= 1'b0;
            dense2_start <= 1'b0;
            output_valid <= 1'b0;
            busy         <= 1'b0;
        end else begin
            load_input   <= 1'b0;
            conv_start   <= 1'b0;
            bn_start     <= 1'b0;
            pool_start   <= 1'b0;
            dense1_start <= 1'b0;
            dense2_start <= 1'b0;
            output_valid <= 1'b0;
            current_state <= state;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy       <= 1'b1;
                        load_input <= 1'b1;
                        state      <= S_LOAD;
                    end
                end

                S_LOAD: begin
                    conv_start <= 1'b1;
                    state      <= S_CONV;
                end

                S_CONV: begin
                    if (conv_done) begin
                        bn_start <= 1'b1;
                        state    <= S_BN;
                    end
                end

                S_BN: begin
                    if (bn_done) begin
                        pool_start <= 1'b1;
                        state      <= S_POOL;
                    end
                end

                S_POOL: begin
                    if (pool_done) begin
                        dense1_start <= 1'b1;
                        state        <= S_DENSE1;
                    end
                end

                S_DENSE1: begin
                    if (dense1_done) begin
                        dense2_start <= 1'b1;
                        state        <= S_DENSE2;
                    end
                end

                S_DENSE2: begin
                    if (dense2_done) begin
                        state <= S_OUTPUT;
                    end
                end

                S_OUTPUT: begin
                    output_valid <= 1'b1;
                    busy         <= 1'b0;
                    state        <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
