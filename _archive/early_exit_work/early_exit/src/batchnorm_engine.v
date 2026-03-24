module batchnorm_engine (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,
    input  wire [2047:0]     input_data,
    output reg               done,
    output reg [2047:0]      output_data
);

    localparam signed [15:0] EPSILON_Q8_8 = 16'sd1; // ~0.0039

    reg signed [15:0] gamma [0:7];
    reg signed [15:0] beta  [0:7];
    reg signed [15:0] mean  [0:7];
    reg signed [15:0] var   [0:7];
    reg signed [15:0] scale [0:7];
    reg signed [15:0] shift [0:7];

    integer t;
    integer f;
    integer temp;
    integer var_eps;
    integer sqrt_q8_8;
    integer inv_sqrt_q8_8;
    integer i;

    function automatic [15:0] isqrt32;
        input [31:0] x;
        reg [31:0] op;
        reg [31:0] res;
        reg [31:0] one;
        begin
            op = x;
            res = 0;
            one = 32'h40000000;

            while (one > op) begin
                one = one >> 2;
            end

            while (one != 0) begin
                if (op >= (res + one)) begin
                    op = op - (res + one);
                    res = res + (one << 1);
                end
                res = res >> 1;
                one = one >> 2;
            end
            isqrt32 = res[15:0];
        end
    endfunction

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
        for (i = 0; i < 8; i = i + 1) begin
            gamma[i] = 16'sd0;
            beta[i]  = 16'sd0;
            mean[i]  = 16'sd0;
            var[i]   = 16'sd1;
            scale[i] = 16'sd256;
            shift[i] = 16'sd0;
        end

        $readmemh("bn1_gamma.mem", gamma);
        $readmemh("bn1_beta.mem", beta);
        $readmemh("bn1_mean.mem", mean);
        $readmemh("bn1_variance.mem", var);

        for (i = 0; i < 8; i = i + 1) begin
            var_eps = var[i] + EPSILON_Q8_8;
            if (var_eps <= 0) begin
                var_eps = 1;
            end

            // sqrt(Q8.8) in Q8.8: sqrt(var_q * 256).
            sqrt_q8_8 = isqrt32(var_eps <<< 8);
            if (sqrt_q8_8 == 0) begin
                sqrt_q8_8 = 1;
            end

            // inv_sqrt in Q8.8 = 65536 / sqrt_q8_8.
            inv_sqrt_q8_8 = 65536 / sqrt_q8_8;
            scale[i] = sat16((gamma[i] * inv_sqrt_q8_8) >>> 8);
            shift[i] = sat16(beta[i] - ((mean[i] * scale[i]) >>> 8));
        end
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
                        // y = x * scale + shift, all in Q8.8.
                        temp = (($signed(input_data[(((t*8)+f)*16) +: 16]) * scale[f]) >>> 8) + shift[f];
                        output_data[(((t*8)+f)*16) +: 16] <= sat16(temp);
                    end
                end
                done <= 1'b1;
            end
        end
    end

endmodule
