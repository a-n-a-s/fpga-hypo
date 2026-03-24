module input_buffer (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       load,
    input  wire [127:0] glucose_in,
    output reg  [127:0] glucose_out
);

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            glucose_out <= 128'd0;
        end else if (load) begin
            for (i = 0; i < 16; i = i + 1) begin
                glucose_out[(i*8) +: 8] <= glucose_in[(i*8) +: 8];
            end
        end
    end

endmodule
