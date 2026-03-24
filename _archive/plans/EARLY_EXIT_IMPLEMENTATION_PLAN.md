# Early Exit Implementation Plan
## Hypoglycemia Predictor CNN - FPGA Project

**Date:** March 23, 2026  
**Project:** FPGA-Based Real-Time Hypoglycemia Prediction with Early Exit and Lightweight XAI

---

## Overview

This document describes the plan to add **early exit capability** to the hypoglycemia predictor FPGA implementation. Early exit allows the model to make predictions after the Dense1 layer if confidence is high, reducing latency and power consumption for easy-to-classify samples.

### Key Benefits

| Benefit | Description |
|---------|-------------|
| **Reduced Latency** | Easy samples exit after Dense1 (~150 cycles saved) |
| **Lower Power** | Skip Dense2 computation when confident |
| **Same Worst-Case** | Hard samples still use full model for accuracy |

---

## Architecture

### Early Exit Point

```
Input → Conv1D → BatchNorm → Pool → Dense1 → [EARLY EXIT] → Dense2 → Output
                                    │
                                    └─→ Early Exit Classifier → Exit if confident
```

### Exit Conditions

Exit early if:
- **Confident HYPO:** `early_probability >= 0.8` (205/255)
- **Confident SAFE:** `early_probability <= 0.2` (51/255)
- **Otherwise:** Continue to Dense2

---

## Phase 1: Train Early Exit Model in Python (2-3 days)

### Task 1.1: Modify Model Architecture

**File:** `train_model.py`

Add early exit branch to the model:

```python
def create_early_exit_cnn():
    """
    Create CNN with early exit capability.
    Exit after Dense1 if confidence is high.
    """
    inputs = keras.Input(shape=(16, 1))

    # Conv block
    x = layers.Conv1D(filters=8, kernel_size=3, padding='same',
                      activation='relu', name='conv1')(inputs)
    x = layers.BatchNormalization(name='bn1')(x)
    x = layers.MaxPooling1D(pool_size=2, name='pool1')(x)
    x = layers.GlobalAveragePooling1D(name='gap')(x)
    x = layers.Dense(16, activation='relu', name='dense1')(x)

    # Early exit branch (after Dense1)
    early_output = layers.Dense(1, activation='sigmoid', 
                                 name='early_output')(x)

    # Continue to full model
    main_output = layers.Dense(1, activation='sigmoid', 
                                name='output')(x)

    model = keras.Model(inputs, [early_output, main_output], 
                        name='early_exit_cnn')

    return model
```

### Task 1.2: Train with Multi-Task Loss

```python
# Compile with multiple outputs
model.compile(
    optimizer=keras.optimizers.Adam(learning_rate=0.001),
    loss={'early_output': 'binary_crossentropy', 
          'output': 'binary_crossentropy'},
    loss_weights={'early_output': 0.3, 'output': 0.7},  # Weight main output higher
    metrics=['accuracy']
)

# Train
history = model.fit(X_train, {'early_output': y_train, 'output': y_train},
                    epochs=30, batch_size=32, validation_split=0.2)
```

**Determine optimal thresholds:**
- High confidence HYPO: probability >= 0.8
- High confidence SAFE: probability <= 0.2
- Measure early exit rate on validation set

### Task 1.3: Export Early Exit Weights

**File:** `export_weights.py`

Add export for early exit dense layer:

```python
# Early exit dense layer (8→1, but we use 16→1 since gap output is 8)
# Actually, early exit uses same Dense1 output, so we need separate weights
early_exit_weights = model.get_layer('early_output').get_weights()[0]  # (16, 1)
early_exit_bias = model.get_layer('early_output').get_weights()[1]      # (1,)

# Convert to Q8.8 and save
early_exit_w_fixed = [float_to_fixed(w) for w in early_exit_weights.flatten()]
early_exit_b_fixed = [float_to_fixed(b) for b in early_exit_bias]

write_mem_file(early_exit_w_fixed, 'mem_files/early_exit_weights.mem')
write_mem_file(early_exit_b_fixed, 'mem_files/early_exit_bias.mem')
```

**Update golden vectors:**
```python
# Add early exit predictions to golden vectors
for tv in test_vectors:
    early_pred = early_exit_model.predict(x_raw)[0]
    tv['early_exit_prob'] = float(early_pred)
    tv['would_exit_early'] = (early_pred >= 0.8) or (early_pred <= 0.2)
```

**Deliverable:** Trained early exit model with exported weights

---

## Phase 2: RTL Implementation (3-4 days)

