# RTL Verification Guide
## Hypoglycemia Predictor CNN on FPGA

---

## Overview

This document explains how to verify that your RTL implementation matches the trained Python CNN model.

---

## Verification Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    VERIFICATION WORKFLOW                        │
│                                                                 │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────────┐  │
│  │ Python Model│────▶│ Export Weights│────▶│ Golden Vectors  │  │
│  │  (Keras)    │     │  (.mem files) │     │ (expected out)  │  │
│  └─────────────┘     └──────────────┘     └─────────────────┘  │
│         ▲                                          │           │
│         │                                          ▼           │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────────┐  │
│  │  Compare &  │◀────│  RTL Sim     │◀────│ Testbench loads │  │
│  │  Verify     │     │  Output      │     │ golden vectors  │  │
│  └─────────────┘     └──────────────┘     └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Generate Golden Reference Vectors

Run the Python script to export weights and generate test vectors:

```bash
cd D:\final FPGA
python export_weights.py
```

**Output files:**
| File | Description |
|------|-------------|
| `mem_files/conv1_weights.mem` | Conv1D weights (Q8.8) |
| `mem_files/conv1_bias.mem` | Conv1D biases |
| `mem_files/bn1_*.mem` | BatchNorm parameters |
| `mem_files/dense1_*.mem` | Dense layer 1 weights |
| `mem_files/output_*.mem` | Output layer weights |
| `mem_files/golden_test_vectors.json` | **Golden references from Python** |
| `mem_files/rtl_golden_vectors.hex` | RTL-compatible format |
| `mem_files/test_cases/test_XX_*.mem` | Individual test cases |

---

## Step 2: Copy .mem Files to Simulation Directory

```bash
# Copy all .mem files to FPGA simulation directory
copy mem_files\*.mem fpga\
copy mem_files\test_input.mem fpga\
```

**Required files in `fpga/` directory:**
- `conv1_weights.mem`, `conv1_bias.mem`
- `bn1_gamma.mem`, `bn1_beta.mem`, `bn1_mean.mem`, `bn1_variance.mem`
- `dense1_weights.mem`, `dense1_bias.mem`
- `output_weights.mem`, `output_bias.mem`
- `test_input.mem`

---

## Step 3: Run Testbenches (Vivado)

### Option A: Run Individual Module Testbenches

```tcl
# In Vivado Tcl console or .tcl script
set_property top tb_conv1d_engine [current_fileset]
launch_simulation
run 1000ns
# Check console for "tb_conv1d_engine: PASS"
```

### Option B: Run Top-Level Testbench

```tcl
set_property top tb_hypoglycemia_predictor [current_fileset]
launch_simulation
run 5000ns
# Check console for "tb_hypoglycemia_predictor: PASS"
```

### Option C: Run Golden Reference Testbench

```tcl
set_property top tb_conv1d_engine_golden [current_fileset]
launch_simulation
run 2000ns
```

---

## Step 4: Verify RTL vs Python Model

### Method 1: Compare Testbench Output

The testbench compares RTL output against computed expected values:

```
tb_conv1d_engine: PASS    ← RTL matches expected
tb_conv1d_engine: FAIL    ← Mismatch detected
```

### Method 2: Manual Waveform Inspection

1. Open **Simulation → Waveform** in Vivado
2. Add signals: `input_data`, `output_data`, `done`, `start`
3. Run simulation
4. Compare `output_data` with expected values from `golden_test_vectors.json`

### Method 3: Python Comparison Script

```python
# verify_rtl_output.py
import json
import numpy as np

# Load golden reference
with open('mem_files/golden_test_vectors.json') as f:
    golden = json.load(f)

# Load RTL output (from simulation log or file)
rtl_output = [...]  # Parse from simulation

for i, tv in enumerate(golden):
    expected = tv['output_q8_8']
    actual = rtl_output[i]
    if expected != actual:
        print(f"MISMATCH test {i}: expected={expected}, got={actual}")
    else:
        print(f"PASS test {i}")
```

---

## Testbench Summary

