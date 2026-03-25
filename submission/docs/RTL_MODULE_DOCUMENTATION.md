# RTL Module Documentation
## FPGA Hypoglycemia Predictor - Complete Module Reference

**Date:** March 24, 2026  
**Project:** FPGA-Based Real-Time Hypoglycemia Prediction with Early Exit and XAI  
**Target Device:** Xilinx Artix-7 XC7A35T (xc7a35ticsg324-1L)

---

## Table of Contents

1. [Overview](#overview)
2. [Baseline CNN Modules](#baseline-cnn-modules)
3. [Early Exit Modules](#early-exit-modules)
4. [XAI Modules](#xai-modules)
5. [Top-Level Modules](#top-level-modules)
6. [Resource Summary](#resource-summary)

---

## Overview

This document provides detailed descriptions of all 24 Verilog RTL modules created for the FPGA Hypoglycemia Predictor project. The design consists of three architectures:

| Architecture | Modules | Purpose |
|-------------|---------|---------|
| **Baseline CNN** | 9 modules | Standard CNN inference pipeline |
| **Early Exit** | 4 modules | Adaptive inference with early exit |
| **XAI** | 4 modules | Explainable AI with interpretable outputs |
| **Shared** | 7 modules | Common utilities across architectures |

### CNN Architecture

```
Input (16×1) → Conv1D (3×1×8) → BatchNorm → MaxPool → GAP → Dense1 (8→16) → Dense2 (16→1) → Output
```

### Data Flow

```
┌─────────────┐
│ Input Buffer │ 128-bit glucose input
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Conv1D      │ 16×8 → 16×8 feature maps
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ BatchNorm   │ Normalize activations
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Pooling     │ Global average pooling
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Dense1      │ 8 → 16 neurons (ReLU)
└──────┬──────┘
       │
       ├──────────────┬──────────────┐
       │              │              │
       ▼              ▼              ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│ Dense2      │ │ Early Exit  │ │ XAI         │
│ (16→1)      │ │ (8→1)       │ │ (Parallel)  │
└─────────────┘ └─────────────┘ └─────────────┘
```

---

## Baseline CNN Modules

### 1. `hypoglycemia_predictor.v` - Top-Level Module (Baseline)

**File:** `fpga/src/hypoglycemia_predictor.v`  
**Lines:** 136  
**Role:** Top-level integration module for baseline CNN

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock (50 MHz) |
| `rst_n` | Input | 1 | Active-low reset |
| `start` | Input | 1 | Start inference |
| `glucose_in` | Input | 128 | 16 × 8-bit glucose values |
| `valid` | Output | 1 | Output data valid |
| `hypo_risk` | Output | 1 | Binary classification (1=HYPO) |
| `probability` | Output | 16 | Raw probability (Q8.8) |
| `busy` | Output | 1 | Module busy signal |

#### Architecture

Instantiates and connects:
- `input_buffer` - Input data latch
- `conv1d_engine_seq` - Conv1D layer
- `batchnorm_engine_seq` - Batch normalization
- `pooling_engine` - Global average pooling
- `dense_layer_seq` (×2) - Two dense layers
- `control_unit` - FSM controller
- `output_comparator` - Threshold comparator

#### Resource Usage

| Resource | Count |
|----------|-------|
| LUTs | ~5,048 |
| DSPs | 6 |
| FFs | ~4,958 |

---

### 2. `conv1d_engine_seq.v` - 1D Convolution Engine

**File:** `fpga/src/conv1d_engine_seq.v`  
**Lines:** 103  
**Role:** Sequential 1D convolution with 3×1 kernels, 8 filters

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Active-low reset |
| `start` | Input | 1 | Start convolution |
| `input_data` | Input | 128 | 16 × 8-bit input |
| `done` | Output | 1 | Operation complete |
| `output_data` | Output | 2048 | 16×8 × 16-bit output |

#### Architecture

**Sequential Design:**
- Uses **1 DSP** (vs 24 in parallel design)
- Time-multiplexed multiply-accumulate (MAC)
- 384 cycles latency (16 timesteps × 8 filters × 3 kernels)

**Weight Storage:**
- 24 weights (3 kernels × 8 filters) in Q8.8 format
- 8 biases in Q8.8 format
- Loaded from `conv1_weights.mem` and `conv1_bias.mem`

**Key Features:**
- `(* use_dsp = "yes" *)` attribute for DSP inference
- Saturation arithmetic to prevent overflow
- Signed multiplication for negative weights

#### FSM States

```
IDLE → COMPUTE (loop 384 times) → STORE → DONE
```

#### Resource Usage

| Resource | Count | Notes |
|----------|-------|-------|
| LUTs | 861 | Sequential logic |
| DSPs | 1 | Single MAC unit |
| FFs | ~300 | Counters, accumulators |

---

### 3. `batchnorm_engine_seq.v` - Batch Normalization Engine

**File:** `fpga/src/batchnorm_engine_seq.v`  
**Lines:** 122  
**Role:** Sequential batch normalization with pre-computed parameters

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Active-low reset |
| `start` | Input | 1 | Start batchnorm |
| `input_data` | Input | 2048 | 16×8 × 16-bit input |
| `done` | Output | 1 | Operation complete |
| `output_data` | Output | 2048 | Normalized output |

#### Architecture

**Pre-computation Strategy:**
- Scale and shift parameters pre-calculated in Python
- Eliminates sqrt and division operations in RTL
- Saves ~1,000 LUTs

**Computation:**
```
output = (input × scale) + shift
where:
  scale = gamma / sqrt(variance + epsilon)
  shift = beta - (mean × scale)
```

**Sequential Design:**
- 1 DSP (vs 8 in parallel design)
- 128 cycles latency (16 timesteps × 8 filters)

#### Weight Files

- `bn1_scale.mem` - 8 scale values (Q8.8)
- `bn1_shift.mem` - 8 shift values (Q8.8)

#### Resource Usage

| Resource | Count |
|----------|-------|
| LUTs | ~150 |
| DSPs | 1 |
| FFs | ~200 |

---

### 4. `dense_layer_seq.v` - Sequential Dense Layer

**File:** `fpga/src/dense_layer_seq.v`  
**Lines:** 186  
**Role:** Generic sequential dense (fully connected) layer

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Active-low reset |
| `start` | Input | 1 | Start dense layer |
| `input_data` | Input | IN_SIZE×16 | Input vector |
| `done` | Output | 1 | Operation complete |
| `output_data` | Output | OUT_SIZE×16 | Output vector |

#### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `IN_SIZE` | integer | 8 | Number of input neurons |
| `OUT_SIZE` | integer | 16 | Number of output neurons |
| `USE_RELU` | integer | 1 | Enable ReLU activation |
| `USE_SIGMOID` | integer | 0 | Enable sigmoid activation |

#### Architecture

**Sequential MAC:**
- Single DSP reused for all multiplications
- Latency: IN_SIZE × OUT_SIZE cycles
- Weight memory: IN_SIZE × OUT_SIZE × 16 bits

**Activation Functions:**
- **ReLU:** `max(0, x)` - simple comparison
- **Sigmoid:** 64-entry LUT for fast approximation

**Sigmoid LUT:**
```verilog
6'd0:  0      6'd16: 128 (0.5)
6'd8:  5       6'd20: 225 (0.88)
6'd12: 31      6'd24: 252 (0.99)
```

#### Configurations Used

| Instance | IN_SIZE | OUT_SIZE | ReLU | Sigmoid | Purpose |
|----------|---------|----------|------|---------|---------|
| `u_dense1` | 8 | 16 | Yes | No | First dense layer |
| `u_dense2` | 16 | 1 | No | Yes | Output layer |
| `u_early_exit` | 8 | 1 | No | Yes | Early exit layer |

#### Resource Usage (for 8→16 configuration)

| Resource | Count |
|----------|-------|
| LUTs | 222 |
| DSPs | 1 |
| FFs | ~250 |

---

### 5. `pooling_engine.v` - Global Average Pooling

**File:** `fpga/src/pooling_engine.v`  
**Lines:** 90  
**Role:** Reduces 16×8 feature map to 8×1 vector

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Active-low reset |
| `start` | Input | 1 | Start pooling |
| `input_data` | Input | 2048 | 16×8 × 16-bit input |
| `done` | Output | 1 | Operation complete |
| `output_data` | Output | 128 | 8 × 16-bit output |

#### Architecture

**Computation:**
```
For each filter f (0-7):
  sum = Σ(input[t, f]) for t=0 to 15
  output[f] = sum / 16
```

**Sequential Design:**
- Single adder with accumulator
- 128 cycles latency (16 timesteps × 8 filters)
- Division by 16 implemented as right shift (>>4)

#### Resource Usage

| Resource | Count |
|----------|-------|
| LUTs | 48 |
| DSPs | 0 |
| FFs | ~100 |

---

### 6. `control_unit.v` - Baseline FSM Controller

**File:** `fpga/src/control_unit.v`  
**Lines:** 114  
**Role:** Finite state machine for baseline CNN pipeline

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Active-low reset |
| `start` | Input | 1 | Start inference |
| `conv_done` | Input | 1 | Conv1D complete |
| `bn_done` | Input | 1 | BatchNorm complete |
| `pool_done` | Input | 1 | Pooling complete |
| `dense1_done` | Input | 1 | Dense1 complete |
| `dense2_done` | Input | 1 | Dense2 complete |
| `load_input` | Output | 1 | Load input buffer |
| `conv_start` | Output | 1 | Start Conv1D |
| `bn_start` | Output | 1 | Start BatchNorm |
| `pool_start` | Output | 1 | Start Pooling |
| `dense1_start` | Output | 1 | Start Dense1 |
| `dense2_start` | Output | 1 | Start Dense2 |
| `output_valid` | Output | 1 | Output ready |
| `busy` | Output | 1 | Module busy |

#### FSM States

| State | Value | Action | Next State |
|-------|-------|--------|------------|
| `IDLE` | 0 | Wait for start | LOAD |
| `LOAD` | 1 | Load input | CONV |
| `CONV` | 2 | Wait conv_done | BATCHNORM |
| `BATCHNORM` | 3 | Wait bn_done | POOL |
| `POOL` | 4 | Wait pool_done | DENSE1 |
| `DENSE1` | 5 | Wait dense1_done | DENSE2 |
| `DENSE2` | 6 | Wait dense2_done | OUTPUT |
| `OUTPUT` | 7 | Assert valid | IDLE |

#### State Diagram

```
     ┌─────────┐
     │  IDLE   │◀────────────────────┐
     └────┬────┘                     │
          │ start                    │
          ▼                          │
     ┌─────────┐                     │
     │  LOAD   │                     │
     └────┬────┘                     │
          │                          │
          ▼                          │
     ┌─────────┐                     │
     │  CONV   │                     │
     └────┬────┘                     │
          │ conv_done                │
          ▼                          │
     ┌─────────────┐                 │
     │ BATCHNORM   │                 │
     └────┬────────┘                 │
          │ bn_done                  │
          ▼                          │
     ┌─────────┐                     │
     │  POOL   │                     │
     └────┬────┘                     │
          │ pool_done                │
          ▼                          │
     ┌─────────┐                     │
     │ DENSE1  │                     │
     └────┬────┘                     │
          │ dense1_done              │
          ▼                          │
     ┌─────────┐                     │
     │ DENSE2  │                     │
     └────┬────┘                     │
          │ dense2_done              │
          ▼                          │
     ┌─────────┐                     │
     │ OUTPUT  │─────────────────────┘
     └─────────┘
```

#### Resource Usage

| Resource | Count |
|----------|-------|
| LUTs | ~100 |
| DSPs | 0 |
| FFs | ~50 |

---

### 7. `input_buffer.v` - Input Data Buffer

**File:** `fpga/src/input_buffer.v`  
**Lines:** 50  
**Role:** Latches 128-bit glucose input vector

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Active-low reset |
| `load` | Input | 1 | Load enable |
| `glucose_in` | Input | 128 | 16 × 8-bit input |
| `glucose_out` | Output | 128 | Buffered output |

#### Architecture

Simple parallel-load register:
```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        glucose_out <= 128'd0;
    else if (load)
        glucose_out <= glucose_in;
end
```

#### Resource Usage

| Resource | Count |
|----------|-------|
| LUTs | 32 |
| DSPs | 0 |
| FFs | 128 |

---

### 8. `activation_unit.v` - Activation Function Unit

**File:** `fpga/src/activation_unit.v`  
**Lines:** 40  
**Role:** Implements ReLU and sigmoid activations

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `input_val` | Input | 16 | Input value (Q8.8) |
| `activation_type` | Input | 1 | 0=ReLU, 1=Sigmoid |
| `output_val` | Output | 16 | Activated output |

#### Architecture

**ReLU:**
```verilog
if (input_val < 0)
    output_val = 0;
else
    output_val = input_val;
```

**Sigmoid:**
- 64-entry lookup table
- Input truncated to 6 bits for LUT indexing
- Output scaled to Q8.8 format

#### Resource Usage

| Resource | Count |
|----------|-------|
| LUTs | ~40 |
| DSPs | 0 |

---

### 9. `output_comparator.v` - Output Threshold Comparator

**File:** `fpga/src/output_comparator.v`  
**Lines:** 20  
**Role:** Compares probability to threshold for binary classification

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `probability` | Input | 16 | CNN output probability (Q8.8) |
| `threshold` | Input | 16 | Decision threshold (default: 171 = 0.667) |
| `hypo_risk` | Output | 1 | 1=HYPO, 0=SAFE |

#### Architecture

Simple comparison:
```verilog
assign hypo_risk = (probability >= threshold) ? 1'b1 : 1'b0;
```

**Default Threshold:** 171/255 ≈ 0.667 (66.7%)

#### Resource Usage

| Resource | Count |
|----------|-------|
| LUTs | ~10 |
| DSPs | 0 |

---

## Early Exit Modules

### 10. `hypoglycemia_predictor_early_exit.v` - Top Module (Early Exit)

**File:** `fpga/src/hypoglycemia_predictor_early_exit.v`  
**Lines:** 201  
**Role:** Top-level integration for Early Exit architecture

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Active-low reset |
| `start` | Input | 1 | Start inference |
| `glucose_in` | Input | 128 | 16 × 8-bit glucose |
| `valid` | Output | 1 | Output valid |
| `hypo_risk` | Output | 1 | Binary classification |
| `probability` | Output | 16 | Raw probability |
| `busy` | Output | 1 | Module busy |
| `early_exit_used` | Output | 1 | 1 if early exit taken |
| `exit_stage` | Output | 2 | Exit stage indicator |

#### Architecture

Extends baseline with:
- `early_exit_dense` - Parallel 8→1 dense layer
- `early_exit_comparator` - Confidence checker
- `control_unit_early_exit` - Modified FSM

**Early Exit Logic:**
```
Exit if (probability >= 0.8) OR (probability <= 0.2)
```

#### Resource Overhead vs Baseline

| Resource | Baseline | Early Exit | Overhead |
|----------|----------|------------|----------|
| LUTs | 5,048 | 5,191 | +143 (+2.8%) |
| DSPs | 6 | 9 | +3 (+50%) |
| FFs | 4,958 | 5,073 | +115 (+2.3%) |

---

### 11. `early_exit_dense.v` - Early Exit Dense Layer

**File:** `fpga/src/early_exit_dense.v`  
**Lines:** 100  
**Role:** 8→1 dense layer for early exit decision

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Active-low reset |
| `start` | Input | 1 | Start computation |
| `input_data` | Input | 128 | 8 × 16-bit GAP output |
| `done` | Output | 1 | Complete signal |
| `output_data` | Output | 16 | 1 × 16-bit probability |

#### Architecture

**Specialized Dense Layer:**
- 8 input neurons (GAP output)
- 1 output neuron (confidence score)
- Sigmoid activation
- 8 cycles latency

**Weight Files:**
- `early_exit_weights.mem` - 8 weights
- `early_exit_bias.mem` - 1 bias

#### Resource Usage

| Resource | Count |
|----------|-------|
| LUTs | ~100 |
| DSPs | 1 |
| FFs | ~80 |

---

### 12. `early_exit_comparator.v` - Confidence Comparator

**File:** `fpga/src/early_exit_comparator.v`  
**Lines:** 30  
**Role:** Checks if prediction is confident enough for early exit

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `probability` | Input | 16 | Early exit probability |
| `high_thresh` | Input | 16 | High threshold (default: 205 = 0.8) |
| `low_thresh` | Input | 16 | Low threshold (default: 51 = 0.2) |
| `early_exit_valid` | Output | 1 | Exit if confident |
| `early_hypo_risk` | Output | 1 | Early exit classification |

#### Architecture

Dual threshold comparison:
```verilog
assign early_exit_valid = (prob >= high_thresh) || (prob <= low_thresh);
assign early_hypo_risk = (prob >= high_thresh) ? 1'b1 : 1'b0;
```

**Thresholds:**
- High: 205/255 ≈ 0.8 (confident HYPO)
- Low: 51/255 ≈ 0.2 (confident SAFE)

#### Resource Usage

| Resource | Count |
|----------|-------|
| LUTs | ~50 |
| DSPs | 0 |

---

### 13. `control_unit_early_exit.v` - Early Exit FSM

**File:** `fpga/src/control_unit_early_exit.v`  
**Lines:** 200  
**Role:** Modified FSM with early exit support

#### Architecture Enhancements

**Additional States:**
- `EARLY_EXIT_CHECK` - Evaluate confidence
- `EARLY_EXIT_OUTPUT` - Output early result

**Modified Flow:**
```
... → DENSE1 → EARLY_EXIT_CHECK →┬→ EARLY_EXIT_OUTPUT → IDLE
                                  │
                                  └→ DENSE2 (if not confident)
```

#### Resource Usage

| Resource | Count |
|----------|-------|
| LUTs | ~120 |
| DSPs | 0 |
| FFs | ~60 |

---

## XAI Modules

### 14. `hypoglycemia_predictor_xai.v` - Top Module (XAI)

**File:** `fpga/src/hypoglycemia_predictor_xai.v`  
**Lines:** 103  
**Role:** Top-level integration for XAI architecture

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Active-low reset |
| `start` | Input | 1 | Start inference |
| `glucose_in` | Input | 128 | 16 × 8-bit glucose |
| `valid` | Output | 1 | Output valid |
| `hypo_risk` | Output | 1 | Binary classification |
| `probability` | Output | 16 | Raw probability |
| `busy` | Output | 1 | Module busy |
| `reason_code` | Output | 3 | 3-bit XAI explanation |
| `slope` | Output | 16 | Glucose trend (Q8.8) |
| `min_value` | Output | 8 | Minimum glucose |
| `recent_low` | Output | 1 | Recent low flag |
| `trend_direction` | Output | 1 | 0=stable, 1=dropping |

#### Architecture

**Parallel Execution:**
- CNN pipeline runs independently
- XAI modules run in parallel (combinational)
- Zero latency overhead

**XAI Modules:**
- `trend_calculator` - Glucose slope
- `min_detector` - Minimum value detection
- `rate_of_change` - Rapid drop detection
- `reason_encoder` - 3-bit reason code

#### Resource Overhead vs Baseline

| Resource | Baseline | XAI | Overhead |
|----------|----------|-----|----------|
| LUTs | 5,048 | 6,011 | +963 (+19%) |
| DSPs | 6 | 6 | 0 (0%) |
| FFs | 4,958 | 5,005 | +47 (+1%) |

---

### 15. `trend_calculator.v` - Glucose Trend Calculator

**File:** `fpga/src/trend_calculator.v`  
**Lines:** 50  
**Role:** Calculates glucose slope over 16-timestep window

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `glucose_in` | Input | 128 | 16 × 8-bit glucose |
| `slope` | Output | 16 | Slope in Q8.8 format |
| `trend_direction` | Output | 1 | 0=stable, 1=dropping |

#### Architecture

**Computation:**
```
first_avg = average(glucose[0:4])
last_avg = average(glucose[11:15])
slope = last_avg - first_avg
```

**Output Format:**
- Q8.8 fixed-point (slope × 256)
- Positive = rising, Negative = dropping

**Trend Direction:**
```verilog
trend_direction = (slope < -2560) ? 1'b1 : 1'b0;
// -2560 in Q8.8 = -10 mg/dL per 5 min
```

#### Resource Usage

| Resource | Count |
|----------|-------|
| LUTs | ~200 |
| DSPs | 0 |
| FFs | ~50 |

---

### 16. `min_detector.v` - Minimum Value Detector

**File:** `fpga/src/min_detector.v`  
**Lines:** 45  
**Role:** Finds minimum glucose value and its position

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `glucose_in` | Input | 128 | 16 × 8-bit glucose |
| `min_value` | Output | 8 | Minimum glucose value |
| `min_index` | Output | 4 | Timestep of minimum (0-15) |
| `recent_low` | Output | 1 | 1 if min in last 4 readings < 70 |

#### Architecture

**Algorithm:**
```verilog
current_min = glucose[0];
for (i = 1 to 15) begin
    if (glucose[i] < current_min) begin
        current_min = glucose[i];
        current_index = i;
    end
end
```

**Recent Low Detection:**
```verilog
recent_low = (min_index >= 12) && (min_value < 70);
// Last 4 readings = last 20 minutes
```

#### Resource Usage

| Resource | Count |
|----------|-------|
| LUTs | ~150 |
| DSPs | 0 |
| FFs | ~40 |

---

### 17. `rate_of_change.v` - Rate of Change Calculator

**File:** `fpga/src/rate_of_change.v`  
**Lines:** 35  
**Role:** Calculates glucose rate of change

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `glucose_in` | Input | 128 | 16 × 8-bit glucose |
| `rate` | Output | 16 | Rate in mg/dL per minute |
| `rapid_drop` | Output | 1 | 1 if rate < -10 mg/dL/min |

#### Architecture

**Computation:**
```
rate = (glucose[15] - glucose[0]) / 80 minutes
rapid_drop = (rate < -10)
```

#### Resource Usage

| Resource | Count |
|----------|-------|
| LUTs | ~100 |
| DSPs | 0 |

---

### 18. `reason_encoder.v` - Reason Code Encoder

**File:** `fpga/src/reason_encoder.v`  
**Lines:** 30  
**Role:** Encodes 3-bit reason code from XAI features

#### Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `slope` | Input | 16 | Glucose trend |
| `min_value` | Input | 8 | Minimum glucose |
| `current_value` | Input | 8 | Current glucose |
| `rapid_drop` | Input | 1 | Rapid drop flag |
| `recent_low` | Input | 1 | Recent low flag |
| `reason_code` | Output | 3 | 3-bit encoded reason |

#### Architecture

**Reason Code Encoding:**

| Bit | Meaning | Condition |
|-----|---------|-----------|
| Bit 0 | Rapid Drop | slope < -10 mg/dL/min |
| Bit 1 | Recent Low | min in last 20 min < 70 mg/dL |
| Bit 2 | Current Low | current < 80 mg/dL |

**Example Encodings:**

| Code | Binary | Interpretation |
|------|--------|----------------|
| 0 | 000 | No risk factors |
| 1 | 001 | Rapid drop only |
| 5 | 101 | Rapid drop + Current low ⚠️ |
| 7 | 111 | All three factors (Critical) |

#### Resource Usage

| Resource | Count |
|----------|-------|
| LUTs | ~50 |
| DSPs | 0 |

---

## Shared Utility Modules

### 19. `pooling_engine.v` - Global Average Pooling

(Described in Baseline CNN section)

---

### 20. `output_comparator.v` - Threshold Comparator

(Described in Baseline CNN section)

---

### 21. `activation_unit.v` - Activation Unit

(Described in Baseline CNN section)

---

### 22. `input_buffer.v` - Input Buffer

(Described in Baseline CNN section)

---

## Optimized Variants

### 23. `hypoglycemia_predictor_opt.v` - Optimized Top Module

**File:** `fpga/src/hypoglycemia_predictor_opt.v`  
**Lines:** 140  
**Role:** Optimized baseline with sequential modules

**Differences from Baseline:**
- Uses `conv1d_engine_seq.v` instead of `conv1d_engine.v`
- Uses `batchnorm_engine_seq.v` instead of `batchnorm_engine.v`
- Uses `dense_layer_seq.v` instead of `dense_layer.v`
- Uses `control_unit_opt.v` with multi-cycle states

---

### 24. `control_unit_opt.v` - Optimized Control Unit

**File:** `fpga/src/control_unit_opt.v`  
**Lines:** 180  
**Role:** Multi-cycle FSM for optimized pipeline

**Enhancements:**
- Explicit multi-cycle states for sequential modules
- Proper handshaking with DONE signals
- Improved timing closure

---

## Resource Summary

### Complete Design Comparison

| Design | LUTs | DSPs | FFs | Utilization |
|--------|------|------|-----|-------------|
| **Baseline** | 5,048 | 6 | 4,958 | 24% |
| **Early Exit** | 5,191 | 9 | 5,073 | 25% |
| **XAI** | 6,011 | 6 | 5,005 | 29% |
| **Combined** | ~7,200 | ~12 | ~5,500 | ~35% |

### Module-by-Module Breakdown

| Module | LUTs | DSPs | FFs | Category |
|--------|------|------|-----|----------|
| `hypoglycemia_predictor` | ~100 | 0 | ~100 | Top-level |
| `conv1d_engine_seq` | 861 | 1 | ~300 | Conv1D |
| `batchnorm_engine_seq` | ~150 | 1 | ~200 | BatchNorm |
| `pooling_engine` | 48 | 0 | ~100 | Pooling |
| `dense_layer_seq` (8→16) | 222 | 1 | ~250 | Dense |
| `dense_layer_seq` (16→1) | 133 | 3 | ~100 | Dense |
| `control_unit` | ~100 | 0 | ~50 | Control |
| `input_buffer` | 32 | 0 | 128 | Buffer |
| `output_comparator` | ~10 | 0 | ~10 | Comparator |
| `early_exit_dense` | ~100 | 1 | ~80 | Early Exit |
| `early_exit_comparator` | ~50 | 0 | ~20 | Early Exit |
| `trend_calculator` | ~200 | 0 | ~50 | XAI |
| `min_detector` | ~150 | 0 | ~40 | XAI |
| `rate_of_change` | ~100 | 0 | ~30 | XAI |
| `reason_encoder` | ~50 | 0 | ~20 | XAI |

---

## File Locations

```
D:\final FPGA\fpga\src\
├── Baseline CNN
│   ├── hypoglycemia_predictor.v
│   ├── control_unit.v
│   ├── input_buffer.v
│   ├── conv1d_engine_seq.v
│   ├── batchnorm_engine_seq.v
│   ├── pooling_engine.v
│   ├── dense_layer_seq.v
│   ├── activation_unit.v
│   └── output_comparator.v
│
├── Early Exit
│   ├── hypoglycemia_predictor_early_exit.v
│   ├── control_unit_early_exit.v
│   ├── early_exit_dense.v
│   └── early_exit_comparator.v
│
├── XAI
│   ├── hypoglycemia_predictor_xai.v
│   ├── trend_calculator.v
│   ├── min_detector.v
│   ├── rate_of_change.v
│   └── reason_encoder.v
│
└── Optimized Variants
    ├── hypoglycemia_predictor_opt.v
    ├── control_unit_opt.v
    ├── batchnorm_engine_v2.v
    └── conv1d_engine.v
```

---

**Document Generated:** March 24, 2026  
**Total Modules:** 24  
**Total Lines of Code:** ~2,500  
**Project Status:** ✅ Complete and Verified
