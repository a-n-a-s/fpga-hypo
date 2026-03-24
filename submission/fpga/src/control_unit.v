module control_unit (
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
    output reg  busy
);

    localparam [3:0] IDLE      = 4'd0;
    localparam [3:0] LOAD      = 4'd1;
    localparam [3:0] CONV      = 4'd2;
    localparam [3:0] BATCHNORM = 4'd3;
    localparam [3:0] POOL      = 4'd4;
    localparam [3:0] DENSE1    = 4'd5;
    localparam [3:0] DENSE2    = 4'd6;
    localparam [3:0] OUTPUT    = 4'd7;

    reg [3:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
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

            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy       <= 1'b1;
                        load_input <= 1'b1;
                        state      <= LOAD;
                    end
                end

                LOAD: begin
                    conv_start <= 1'b1;
                    state      <= CONV;
                end

                CONV: begin
                    if (conv_done) begin
                        bn_start <= 1'b1;
                        state    <= BATCHNORM;
                    end
                end

                BATCHNORM: begin
                    if (bn_done) begin
                        pool_start <= 1'b1;
                        state      <= POOL;
                    end
                end

                POOL: begin
                    if (pool_done) begin
                        dense1_start <= 1'b1;
                        state        <= DENSE1;
                    end
                end

                DENSE1: begin
                    if (dense1_done) begin
                        dense2_start <= 1'b1;
                        state        <= DENSE2;
                    end
                end

                DENSE2: begin
                    if (dense2_done) begin
                        state <= OUTPUT;
                    end
                end

                OUTPUT: begin
                    output_valid <= 1'b1;
                    busy         <= 1'b0;
                    state        <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
