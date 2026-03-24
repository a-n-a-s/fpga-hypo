module activation_unit (
    input  wire signed [15:0] input_data,
    input  wire               use_sigmoid,
    output wire signed [15:0] output_data
);

    reg signed [15:0] y;
    integer tmp;

    always @(*) begin
        if (use_sigmoid) begin
            if (input_data <= -16'sd1024) begin
                y = 16'sd0;
            end else if (input_data >= 16'sd1024) begin
                y = 16'sd255;
            end else begin
                tmp = 128 + (input_data >>> 3);
                if (tmp < 0)
                    tmp = 0;
                if (tmp > 255)
                    tmp = 255;
                y = tmp[15:0];
            end
        end else begin
            if (input_data[15])
                y = 16'sd0;
            else
                y = input_data;
        end
    end

    assign output_data = y;

endmodule
