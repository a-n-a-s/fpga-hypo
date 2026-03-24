# FPGA Implementation Plan

## Hypoglycemia Prediction Accelerator

**Target Device**: Xilinx Artix-7 / Intel Cyclone V  
**Clock Frequency**: 50 MHz  
**Project**: FPGA-Based Real-Time Hypoglycemia Prediction with Early Exit and Lightweight XAI

---

## 1. System Overview

### Block Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        FPGA TOP LEVEL                                    │
│                                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐               │
│  │   Input      │    │   Conv1D     │    │  BatchNorm   │               │
│  │   Buffer     │───▶│   Engine     │───▶│   Engine     │               │
│  │  (16×uint8)  │    │  (3×1×8)     │    │              │               │
│  └──────────────┘    └──────────────┘    └──────────────┘               │
│                            │                   │                         │
│                            ▼                   ▼                         │
│                       ┌──────────────────────────────┐                   │
│                       │     MaxPool + GlobalAvg      │                   │
│                       │         (combined)           │                   │
│                       └──────────────────────────────┘                   │
│                                          │                               │
│                                          ▼                               │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐               │
│  │   Output     │◀───│   Dense2     │◀───│   Dense1     │               │
│  │   Register   │    │  (16×1)      │    │  (8×16)      │               │
│  └──────────────┘    └──────────────┘    └──────────────┘               │
│       │                                                                  │
│       ▼                                                                  │
│  ┌──────────────┐                                                        │
│  │  Comparison  │  (threshold = 0.667)                                   │
│  │   Module     │                                                        │
│  └──────────────┘                                                        │
│       │                                                                  │
│       ▼                                                                  │
│  HYPO RISK / SAFE  (1-bit output)                                        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
1. Load 16 glucose samples (uint8) → Input Buffer
2. Conv1D: 3×1×8 convolution → 16×8 feature map
3. BatchNorm: Normalize → 16×8 normalized
4. MaxPool: Downsample 2× → 8×8
5. GlobalAvgPool: Average → 8-element vector
6. Dense1: 8→16 matrix multiply → 16-element vector
7. Dense2: 16→1 matrix multiply → 1 probability
8. Compare: probability vs 0.667 → Binary output
```

---

## 2. Memory Map

### Weight Memory (ROM)

| Layer | Start Addr | End Addr | Count | Size |
|-------|------------|----------|-------|------|
| conv1_weights | 0x000 | 0x017 | 24 | 48 bytes |
| conv1_bias | 0x018 | 0x01F | 8 | 16 bytes |
| bn1_gamma | 0x020 | 0x027 | 8 | 16 bytes |
| bn1_beta | 0x028 | 0x02F | 8 | 16 bytes |
| bn1_mean | 0x030 | 0x037 | 8 | 16 bytes |
| bn1_variance | 0x038 | 0x03F | 8 | 16 bytes |
| dense1_weights | 0x040 | 0x0BF | 128 | 256 bytes |
| dense1_bias | 0x0C0 | 0x0CF | 16 | 32 bytes |
| output_weights | 0x0D0 | 0x0DF | 16 | 32 bytes |
| output_bias | 0x0E0 | 0x0E0 | 1 | 2 bytes |
| **Total** | | | **225** | **450 bytes** |

### Activation Memory (RAM)

| Buffer | Size | Format | Purpose |
|--------|------|--------|---------|
| input_buffer | 16×8-bit | uint8 | Input glucose |
| conv_output | 16×8×16-bit | Q8.8 | Conv1D output |
| bn_output | 16×8×16-bit | Q8.8 | BatchNorm output |
| pool_output | 8×8×16-bit | Q8.8 | MaxPool output |
| gap_output | 8×16-bit | Q8.8 | GlobalAvgPool output |
| dense1_output | 16×16-bit | Q8.8 | Dense1 output |
| output_prob | 16-bit | Q8.8 | Final probability |

**Total Activation RAM**: ~1.5 KB

---

## 3. Module Specifications

### 3.1 Top Module (`hypoglycemia_predictor.v`)

```verilog
module hypoglycemia_predictor (
    input  wire        clk,           // 50 MHz clock
    input  wire        rst_n,         // Active-low reset
    input  wire        start,         // Start inference
    input  wire [7:0]  glucose_in[15:0], // 16 glucose samples
    output reg         valid,         // Output valid
    output reg         hypo_risk,     // 1 = hypo risk, 0 = safe
    output reg [15:0]  probability,   // Q8.8 probability
    output reg         busy           // Module busy
);
```

**Interface Signals**:
- `clk`: 50 MHz system clock
- `rst_n`: Active-low asynchronous reset
- `start`: Start inference (pulse)
- `glucose_in[15:0]`: 16 input glucose values (uint8)
- `valid`: Output data valid
- `hypo_risk`: Binary classification (1 = hypo)
- `probability`: Raw probability (Q8.8)
- `busy`: Module busy flag

---

### 3.2 Input Buffer (`input_buffer.v`)

```verilog
module input_buffer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        load,
    input  wire [7:0]  glucose_in[15:0],
    output wire [7:0]  glucose_out[15:0]
);
```

**Function**: Store 16 input glucose samples  
**Resources**: 16×8-bit register file  
**Latency**: 1 cycle

---

### 3.3 Conv1D Engine (`conv1d_engine.v`)

```verilog
module conv1d_engine (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [7:0]  input_data[15:0],
    output reg         done,
    output reg [15:0]  output_data[15:0][7:0]  // 16 timesteps × 8 filters
);
```

**Function**: 1D convolution with 8 filters, kernel size 3  
**Implementation**:
- 8 parallel multiply-accumulate (MAC) units
- Sliding window over 16 timesteps
- Padding: 'same' (output = 16 timesteps)

**Resources**:
- 8 MAC units (DSP slices)
- 24 weight registers (3×1×8)
- 8 bias registers
- Control FSM (10 states)

**Latency**: ~50 cycles

**Computation**:
```verilog
for each timestep t (0-15):
    for each filter f (0-7):
        acc = 0
        for each kernel k (0-2):
            if (t+k-1) within bounds:
                acc += input[t+k-1] × weight[k][f]
        output[t][f] = acc + bias[f]