### Task 2.1: Add Early Exit Comparator Module

**New File:** `fpga/src/early_exit_comparator.v`

```verilog
`timescale 1ns/1ps

module early_exit_comparator (
    input  wire [15:0] early_probability,  // Q8.8 from early exit
    input  wire [15:0] high_conf_thresh,   // 0.8 = 205 = 0x00CD
    input  wire [15:0] low_conf_thresh,    // 0.2 = 51 = 0x0033
    output wire early_exit_valid,          // 1 = can exit early
    output wire early_hypo_risk            // Early exit classification
);

    // High confidence HYPO: prob >= 0.8
    wire confident_hypo = (early_probability >= high_conf_thresh);
    
    // High confidence SAFE: prob <= 0.2
    wire confident_safe = (early_probability <= low_conf_thresh);
    
    // Exit if confident in either direction
    assign early_exit_valid = confident_hypo || confident_safe;
    
    // Classification if exiting early
    assign early_hypo_risk = confident_hypo ? 1'b1 : 1'b0;

endmodule
```

### Task 2.2: Add Early Exit Dense Layer

**Option A:** Create new module `fpga/src/early_exit_dense.v`

```verilog
`timescale 1ns/1ps

module early_exit_dense (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [127:0] input_data,  // 8 × 16-bit (pool output)
    output reg         done,
    output reg [15:0]  output_data  // 1 × 16-bit (sigmoid output)
);

    reg signed [15:0] w_mem [0:15];  // 16 weights (8→1, but stored as 16 for alignment)
    reg signed [15:0] b_mem [0:0];   // 1 bias

    // ... (same structure as dense_layer.v, simplified for 8→1)
    
    initial begin
        $readmemh("early_exit_weights.mem", w_mem);
        $readmemh("early_exit_bias.mem", b_mem);
    end

    // ... computation logic
endmodule
```

**Option B:** Reuse existing `dense_layer.v` with parameters:
```verilog
dense_layer #(
    .IN_SIZE(8),
    .OUT_SIZE(1),
    .USE_RELU(0),
    .USE_SIGMOID(1)
) u_early_exit_dense (
    .clk(clk),
    .rst_n(rst_n),
    .start(dense1_start),  // Trigger with Dense1
    .input_data(pool_data),
    .done(early_exit_done),
    .output_data(early_exit_prob)
);
```

### Task 2.3: Modify Top Module

**File:** `fpga/src/hypoglycemia_predictor.v`

Add signals and modules:

```verilog
module hypoglycemia_predictor (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [127:0] glucose_in,
    output reg         valid,
    output reg         hypo_risk,
    output reg [15:0]  probability,
    output wire        busy,
    // New early exit outputs
    output reg         early_exit_used,   // 1 = early exit was taken
    output reg [2:0]   exit_stage         // 0=Dense1, 1=Dense2
);

    // Existing wires
    wire load_input, conv_start, bn_start, pool_start;
    wire dense1_start, dense2_start, output_valid;
    wire conv_done, bn_done, pool_done, dense1_done, dense2_done;
    
    // New early exit wires
    wire early_exit_done;
    wire [15:0] early_exit_prob;
    wire early_exit_valid;
    wire early_hypo_risk;

    // Existing data wires
    wire [127:0] input_data;
    wire [2047:0] conv_data;
    wire [2047:0] bn_data;
    wire [127:0] pool_data;
    wire [255:0] dense1_data;
    wire [15:0] dense2_data;
    wire hypo_risk_w;

    // Existing modules (u_control, u_input_buffer, etc.)
    // ...

    // NEW: Early exit dense layer (runs in parallel with Dense1)
    dense_layer #(
        .IN_SIZE(8),
        .OUT_SIZE(1),
        .USE_RELU(0),
        .USE_SIGMOID(1)
    ) u_early_exit_dense (
        .clk(clk),
        .rst_n(rst_n),
        .start(dense1_start),  // Start with Dense1
        .input_data({pool_data, 64'd0}),  // Pad to 128 bits
        .done(early_exit_done),
        .output_data(early_exit_prob)
    );

    // NEW: Early exit comparator
    early_exit_comparator u_early_cmp (
        .early_probability(early_exit_prob),
        .high_conf_thresh(16'h00CD),  // 0.8 = 205
        .low_conf_thresh(16'h0033),   // 0.2 = 51
        .early_exit_valid(early_exit_valid),
        .early_hypo_risk(early_hypo_risk)
    );

    // Modified control unit with early exit input
    control_unit u_control (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .conv_done(conv_done),
        .bn_done(bn_done),
        .pool_done(pool_done),
        .dense1_done(dense1_done),
        .dense2_done(dense2_done),
        .early_exit_valid(early_exit_valid),  // NEW input
        .load_input(load_input),
        .conv_start(conv_start),
        .bn_start(bn_start),
        .pool_start(pool_start),
        .dense1_start(dense1_start),
        .dense2_start(dense2_start),
        .output_valid(output_valid),
        .busy(busy)
    );

    // Modified output logic with early exit MUX
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid         <= 1'b0;
            probability   <= 16'h0000;
            hypo_risk     <= 1'b0;
            early_exit_used <= 1'b0;
            exit_stage    <= 3'd0;
        end else begin
            valid <= output_valid;
            if (output_valid) begin
                if (early_exit_valid) begin
                    probability   <= early_exit_prob;
                    hypo_risk     <= early_hypo_risk;
                    early_exit_used <= 1'b1;
                    exit_stage    <= 3'd1;  // Exited after Dense1
                end else begin
                    probability   <= dense2_data;
                    hypo_risk     <= hypo_risk_w;
                    early_exit_used <= 1'b0;
                    exit_stage    <= 3'd2;  // Went through Dense2
                end
            end
        end
    end

endmodule
```

