module conv1d_engine (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,
    input  wire [127:0]      input_data,
    output reg               done,
    output reg [2047:0]      output_data
);

    reg signed [15:0] conv_w [0:23];
    reg signed [15:0] conv_b [0:7];

    integer t;
    integer f;
    integer k;
    integer idx;
    integer acc;
    integer mult;

    function automatic signed [15:0] sat16;
        input signed [31:0] x;
        begin
            if (x > 32767)
                sat16 = 16'sh7FFF;
            else if (x < -32768)
                sat16 = 16'sh8000;
            else
                sat16 = x[15:0];
        end
    endfunction

    initial begin
        for (k = 0; k < 24; k = k + 1) begin
            conv_w[k] = 16'sd0;
        end
        for (k = 0; k < 8; k = k + 1) begin
            conv_b[k] = 16'sd0;
        end
        $readmemh("conv1_weights.mem", conv_w);
        $readmemh("conv1_bias.mem", conv_b);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 1'b0;
            output_data <= 2048'd0;
        end else begin
            done <= 1'b0;
            if (start) begin
                for (t = 0; t < 16; t = t + 1) begin
                    for (f = 0; f < 8; f = f + 1) begin
                        acc = 0;
                        for (k = 0; k < 3; k = k + 1) begin
                            idx = t + k - 1;
                            if ((idx >= 0) && (idx < 16)) begin
                                // Q8.8 * Q8.8 -> Q16.16, then normalize back to Q8.8.
                                mult = $signed({8'd0, input_data[(idx*8) +: 8]}) * $signed(conv_w[(k*8) + f]);
                                acc = acc + (mult >>> 8);
                            end
                        end
                        output_data[(((t*8)+f)*16) +: 16] <= $signed(sat16(acc + $signed(conv_b[f])));
                    end
                end
                done <= 1'b1;
            end
        end
    end

endmodule