```

---

### 3.4 BatchNorm Engine (`batchnorm_engine.v`)

```verilog
module batchnorm_engine (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [15:0] input_data[15:0][7:0],
    output reg         done,
    output reg [15:0]  output_data[15:0][7:0]
);
```

**Function**: Batch normalization  
**Formula**:
```
y = (x - mean) / sqrt(variance + epsilon) × gamma + beta
```

**Optimization**: Pre-compute scale and shift:
```
scale = gamma / sqrt(variance + epsilon)
shift = beta - mean × scale
y = x × scale + shift
```

**Resources**:
- 8 scale registers (Q8.8)
- 8 shift registers (Q8.8)
- 8 parallel multipliers
- Control FSM

**Latency**: ~20 cycles

---

### 3.5 MaxPool + GlobalAvgPool (`pooling_engine.v`)

```verilog
module pooling_engine (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [15:0] input_data[15:0][7:0],
    output reg         done,
    output reg [15:0]  output_data[7:0]
);
```

**Function**: MaxPool (2×) followed by Global Average Pooling

**MaxPool**:
- Input: 16×8
- Output: 8×8 (max of every 2 timesteps)

**GlobalAvgPool**:
- Input: 8×8
- Output: 8 (average across timesteps)

**Combined Operation**:
```verilog
for each filter f (0-7):
    max_val = 0
    sum = 0
    for t = 0 to 7:
        max_val = max(input[2t][f], input[2t+1][f])
        sum += max_val
    output[f] = sum / 8
```

**Resources**:
- 8 comparators (max)
- 8 accumulators
- Divider by 8 (shift right by 3)

**Latency**: ~20 cycles

---

### 3.6 Dense Layer (`dense_layer.v`)

```verilog
module dense_layer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [15:0] input_data[7:0],
    input  wire        is_output_layer,  // 1 = output layer (16→1)
    output reg         done,
    output reg [15:0]  output_data
);
```

**Function**: Fully connected layer

**Dense1** (8→16):
- 8 inputs, 16 outputs
- 128 weights + 16 biases
- ReLU activation

**Dense2** (16→1):
- 16 inputs, 1 output
- 16 weights + 1 bias
- Sigmoid activation

**Implementation**:
- Sequential MAC (resource-efficient)
- OR 16 parallel MACs (performance)

**Resources** (sequential):
- 1 MAC unit
- Weight ROM (128 or 16 values)
- Accumulator
- ReLU/Sigmoid unit

**Latency**:
- Dense1: ~150 cycles (sequential) or ~10 cycles (parallel)
- Dense2: ~20 cycles (sequential) or ~2 cycles (parallel)

---

### 3.7 Activation Functions (`activation_unit.v`)

```verilog
module activation_unit (
    input  wire [15:0] input_data,
    input  wire        use_sigmoid,
    output wire [15:0] output_data
);
```

**ReLU**:
```verilog
assign output_data = (input_data[15]) ? 16'b0 : input_data;  // Check sign bit
```

**Sigmoid** (LUT approximation):
```verilog
// 256-entry LUT for sigmoid
// Input: Q8.8, Output: Q8.8
// Range: 0 to 1 (mapped to 0x0000 to 0x00FF)
```

**Resources**:
- ReLU: 1 comparator
- Sigmoid: 256×16-bit ROM (512 bytes)

---

### 3.8 Output Comparator (`output_comparator.v`)

```verilog
module output_comparator (
    input  wire [15:0] probability,  // Q8.8
    output wire        hypo_risk
);
    // Threshold: 0.667 = 0.667 × 256 = 171 = 0x00AB
    localparam [15:0] THRESHOLD = 16'h00AB;
    
    assign hypo_risk = (probability >= THRESHOLD);
