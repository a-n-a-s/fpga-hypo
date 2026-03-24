module hypoglycemia_predictor (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [127:0] glucose_in,
    output reg         valid,
    output reg         hypo_risk,
    output reg [15:0]  probability,
    output wire        busy
);

    wire load_input;
    wire conv_start;
    wire bn_start;
    wire pool_start;
    wire dense1_start;
    wire dense2_start;
    wire output_valid;

    wire conv_done;
    wire bn_done;
    wire pool_done;
    wire dense1_done;
    wire dense2_done;

    wire [127:0] input_data;
    wire [2047:0] conv_data;
    wire [2047:0] bn_data;
    wire [127:0] pool_data;
    wire [255:0] dense1_data;
    wire [15:0] dense2_data;
    wire hypo_risk_w;

    control_unit u_control (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .conv_done(conv_done),
        .bn_done(bn_done),
        .pool_done(pool_done),
        .dense1_done(dense1_done),
        .dense2_done(dense2_done),
        .load_input(load_input),
        .conv_start(conv_start),
        .bn_start(bn_start),
        .pool_start(pool_start),
        .dense1_start(dense1_start),
        .dense2_start(dense2_start),
        .output_valid(output_valid),
        .busy(busy)
    );

    input_buffer u_input_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .load(load_input),
        .glucose_in(glucose_in),
        .glucose_out(input_data)
    );

    conv1d_engine u_conv1d (
        .clk(clk),
        .rst_n(rst_n),
        .start(conv_start),
        .input_data(input_data),
        .done(conv_done),
        .output_data(conv_data)
    );

    batchnorm_engine u_batchnorm (
        .clk(clk),
        .rst_n(rst_n),
        .start(bn_start),
        .input_data(conv_data),
        .done(bn_done),
        .output_data(bn_data)
    );

    pooling_engine u_pool (
        .clk(clk),
        .rst_n(rst_n),
        .start(pool_start),
        .input_data(bn_data),
        .done(pool_done),
        .output_data(pool_data)
    );

    dense_layer #(
        .IN_SIZE(8),
        .OUT_SIZE(16),
        .USE_RELU(1),
        .USE_SIGMOID(0)
    ) u_dense1 (
        .clk(clk),
        .rst_n(rst_n),
        .start(dense1_start),
        .input_data(pool_data),
        .done(dense1_done),
        .output_data(dense1_data)
    );

    dense_layer #(
        .IN_SIZE(16),
        .OUT_SIZE(1),
        .USE_RELU(0),
        .USE_SIGMOID(1)
    ) u_dense2 (
        .clk(clk),
        .rst_n(rst_n),
        .start(dense2_start),
        .input_data(dense1_data),
        .done(dense2_done),
        .output_data(dense2_data)
    );

    output_comparator u_cmp (
        .probability(dense2_data),
        .hypo_risk(hypo_risk_w)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid       <= 1'b0;
            probability <= 16'h0000;
            hypo_risk   <= 1'b0;
        end else begin
            valid <= output_valid;
            if (output_valid) begin
                probability <= dense2_data;
                hypo_risk   <= hypo_risk_w;
            end
        end
    end

endmodule