| Testbench | Tests | Golden Reference | Use Case |
|-----------|-------|------------------|----------|
| `tb_conv1d_engine.v` | Conv1D only | Computed in TB | Module debugging |
| `tb_batchnorm_engine.v` | BatchNorm only | Computed in TB | Module debugging |
| `tb_pooling_engine.v` | Pooling only | Computed in TB | Module debugging |
| `tb_dense_layer.v` | Dense layers | Computed in TB | Module debugging |
| `tb_hypoglycemia_predictor.v` | **Full pipeline** | Computed in TB | **Integration test** |
| `tb_conv1d_engine_golden.v` | Conv1D with corners | Computed in TB | Enhanced coverage |

---

## What Each Testbench Verifies

### tb_conv1d_engine
- **Input:** 16 timesteps × 8-bit glucose values
- **Output:** 16×8 = 128 outputs (16-bit Q8.8 each)
- **Verification:** 1D convolution with 3-tap kernel, 8 filters

### tb_batchnorm_engine
- **Input:** 16×8 fixed-point values
- **Output:** Normalized values
- **Verification:** y = (x - mean) × scale + shift

### tb_pooling_engine
- **Input:** 16×8 values
- **Output:** 8 values (max-pool + average)
- **Verification:** Max of pairs, then divide by 8

### tb_dense_layer
- **Dense1:** 8 inputs → 16 outputs (ReLU)
- **Dense2:** 16 inputs → 1 output (Sigmoid)
- **Verification:** Matrix multiply + activation

### tb_hypoglycemia_predictor
- **Input:** 128-bit glucose vector (16 × 8-bit)
- **Output:** `probability` (16-bit), `hypo_risk` (1-bit)
- **Verification:** **Full CNN pipeline end-to-end**

---

## Expected Results

### Passing Simulation
```
tb_conv1d_engine: PASS
tb_batchnorm_engine: PASS
tb_pooling_engine: PASS
tb_dense_layer: PASS
tb_hypoglycemia_predictor: PASS
```

### Failing Simulation (Example)
```
MISMATCH test_input.mem: t=3 f=2 exp=1234 got=1256
tb_conv1d_engine: FAIL (3 mismatches)
```

---

## Debugging Mismatches

### 1. Check Weight Files
```tcl
# In simulation, inspect weight arrays
read_mem conv1_weights.mem conv_w
# Verify weights loaded correctly
```

### 2. Check Fixed-Point Format
- Python uses float32
- RTL uses Q8.8 (8 integer + 8 fractional bits)
- Conversion: `fixed = int(float * 256)`

### 3. Check Saturation
- RTL saturates to [-32768, 32767]
- Python may not saturate
- Large values may differ

### 4. Check Sigmoid Implementation
- RTL uses 32-entry LUT + interpolation
- Python uses exact sigmoid
- Small differences expected (±1 LSB)

---

## Acceptance Criteria

| Metric | Target | How to Verify |
|--------|--------|---------------|
| Output accuracy | ±2 LSB | Compare RTL vs Python output |
| Classification match | 100% | `hypo_risk` matches threshold |
| All testbenches | PASS | Console output |
| No X/Z values | Verified | Waveform inspection |

---

## Quick Start Commands

```bash
# 1. Generate weights and golden vectors
python export_weights.py

# 2. Copy .mem files to fpga/
copy mem_files\*.mem fpga\

# 3. Open Vivado
vivado -project fpga/fpga.xpr

# 4. Run simulation
set_property top tb_hypoglycemia_predictor [current_fileset]
launch_simulation
run 5000ns

# 5. Check console for PASS/FAIL
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `$readmemh` file not found | Copy .mem files to sim directory |
| Timeout waiting for `done` | Check clock/reset, verify FSM |
| All outputs zero | Check weights loaded, verify `start` pulse |
| Mismatch on sigmoid | ±1 LSB is acceptable (LUT approximation) |
| Large mismatch (>10%) | Check Q-format conversion |

---

## Next Steps After Verification

1. ✅ All testbenches pass → Proceed to synthesis
2. ⚠️ Small mismatches (±1-2 LSB) → Acceptable, document
3. ❌ Large mismatches → Debug weight files, check Q-format

---

## Document Revision

| Date | Author | Changes |
|------|--------|---------|
| 2026-03-23 | RTL Verification | Initial version |