### Task 2.4: Modify Control Unit FSM

**File:** `fpga/src/control_unit.v`

Add early exit state and transitions:

```verilog
module control_unit (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire conv_done,
    input  wire bn_done,
    input  wire pool_done,
    input  wire dense1_done,
    input  wire dense2_done,
    input  wire early_exit_valid,  // NEW input
    output reg  load_input,
    output reg  conv_start,
    output reg  bn_start,
    output reg  pool_start,
    output reg  dense1_start,
    output reg  dense2_start,
    output reg  output_valid,
    output reg  busy
);

    localparam [3:0] IDLE           = 4'd0;
    localparam [3:0] LOAD           = 4'd1;
    localparam [3:0] CONV           = 4'd2;
    localparam [3:0] BATCHNORM      = 4'd3;
    localparam [3:0] POOL           = 4'd4;
    localparam [3:0] DENSE1         = 4'd5;
    localparam [3:0] EARLY_EXIT_CHECK = 4'd6;  // NEW state
    localparam [3:0] DENSE2         = 4'd7;
    localparam [3:0] OUTPUT         = 4'd8;

    reg [3:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            // ... reset other signals
        end else begin
            // ... clear output signals

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
                        state <= EARLY_EXIT_CHECK;  // NEW: Check early exit
                    end
                end

                EARLY_EXIT_CHECK: begin  // NEW state
                    if (early_exit_valid) begin
                        // Confident - skip Dense2
                        state <= OUTPUT;
                    end else begin
                        // Not confident - continue to Dense2
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
```

### Task 2.5: Update Weight Files

Add early exit weight export to `export_weights.py`:

```python
# Early exit weights (16→1 dense layer)
early_exit_layer = model.get_layer('early_output')
ee_weights = early_exit_layer.get_weights()[0].flatten()  # (16,)
ee_bias = early_exit_layer.get_weights()[1][0]            # scalar

ee_w_fixed = [float_to_fixed(w) for w in ee_weights]
ee_b_fixed = [float_to_fixed(ee_bias)]

write_mem_file(ee_w_fixed, 'mem_files/early_exit_weights.mem')
write_mem_file(ee_b_fixed, 'mem_files/early_exit_bias.mem')
```

**Deliverable:** Modified RTL with early exit capability

---

## Phase 3: Testbench Updates (2 days)

### Task 3.1: Update Top-Level Testbench

**File:** `fpga/tb/tb_hypoglycemia_predictor.v`

Add early exit monitoring:

```verilog
// Add to testbench
wire early_exit_used;
wire [2:0] exit_stage;

hypoglycemia_predictor dut (
    // ... existing ports
    .early_exit_used(early_exit_used),
    .exit_stage(exit_stage)
);

// In test task
task run_case;
    input [127:0] name;
    begin
        compute_reference();
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        timeout = 0;
        while ((valid !== 1'b1) && (timeout < 100)) begin
            timeout = timeout + 1;
            @(posedge clk);
        end

        if (valid !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL %0s: timed out", name);
        end else begin
            // Check early exit behavior
            if (early_exit_used) begin
                $display("INFO %0s: exited early (stage=%0d)", name, exit_stage);
                early_exit_count = early_exit_count + 1;
            end
            
            // Verify output matches expected (whether early or full)
            if (probability !== exp_probability) begin
                errors = errors + 1;
                $display("FAIL %0s: probability mismatch", name);
            end
        end
    end
endtask
```