endmodule
```

**Threshold**: 0.667 → 171 (Q8.8: 0x00AB)

---

## 4. Control Unit

### FSM States

```verilog
typedef enum logic [3:0] {
    IDLE,        // 0000: Wait for start
    LOAD_INPUT,  // 0001: Load input buffer
    CONV1D,      // 0010: Conv1D inference
    BATCHNORM,   // 0011: BatchNorm
    POOLING,     // 0100: MaxPool + GlobalAvgPool
    DENSE1,      // 0101: Dense layer 1
    DENSE2,      // 0110: Dense layer 2
    OUTPUT,      // 0111: Compare and output
    DONE         // 1000: Inference complete
} state_t;
```

### State Transition Diagram

```
     ┌─────────┐
     │  IDLE   │◀──────────────────────┐
     └────┬────┘                       │
          │ start                      │ done
          ▼                            │
     ┌─────────┐                       │
     │LOAD_IN  │                       │
     └────┬────┘                       │
          │                            │
          ▼                            │
     ┌─────────┐                       │
     │ CONV1D  │                       │
     └────┬────┘                       │
          │                            │
          ▼                            │
     ┌─────────┐                       │
     │BATCHNORM│                       │
     └────┬────┘                       │
          │                            │
          ▼                            │
     ┌─────────┐                       │
     │POOLING  │                       │
     └────┬────┘                       │
          │                            │
          ▼                            │
     ┌─────────┐                       │
     │ DENSE1  │                       │
     └────┬────┘                       │
          │                            │
          ▼                            │
     ┌─────────┐                       │
     │ DENSE2  │                       │
     └────┬────┘                       │
          │                            │
          ▼                            │
     ┌─────────┐      done             │
     │ OUTPUT  │───────────────────────┘
     └─────────┘
```

---

## 5. Resource Estimation

### Xilinx Artix-7 (XC7A35T)

| Resource | Estimated | Available | Utilization |
|----------|-----------|-----------|-------------|
| **LUTs** | 800-1200 | 33,280 | 2-4% |
| **FFs** | 600-900 | 66,560 | 1-2% |
| **DSP Slices** | 4-8 | 90 | 4-9% |
| **BRAM (18Kb)** | 2-3 | 50 | 4-6% |
| **Power** | ~50 mW | - | - |

### Intel Cyclone V (5CEBA4)

| Resource | Estimated | Available | Utilization |
|----------|-----------|-----------|-------------|
| **ALMs** | 600-1000 | 49,760 | 1-2% |
| **FFs** | 600-900 | 99,520 | <1% |
| **DSP Blocks** | 4-8 | 75 | 5-11% |
| **M9K Memory** | 2-3 | 117 | 2-3% |
| **Power** | ~45 mW | - | - |

---

## 6. Performance Estimation

### Latency Breakdown

| Stage | Cycles | Time @ 50MHz |
|-------|--------|--------------|
| Load Input | 16 | 320 ns |
| Conv1D | 50 | 1 μs |
| BatchNorm | 20 | 400 ns |
| Pooling | 20 | 400 ns |
| Dense1 | 150 | 3 μs |
| Dense2 | 20 | 400 ns |
| Output | 5 | 100 ns |
| **Total** | **~281** | **~5.6 μs** |

### Throughput

- **Single Inference**: ~5.6 μs
- **Continuous**: ~180,000 inferences/second
- **CGM Sampling**: Every 5 min = 1 sample
- **Duty Cycling**: Run once per minute → **<1 mW average power**

---

## 7. Testbench Plan

### Testbench Modules

1. **`tb_hypoglycemia_predictor.v`**: Top-level testbench
2. **`tb_conv1d_engine.v`**: Conv1D unit test
3. **`tb_batchnorm_engine.v`**: BatchNorm unit test
4. **`tb_pooling_engine.v`**: Pooling unit test
5. **`tb_dense_layer.v`**: Dense layer unit test

### Test Vectors

| Test | Input | Expected Output |
|------|-------|-----------------|
| Normal glucose | [120, 125, 130, ...] | SAFE (0) |
| Dropping glucose | [100, 90, 80, ...] | HYPO RISK (1) |
| Low glucose | [60, 65, 70, ...] | HYPO RISK (1) |
| Rising glucose | [80, 90, 100, ...] | SAFE (0) |

### Verification

```verilog
// Compare FPGA output with Python reference
initial begin
    $readmemh("mem_files/test_input.mem", test_input);
    expected_output = 17'h00E3;  // 0.898 × 256 = 230 (from Python)
    
    // Run inference
    run_inference(test_input);
    
    // Check output
    if (fpga_output == expected_output) begin
        $display("TEST PASSED");
    end else begin
        $display("TEST FAILED: expected %h, got %h", 
                 expected_output, fpga_output);
    end
