`timescale 1ns/1ps

module tb_hypoglycemia_predictor_opt;
    reg clk;
    reg rst_n;
    reg start;
    reg [127:0] glucose_in;
    wire valid;
    wire hypo_risk;
    wire [15:0] probability;
    wire busy;
    wire [2:0] current_state;

    reg [7:0] test_input_mem [0:15];
    reg signed [15:0] conv_w [0:23];
    reg signed [15:0] conv_b [0:7];
    reg signed [15:0] gamma [0:7];
    reg signed [15:0] beta  [0:7];
    reg signed [15:0] mean  [0:7];
    reg signed [15:0] var   [0:7];
    reg signed [15:0] d1_w  [0:127];
    reg signed [15:0] d1_b  [0:15];
    reg signed [15:0] o_w   [0:15];
    reg signed [15:0] o_b_arr [0:0];
    reg signed [15:0] o_b;

    reg signed [15:0] scale [0:7];
    reg signed [15:0] shift [0:7];
    reg signed [15:0] m_conv [0:15][0:7];
    reg signed [15:0] m_bn   [0:15][0:7];
    reg signed [15:0] m_pool [0:7];
    reg signed [15:0] m_d1   [0:15];
    reg [15:0] exp_probability;
    reg exp_hypo;

    integer t;
    integer f;
    integer k;
    integer idx;
    integer acc;
    integer mult;
    integer a;
    integer b;
    integer m;
    integer sum;
    integer temp;
    integer var_eps;
    integer sqrt_q8_8;
    integer inv_sqrt_q8_8;
    integer errors;
    integer timeout;
    integer i;

    localparam [15:0] THRESHOLD = 16'h00AB;
    localparam signed [15:0] EPSILON_Q8_8 = 16'sd1;

    hypoglycemia_predictor_opt dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .glucose_in(glucose_in),
        .valid(valid),
        .hypo_risk(hypo_risk),
        .probability(probability),
        .busy(busy),
        .current_state(current_state)
    );

    function automatic [15:0] isqrt32;
        input [31:0] x;
        reg [31:0] op;
        reg [31:0] res;
        reg [31:0] one;
        begin
            op = x;
            res = 0;
            one = 32'h40000000;
            while (one > op) one = one >> 2;
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

    function automatic [15:0] sigmoid_lut;
        input [5:0] lut_idx;
        begin
            case (lut_idx)
                6'd0:  sigmoid_lut = 16'd0;   6'd1:  sigmoid_lut = 16'd0;
                6'd2:  sigmoid_lut = 16'd0;   6'd3:  sigmoid_lut = 16'd0;
                6'd4:  sigmoid_lut = 16'd1;   6'd5:  sigmoid_lut = 16'd1;
                6'd6:  sigmoid_lut = 16'd2;   6'd7:  sigmoid_lut = 16'd3;
                6'd8:  sigmoid_lut = 16'd5;   6'd9:  sigmoid_lut = 16'd8;
                6'd10: sigmoid_lut = 16'd12;  6'd11: sigmoid_lut = 16'd19;
                6'd12: sigmoid_lut = 16'd31;  6'd13: sigmoid_lut = 16'd47;
                6'd14: sigmoid_lut = 16'd69;  6'd15: sigmoid_lut = 16'd97;
                6'd16: sigmoid_lut = 16'd128; 6'd17: sigmoid_lut = 16'd159;
                6'd18: sigmoid_lut = 16'd187; 6'd19: sigmoid_lut = 16'd209;
                6'd20: sigmoid_lut = 16'd225; 6'd21: sigmoid_lut = 16'd237;
                6'd22: sigmoid_lut = 16'd244; 6'd23: sigmoid_lut = 16'd248;
                6'd24: sigmoid_lut = 16'd251; 6'd25: sigmoid_lut = 16'd253;
                6'd26: sigmoid_lut = 16'd254; 6'd27: sigmoid_lut = 16'd255;
                default: sigmoid_lut = 16'd255;
            endcase
        end
    endfunction

    function automatic [15:0] sigmoid_pwl;
        input signed [31:0] xin;
        integer shifted;
        integer seg_idx;
        integer frac;
        integer y0;
        integer y1;
        integer interp;
        begin
            if (xin <= -2048) begin
                sigmoid_pwl = 16'd0;
            end else if (xin >= 2048) begin
                sigmoid_pwl = 16'd255;
            end else begin
                shifted = xin + 2048;
                seg_idx = shifted >>> 7;
                frac = shifted[6:0];
                y0 = sigmoid_lut(seg_idx[5:0]);
                y1 = sigmoid_lut((seg_idx + 1) & 6'h3F);
                interp = ((y0 * (128 - frac)) + (y1 * frac)) >>> 7;
                sigmoid_pwl = sat16(interp);
            end
        end
    endfunction

    task compute_bn_params;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                var_eps = var[i] + EPSILON_Q8_8;
                if (var_eps <= 0) var_eps = 1;
                sqrt_q8_8 = isqrt32(var_eps <<< 8);
                if (sqrt_q8_8 == 0) sqrt_q8_8 = 1;
                inv_sqrt_q8_8 = 65536 / sqrt_q8_8;
                scale[i] = sat16((gamma[i] * inv_sqrt_q8_8) >>> 8);
                shift[i] = sat16(beta[i] - ((mean[i] * scale[i]) >>> 8));
            end
        end
    endtask

    task compute_reference;
        begin
            // Conv1D
            for (t = 0; t < 16; t = t + 1) begin
                for (f = 0; f < 8; f = f + 1) begin
                    acc = 0;
                    for (k = 0; k < 3; k = k + 1) begin
                        idx = t + k - 1;
                        if ((idx >= 0) && (idx < 16)) begin
                            mult = $signed(glucose_in[(idx*8) +: 8]) * conv_w[(k*8) + f];
                            acc = acc + (mult >>> 8);
                        end
                    end
                    m_conv[t][f] = sat16(acc + conv_b[f]);
                    temp = ((m_conv[t][f] * scale[f]) >>> 8) + shift[f];
                    m_bn[t][f] = sat16(temp);
                end
            end

            // Pooling
            for (f = 0; f < 8; f = f + 1) begin
                sum = 0;
                for (t = 0; t < 8; t = t + 1) begin
                    a = m_bn[2*t][f];
                    b = m_bn[(2*t)+1][f];
                    if (a > b) m = a;
                    else m = b;
                    sum = sum + m;
                end
                m_pool[f] = (sum >>> 3);
            end

            // Dense1 (ReLU)
            for (f = 0; f < 16; f = f + 1) begin
                acc = d1_b[f];
                for (t = 0; t < 8; t = t + 1) begin
                    idx = (t * 16) + f;
                    acc = acc + ((m_pool[t] * d1_w[idx]) >>> 8);
                end
                if (acc < 0) m_d1[f] = 16'sd0;
                else m_d1[f] = sat16(acc);
            end

            // Dense2 (Sigmoid)
            acc = o_b;
            for (t = 0; t < 16; t = t + 1) begin
                acc = acc + ((m_d1[t] * o_w[t]) >>> 8);
            end
            exp_probability = sigmoid_pwl(acc);
            exp_hypo = (exp_probability >= THRESHOLD);
        end
    endtask

    task run_case;
        input [127:0] name;
        begin
            compute_reference();
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            timeout = 0;
            while ((valid !== 1'b1) && (timeout < 2000)) begin  // Increased timeout for sequential design
                timeout = timeout + 1;
                @(posedge clk);
            end

            if (valid !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL %0s: timed out waiting for valid", name);
            end else begin
                if (probability !== exp_probability) begin
                    errors = errors + 1;
                    $display("FAIL %0s: probability exp=%0d got=%0d",
                             name, exp_probability, probability);
                end
                if (hypo_risk !== exp_hypo) begin
                    errors = errors + 1;
                    $display("FAIL %0s: hypo exp=%0d got=%0d", name, exp_hypo, hypo_risk);
                end
            end
            @(posedge clk);
        end
    endtask

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        errors = 0;

        glucose_in = 128'd0;
        for (i = 0; i < 16; i = i + 1) begin
            test_input_mem[i] = 8'd0;
            d1_b[i] = 16'sd0;
        end
        for (i = 0; i < 24; i = i + 1) conv_w[i] = 16'sd0;
        for (i = 0; i < 8; i = i + 1) begin
            conv_b[i] = 16'sd0;
            gamma[i] = 16'sd0;
            beta[i] = 16'sd0;
            mean[i] = 16'sd0;
            var[i] = 16'sd0;
            scale[i] = 16'sd0;
            shift[i] = 16'sd0;
        end
        for (i = 0; i < 128; i = i + 1) d1_w[i] = 16'sd0;
        for (i = 0; i < 16; i = i + 1) o_w[i] = 16'sd0;
        o_b_arr[0] = 16'sd0;
        o_b = 16'sd0;

        $readmemh("test_input.mem", test_input_mem);
        $readmemh("conv1_weights.mem", conv_w);
        $readmemh("conv1_bias.mem", conv_b);
        $readmemh("bn1_gamma.mem", gamma);
        $readmemh("bn1_beta.mem", beta);
        $readmemh("bn1_mean.mem", mean);
        $readmemh("bn1_variance.mem", var);
        $readmemh("dense1_weights.mem", d1_w);
        $readmemh("dense1_bias.mem", d1_b);
        $readmemh("output_weights.mem", o_w);
        $readmemh("output_bias.mem", o_b_arr);
        o_b = o_b_arr[0];

        compute_bn_params();

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Test case 1: from file
        for (i = 0; i < 16; i = i + 1) begin
            glucose_in[(i*8) +: 8] = test_input_mem[i];
        end
        run_case("test_input.mem");

        // Test case 2: ramp input
        for (i = 0; i < 16; i = i + 1) begin
            glucose_in[(i*8) +: 8] = 8'd90 + i;
        end
        run_case("ramp_input");

        if (errors == 0) begin
            $display("tb_hypoglycemia_predictor_opt: PASS");
        end else begin
            $display("tb_hypoglycemia_predictor_opt: FAIL (%0d mismatches)", errors);
        end
        $finish;
    end
endmodule
