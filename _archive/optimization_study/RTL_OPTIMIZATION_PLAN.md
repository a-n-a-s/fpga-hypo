# RTL Optimization Plan
## Hypoglycemia Predictor CNN - Resource Optimization

**Date:** March 23, 2026
**Target:** Reduce utilization to <80% LUT, <50% DSP

---

## Current Issues

| Resource | Current | Target | Issue |
|----------|---------|--------|-------|
| LUTs | 32,623 (156%) | <16,000 (80%) | Weights in LUTs, no BRAM |
| DSPs | 90 (100%) | <45 (50%) | Too parallel |
| FFs | 4,619 (11%) | <3,000 | OK |
| BRAM | 0 (0%) | 3-5 (6-10%) | Not utilized |

---

## Optimization Strategy

### 1. Move Weights to BRAM (Highest Priority)

**Problem:** 225 weights × 16 bits = 3,600 bits stored in LUTs

**Solution:** Add `rom_style = "block"` attributes

**Files to modify:**
- `conv1d_engine.v` (24 weights + 8 biases)
- `batchnorm_engine.v` (32 params for scale/shift)
- `dense_layer.v` (128 weights + 16 biases)

**Expected savings:** ~8,000 LUTs

---

### 2. Reduce DSP Usage (High Priority)

**Problem:** 90 DSPs used (all parallel multipliers)

**Current architecture:**
- Conv1D: 8 filters × 3 kernels = 24 multipliers (all parallel)
- BatchNorm: 8 multipliers (all parallel)
- Dense1: 8×16 = 128 multipliers (inferred as DSPs)
- Dense2: 16×1 = 16 multipliers

**Solution:** Time-multiplex with sequential MAC

**New architecture:**
- Conv1D: 2 DSPs (reuse over 16 timesteps × 8 filters)
- BatchNorm: 1 DSP (reuse over 16×8 outputs)
- Dense1: 2 DSPs (sequential over 8 inputs × 16 outputs)
- Dense2: 1 DSP

**Total:** 6 DSPs (vs 90 current)

**Expected savings:** 84 DSPs

---

### 3. Add Pipelining (Medium Priority)

**Problem:** All computation in single cycle → long critical path → LUT duplication

**Solution:** Pipeline each module

```
Conv1D:   16 cycles (1 output per cycle)
BatchNorm: 128 cycles (1 output per cycle)
Dense1:   16 cycles (1 output per cycle)
Dense2:   1 cycle
```

**Expected savings:** ~2,000 LUTs (less duplication)

---

### 4. Remove Pre-computation Logic (Medium Priority)

**Problem:** BatchNorm pre-computes scale/shift in `initial` block using complex math

**Solution:** Pre-compute in Python, store final values in .mem files

**Files to modify:**
- `export_weights.py` - Compute scale/shift in Python
- `batchnorm_engine.v` - Remove pre-computation logic

**Expected savings:** ~1,000 LUTs

---

### 5. Optimize Input/Output (Low Priority)

**Problem:** 150 IOB used (71%)

**Solution:**
- Serialize 128-bit input bus
- Remove debug signals from top level
- Use AXI or simple streaming interface

**Expected savings:** ~100 IOB

---

## Implementation Plan

### Phase 1: BRAM Inference (1 day)

**Files:** `conv1d_engine.v`, `batchnorm_engine.v`, `dense_layer.v`

Add synthesis attributes:
```verilog
(* rom_style = "block" *) reg signed [15:0] conv_w [0:23];
(* rom_style = "block" *) reg signed [15:0] conv_b [0:7];
```

### Phase 2: Sequential Architecture (2 days)

**Files:** All compute engines

Convert from parallel to sequential:
```verilog
// Before (parallel, 1 cycle, 8 DSPs)
for (f = 0; f < 8; f = f + 1) begin
    mult = input * weight[f];
end

// After (sequential, 8 cycles, 1 DSP)
always @(posedge clk) begin
    if (compute_en) begin
        acc <= acc + (input * weight[f]);
        f <= f + 1;
    end
end
```

### Phase 3: Pre-compute BatchNorm (1 day)

**Files:** `export_weights.py`, `batchnorm_engine.v`

Move scale/shift computation to Python:
```python
# Python: Pre-compute scale and shift
scale = gamma / sqrt(variance + epsilon)
shift = beta - mean * scale

# Save to .mem files
write_mem_file(scale, 'bn1_scale.mem')
write_mem_file(shift, 'bn1_shift.mem')
```

Simplify RTL:
```verilog
// Just load and multiply
temp = (input * scale[f]) + shift[f];
```

### Phase 4: Add Control FSM (1 day)

**Files:** `control_unit.v`, all engines

Add ready/valid handshake:
```verilog
// Instead of: start → done (1 cycle)
// Use: start → busy → ready + valid (multi-cycle)
```

---

## Expected Results

| Metric | Current | Optimized | Improvement |
|--------|---------|-----------|-------------|
| LUTs | 32,623 | 12,000 | 63% reduction |
| DSPs | 90 | 6 | 93% reduction |
| FFs | 4,619 | 3,500 | 24% reduction |
| BRAM | 0 | 4 | - |
| Latency | ~281 cycles | ~500 cycles | 78% increase |
| Power | TBD | Lower | Less parallel switching |

---

## Trade-offs

| Aspect | Before | After |
|--------|--------|-------|
| Parallelism | High | Low |
| Latency | Low (281 cyc) | Higher (~500 cyc) |
| Throughput | 1 per 281 cyc | 1 per 500 cyc |
| Resources | Too high | Fits on FPGA |
| Power | High | Lower |

**Note:** For hypoglycemia prediction (once per minute), latency doesn't matter. Resource efficiency is more important.

---

## Files to Create/Modify

### New Files
1. `fpga/src/conv1d_engine_seq.v` - Sequential Conv1D
2. `fpga/src/batchnorm_engine_v2.v` - Simplified BatchNorm
3. `fpga/src/dense_layer_seq.v` - Sequential Dense

### Modified Files
1. `export_weights.py` - Pre-compute BatchNorm scale/shift
2. `fpga/src/control_unit.v` - Multi-cycle FSM
3. `fpga/src/hypoglycemia_predictor.v` - Update instantiation

---

## Verification Plan

1. **Functional check:** Compare outputs with Python model
2. **Resource check:** Synthesize and verify <80% LUT, <50% DSP
3. **Timing check:** Verify timing closure at 50 MHz
4. **Power check:** Estimate power reduction

---

*Document Version: 1.0*
*Last Updated: March 23, 2026*
