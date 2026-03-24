module output_comparator (
    input  wire [15:0] probability,
    output wire        hypo_risk
);
    localparam [15:0] THRESHOLD = 16'h00AB;
    assign hypo_risk = (probability >= THRESHOLD);
endmodule
