module pooling_engine (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,
    input  wire [2047:0]     input_data,
    output reg               done,
    output reg [127:0]       output_data
);

    integer f;
    integer t;
    integer a;
    integer b;
    integer m;
    integer sum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 1'b0;
            output_data <= 128'd0;
        end else begin
            done <= 1'b0;
            if (start) begin
                for (f = 0; f < 8; f = f + 1) begin
                    sum = 0;
                    for (t = 0; t < 8; t = t + 1) begin
                        a = $signed(input_data[((((2*t)*8)+f)*16) +: 16]);
                        b = $signed(input_data[((((2*t+1)*8)+f)*16) +: 16]);
                        if (a > b)
                            m = a;
                        else
                            m = b;
                        sum = sum + m;
                    end
                    output_data[(f*16) +: 16] <= (sum >>> 3);
                end
                done <= 1'b1;
            end
        end
    end

endmodule