end
```

---

## 8. File Structure

```
fpga/
├── src/
│   ├── hypoglycemia_predictor.v    (top module)
│   ├── input_buffer.v
│   ├── conv1d_engine.v
│   ├── batchnorm_engine.v
│   ├── pooling_engine.v
│   ├── dense_layer.v
│   ├── activation_unit.v
│   ├── output_comparator.v
│   └── control_unit.v
├── tb/
│   ├── tb_hypoglycemia_predictor.v
│   ├── tb_conv1d_engine.v
│   ├── tb_batchnorm_engine.v
│   ├── tb_pooling_engine.v
│   └── tb_dense_layer.v
├── mem_files/
│   ├── conv1_weights.mem
│   ├── conv1_bias.mem
│   ├── bn1_gamma.mem
│   ├── bn1_beta.mem
│   ├── bn1_mean.mem
│   ├── bn1_variance.mem
│   ├── dense1_weights.mem
│   ├── dense1_bias.mem
│   ├── output_weights.mem
│   ├── output_bias.mem
│   └── test_input.mem
├── constraints/
│   ├── arty_a7.xdc (Xilinx constraints)
│   └── cyclone_v.qsf (Intel constraints)
└── docs/
    └── FPGA_IMPLEMENTATION_PLAN.md (this file)
```

---

## 9. Implementation Timeline

| Phase | Task | Duration |
|-------|------|----------|
| **Phase 1** | RTL coding (modules) | 3-4 days |
| **Phase 2** | Testbench + simulation | 2-3 days |
| **Phase 3** | Synthesis + timing | 1-2 days |
| **Phase 4** | Hardware verification | 2-3 days |
| **Phase 5** | Early exit addition | 2-3 days |
| **Phase 6** | XAI module | 2-3 days |
| **Total** | | **12-18 days** |

---

## 10. Next Steps

### Immediate (Phase 1)

1. ✅ Create weight .mem files (done)
2. ⏳ Write top module
3. ⏳ Write Conv1D engine
4. ⏳ Write BatchNorm engine
5. ⏳ Write pooling engine
6. ⏳ Write dense layer
7. ⏳ Write control unit

### Short-term (Phase 2-3)

1. Create testbenches
2. Simulate with ModelSim/Vivado
3. Verify against Python output
4. Synthesize for target FPGA

### Long-term (Phase 4-6)

1. Add early exit logic
2. Add XAI (trend/slope detection)
3. Hardware validation
4. Power optimization

---

## 11. Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Fixed-point precision loss | Medium | Verify with Python Q8.8 simulation |
| Timing violations | Low | Pipeline critical paths |
| BRAM inference | Medium | Use distributed RAM for small buffers |
| Power budget | Low | Gate clock when idle |

---

## 12. Success Criteria

| Criterion | Target | Measured |
|-----------|--------|----------|
| Functional correctness | Match Python | TBD |
| Max frequency | >50 MHz | TBD |
| Latency | <10 μs | TBD |
| Power | <100 mW | TBD |
| Resource usage | <10% LUTs | TBD |

---

## Appendix: Weight Files Reference

| File | Values | Format | Size |
|------|--------|--------|------|
| conv1_weights.mem | 24 | Q8.8 hex | 48 bytes |
| conv1_bias.mem | 8 | Q8.8 hex | 16 bytes |
| bn1_gamma.mem | 8 | Q8.8 hex | 16 bytes |
| bn1_beta.mem | 8 | Q8.8 hex | 16 bytes |
| bn1_mean.mem | 8 | Q8.8 hex | 16 bytes |
| bn1_variance.mem | 8 | Q8.8 hex | 16 bytes |
| dense1_weights.mem | 128 | Q8.8 hex | 256 bytes |
| dense1_bias.mem | 16 | Q8.8 hex | 32 bytes |
| output_weights.mem | 16 | Q8.8 hex | 32 bytes |
| output_bias.mem | 1 | Q8.8 hex | 2 bytes |
| **Total** | **225** | | **450 bytes** |

---

**Document Version**: 1.0  
**Last Updated**: March 22, 2026  
**Author**: FPGA Development Team