### Task 3.2: Create Early Exit Testbench

**New File:** `fpga/tb/tb_early_exit.v`

```verilog
`timescale 1ns/1ps

module tb_early_exit;
    // Test early exit behavior with various confidence levels
    
    reg clk;
    reg rst_n;
    reg start;
    reg [127:0] glucose_in;
    wire valid;
    wire hypo_risk;
    wire [15:0] probability;
    wire busy;
    wire early_exit_used;
    wire [2:0] exit_stage;

    integer high_conf_hypo_count;
    integer high_conf_safe_count;
    integer low_conf_count;

    hypoglycemia_predictor dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .glucose_in(glucose_in),
        .valid(valid),
        .hypo_risk(hypo_risk),
        .probability(probability),
        .busy(busy),
        .early_exit_used(early_exit_used),
        .exit_stage(exit_stage)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        glucose_in = 128'd0;
        
        high_conf_hypo_count = 0;
        high_conf_safe_count = 0;
        low_conf_count = 0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Test 1: High confidence HYPO (should exit early)
        $display("Test 1: High confidence HYPO");
        glucose_in = create_high_conf_hypo();
        run_test();
        if (early_exit_used && hypo_risk) high_conf_hypo_count++;

        // Test 2: High confidence SAFE (should exit early)
        $display("Test 2: High confidence SAFE");
        glucose_in = create_high_conf_safe();
        run_test();
        if (early_exit_used && !hypo_risk) high_conf_safe_count++;

        // Test 3: Low confidence (should use full model)
        $display("Test 3: Low confidence");
        glucose_in = create_low_conf();
        run_test();
        if (!early_exit_used) low_conf_count++;

        // Report
        $display("\n=== EARLY EXIT TEST RESULTS ===");
        $display("High conf HYPO (early): %0d/1", high_conf_hypo_count);
        $display("High conf SAFE (early): %0d/1", high_conf_safe_count);
        $display("Low conf (full model):  %0d/1", low_conf_count);
        
        if (high_conf_hypo_count == 1 && high_conf_safe_count == 1 && low_conf_count == 1) begin
            $display("tb_early_exit: PASS");
        end else begin
            $display("tb_early_exit: FAIL");
        end
        
        $finish;
    end

    task run_test;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(valid == 1'b1);
        @(posedge clk);
    endtask

    function [127:0] create_high_conf_hypo;
        // Create input pattern that should give high confidence HYPO
        // (rapidly dropping glucose)
        create_high_conf_hypo = 128'd0;
        // ... set appropriate values
    endfunction

    function [127:0] create_high_conf_safe;
        // Create input pattern that should give high confidence SAFE
        // (stable or rising glucose)
        create_high_conf_safe = 128'd0;
        // ... set appropriate values
    endfunction

    function [127:0] create_low_conf;
        // Create input pattern that should give low confidence
        // (borderline case)
        create_low_conf = 128'd0;
        // ... set appropriate values
    endfunction

endmodule
```

### Task 3.3: Update Python Comparison Script

**File:** `compare_rtl_vs_python.py`

Add early exit comparison:

```python
# Load early exit model
early_exit_model = create_early_exit_cnn()
early_exit_model.load_weights('models/early_exit_cnn.weights.h5')

# Compare early exit predictions
print("=" * 70)
print("EARLY EXIT COMPARISON")
print("=" * 70)

early_exit_correct = 0
early_exit_total = 0
full_model_correct = 0

for i, tv in enumerate(golden[:20]):
    x_raw = (X_test[i] / 400.0).reshape(1, 16, 1)
    
    # Get early exit and full model predictions
    early_pred, full_pred = early_exit_model.predict(x_raw, verbose=0)
    early_prob = float(early_pred[0, 0])
    full_prob = float(full_pred[0, 0])
    
    # Determine if early exit would be taken
    would_exit = (early_prob >= 0.8) or (early_prob <= 0.2)
    actual_label = y_test[i]
    
    # Check accuracy
    early_pred_label = 1 if early_prob >= 0.5 else 0
    full_pred_label = 1 if full_prob >= 0.5 else 0
    
    if would_exit:
        early_exit_total += 1
        if early_pred_label == actual_label:
            early_exit_correct += 1
    
    if full_pred_label == actual_label:
        full_model_correct += 1

early_exit_rate = early_exit_total / len(golden[:20])
early_exit_accuracy = early_exit_correct / max(early_exit_total, 1)
full_model_accuracy = full_model_correct / len(golden[:20])

print(f"Early exit rate: {early_exit_rate*100:.1f}%")
print(f"Early exit accuracy: {early_exit_accuracy*100:.1f}%")
print(f"Full model accuracy: {full_model_accuracy*100:.1f}%")
```

**Deliverable:** Verified early exit RTL

---

## Phase 4: Synthesis & Comparison (2 days)

### Task 4.1: Run Synthesis with Early Exit

Create synthesis script and compare:

```tcl
# synth_early_exit.tcl
create_project hypoglycemia_early_exit ./early_exit_proj -part xc7a35ticsg325-1L

add_files -norecurse {
    src/activation_unit.v
    src/batchnorm_engine.v
    src/conv1d_engine.v
    src/control_unit.v
    src/dense_layer.v
    src/early_exit_comparator.v
    src/early_exit_dense.v
    src/hypoglycemia_predictor.v
    src/input_buffer.v
    src/output_comparator.v
    src/pooling_engine.v
}

set_property top hypoglycemia_predictor [current_fileset]
launch_runs synth_1
wait_on_run synth_1
open_run synth_1

report_utilization -file early_exit_util.rpt
report_timing_summary -file early_exit_timing.rpt
```

### Task 4.2: Measure Performance Metrics

| Metric | Baseline | Early Exit | Improvement |
|--------|----------|------------|-------------|
| **Latency (avg)** | ~281 cycles | TBD (target: <180) | ~35% reduction |
| **Latency (worst)** | ~281 cycles | ~281 cycles | 0% |
| **LUTs** | ~850 | TBD (target: <1000) | <15% increase |
| **FFs** | ~620 | TBD | <15% increase |
| **DSPs** | ~8 | ~8-10 | Minimal |
| **Early exit rate** | 0% | Target: 40-60% | - |
| **Accuracy** | 90.5% F1 | Target: >89% F1 | <2% drop |

### Task 4.3: Create Comparison Report

**New File:** `EARLY_EXIT_COMPARISON.md`

Document:
- Accuracy comparison (baseline vs early exit)
- Latency savings (average case)
- Resource overhead
- Power savings estimate
- Recommended configuration

**Deliverable:** Complete early exit implementation with metrics

---

## File Summary

### New Files to Create

| File | Purpose |
|------|---------|
| `fpga/src/early_exit_comparator.v` | Early exit decision logic |
| `fpga/src/early_exit_dense.v` | Early exit classifier (or reuse dense_layer) |
| `fpga/tb/tb_early_exit.v` | Early exit testbench |
| `EARLY_EXIT_COMPARISON.md` | Results comparison report |

### Files to Modify

| File | Changes |
|------|---------|
| `train_model.py` | Add early exit model architecture and training |
| `export_weights.py` | Export early exit weights |
| `fpga/src/hypoglycemia_predictor.v` | Add early exit path and MUX |
| `fpga/src/control_unit.v` | Add EARLY_EXIT_CHECK state |
| `fpga/tb/tb_hypoglycemia_predictor.v` | Monitor early exit signals |
| `compare_rtl_vs_python.py` | Add early exit comparison |

---

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Early exit accuracy drop | High | Use conservative thresholds, verify on test set |
| Resource overhead too high | Medium | Share computation between early/main exit |
| Timing violations | Low | Pipeline early exit comparator |
| Complex control logic | Medium | Keep FSM simple, add documentation |

---

## Success Criteria

- [ ] Early exit model trained with <1% accuracy drop
- [ ] Early exit rate >40% (40% of samples exit early)
- [ ] RTL verified against Python early exit model
- [ ] Synthesis completes with <15% resource overhead
- [ ] Average latency reduced by >30%

---

## Timeline

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Python Model | 2-3 days | None |
| Phase 2: RTL Implementation | 3-4 days | Phase 1 |
| Phase 3: Testbenches | 2 days | Phase 2 |
| Phase 4: Synthesis & Compare | 2 days | Phase 3 |
| **Total** | **9-11 days** | Sequential |

---

## Next Steps (After Early Exit)

1. **XAI Module** - Add trend/slope detection for explainability
2. **Final Comparison** - Baseline vs Early Exit vs XAI
3. **Hardware Validation** - Test on actual FPGA board

---

*Document Version: 1.0*  
*Last Updated: March 23, 2026*
