# Optimized RTL Verification Plan
## Hypoglycemia Predictor CNN - Testing Strategy

**Date:** March 23, 2026  
**Status:** Ready for Testing

---

## Why Testing is Critical

We made **major architectural changes**:
- Parallel → Sequential computation
- Changed control FSM timing
- Pre-computed BatchNorm parameters
- Modified multiplier implementations

**Risk:** Optimizations may have introduced bugs or changed numerical results.

---

## Verification Strategy

### Level 1: Compile Check ✅
```bash
cd fpga
iverilog -o sim_opt.vvp src/*.v tb/tb_hypoglycemia_predictor.v
```
**Goal:** Ensure code compiles without errors

---

### Level 2: Self-Consistency Test ⏳
```bash
vvp sim_opt.vvp
```
**Goal:** Internal testbench checks pass (existing testbenches)

**What it checks:**
- No simulation hangs
- Done signals assert correctly
- Output values are valid (no X/Z states)

---

### Level 3: Python Model Comparison ⏳ **(MOST IMPORTANT)**
```bash
python compare_rtl_vs_python.py
```
**Goal:** RTL outputs match Python model predictions

**What it checks:**
- Conv1D outputs match Python Conv1D
- Full pipeline output matches Python model
- Classification (HYPO/SAFE) is correct

**Acceptance Criteria:**
- Conv1D: 128/128 outputs match (100%)
- Final output: ±1 LSB tolerance (Q8.8 quantization)
- Classification: 100% match

---

### Level 4: Golden Vector Comparison ⏳
```bash
python verify_rtl_output.py
```
**Goal:** Compare against pre-computed golden vectors

**What it checks:**
- 20 test samples from test dataset
- Each sample's output matches golden reference
- Early exit behavior (if implemented)

---

## Test Files Needed

### Existing Testbenches (Need Update)

| File | Status | Action Needed |
|------|--------|---------------|
| `tb_conv1d_engine.v` | ⚠️ Old | Update module instantiation |
| `tb_batchnorm_engine.v` | ⚠️ Old | Update module name |
| `tb_pooling_engine.v` | ✅ OK | No changes needed |
| `tb_dense_layer.v` | ⚠️ Old | Update module name |
| `tb_hypoglycemia_predictor.v` | ⚠️ Old | Update to use `_opt` modules |

### New Testbenches to Create

| File | Purpose | Priority |
|------|---------|----------|
| `tb_hypoglycemia_predictor_opt.v` | Top-level testbench for optimized design | **HIGH** |
| `tb_conv1d_seq.v` | Test sequential Conv1D | Medium |
| `tb_batchnorm_seq.v` | Test sequential BatchNorm | Medium |

---

## Step-by-Step Testing Procedure

### Step 1: Update Testbenches for Optimized RTL

The existing testbenches instantiate the old module names. We need to update them.

**File:** `fpga/tb/tb_hypoglycemia_predictor.v`

**Change:**
```verilog
// OLD (will not work with optimized RTL)
hypoglycemia_predictor dut (
    .clk(clk),
    .rst_n(rst_n),
    ...
);

// NEW (use optimized version)
hypoglycemia_predictor_opt dut (
    .clk(clk),
    .rst_n(rst_n),
    ...
);
```

---

### Step 2: Compile and Run Simulation

```bash
cd D:\final FPGA\fpga

# Compile optimized design with testbench
iverilog -o sim_opt.vvp \
    src/input_buffer.v \
    src/conv1d_engine_seq.v \
    src/batchnorm_engine_seq.v \
    src/pooling_engine.v \
    src/dense_layer_seq.v \
    src/control_unit_opt.v \
    src/hypoglycemia_predictor_opt.v \
    src/output_comparator.v \
    tb/tb_hypoglycemia_predictor.v

# Run simulation
vvp sim_opt.vvp
```

**Expected Output:**
```
tb_hypoglycemia_predictor: PASS
```

---

### Step 3: Compare with Python Model

```bash
cd D:\final FPGA
python compare_rtl_vs_python.py
```

**Expected Output:**
```
======================================================================
DIRECT RTL vs PYTHON MODEL COMPARISON
======================================================================

STEP 1: Running RTL Simulation
...
RTL outputs captured for 4 test cases

STEP 2: Computing Python Model Conv1D Output
...

STEP 3: Comparing RTL vs Python Conv1D Output
======================================================================
Maximum difference: 0
Mean difference: 0.0000
Exact matches: 128 / 128 (100.00%)

VERDICT: RTL MATCHES PYTHON MODEL
======================================================================
```

---

### Step 4: Check All Test Cases

Run full verification:

```bash
python verify_rtl_output.py
```

**Expected Output:**
```
[PASS] Conv1D Layer
[PASS] BatchNorm Layer
[PASS] Pooling Layer
[PASS] Dense Layers
[PASS] Full Pipeline (Top-Level)

VERIFICATION STATUS: ALL TESTBENCHES PASSED
```

---

## Known Issues to Watch For

### Issue 1: Module Name Mismatch

**Symptom:** Compilation error "module not found"

**Fix:** Ensure testbench instantiates `hypoglycemia_predictor_opt`, not `hypoglycemia_predictor`

---

### Issue 2: Timing Mismatch

**Symptom:** Testbench expects output in 1 cycle, but optimized design takes multiple cycles

**Fix:** Update testbench to wait for `done` signal properly:
```verilog
// Wait for done with timeout
timeout = 0;
while ((done !== 1'b1) && (timeout < 1000)) begin
    timeout = timeout + 1;
    @(posedge clk);
end
```

---

### Issue 3: Pre-computed BatchNorm Values

**Symptom:** BatchNorm outputs don't match Python

**Check:** Ensure `bn1_scale.mem` and `bn1_shift.mem` files exist and are loaded correctly

**Debug:**
```verilog
// Add to testbench
$display("scale[0] = %h", scale[0]);
$display("shift[0] = %h", shift[0]);
```

---

### Issue 4: Q8.8 Quantization Differences

**Symptom:** RTL output differs from Python by ±1 LSB

**Cause:** Rounding differences in fixed-point conversion

**Acceptance:** ±1 LSB is acceptable for Q8.8 format

---

## Test Coverage Goals

| Test Category | Coverage Goal | Status |
|---------------|---------------|--------|
| **Module-Level** | All 7 modules tested | ⏳ Pending |
| **Integration** | Full pipeline tested | ⏳ Pending |
| **Functional** | Matches Python model | ⏳ Pending |
| **Corner Cases** | Zeros, max values, negatives | ⏳ Pending |
| **Performance** | Timing closure at 50 MHz | ⏳ Pending |

---

## Debugging Tips

### Tip 1: Dump Waveforms

Add to testbench:
```verilog
initial begin
    $dumpfile("debug.vcd");
    $dumpvars(0, tb_hypoglycemia_predictor);
end
```

View in GTKWave:
```bash
gtkwave debug.vcd
```

### Tip 2: Print Internal Signals

Add to testbench:
```verilog
always @(posedge clk) begin
    if (start) $display("START at time %0t", $time);
    if (done) $display("DONE at time %0t", $time);
    if (valid) $display("VALID: probability=%0d, hypo_risk=%0b", probability, hypo_risk);
end
```

### Tip 3: Compare Intermediate Results

Don't just check final output - check intermediate layers:
```python
# In compare_rtl_vs_python.py
print("Python Conv1D output[0][0] =", python_conv_output[0, 0])
print("RTL Conv1D output[0][0] =", rtl_outputs['test_input_mem'][0, 0])
```

---

## Success Criteria

### Must Pass (Blocking)

- [ ] **All testbenches compile** without errors
- [ ] **No simulation hangs** (all tests complete)
- [ ] **Conv1D matches Python** (128/128 exact match)
- [ ] **Full pipeline classification** matches Python (100%)

### Should Pass (Non-Blocking)

- [ ] BatchNorm outputs match (±1 LSB acceptable)
- [ ] Dense layer outputs match (±1 LSB acceptable)
- [ ] Timing closure at 50 MHz
- [ ] No critical warnings in synthesis

### Nice to Have

- [ ] Waveform dumps for visual inspection
- [ ] Coverage reports
- [ ] Performance benchmarks

---

## Test Schedule

| Phase | Task | Duration | Owner |
|-------|------|----------|-------|
| **Phase 1** | Update testbenches | 1 hour | RTL Team |
| **Phase 2** | Compile & debug | 2 hours | RTL Team |
| **Phase 3** | Python comparison | 1 hour | Verification Team |
| **Phase 4** | Full verification | 2 hours | Verification Team |
| **Phase 5** | Documentation | 1 hour | Documentation Team |
| **Total** | | **7 hours** | |

---

## Next Steps After Testing

### If All Tests Pass ✅

1. ✅ Proceed to Early Exit implementation
2. ✅ Run implementation (place & route)
3. ✅ Generate bitstream
4. ✅ Hardware validation

### If Tests Fail ❌

1. ❌ Debug failing tests
2. ❌ Fix RTL bugs
3. ❌ Re-run synthesis
4. ❌ Re-test (return to Step 1)

---

## Contact & Support

For testing issues:
- Check `RTL_VERIFICATION_GUIDE.md` for general verification methodology
- Review `compare_rtl_vs_python.py` for Python comparison script
- See `RTL_OPTIMIZATION_RESULTS.md` for optimization details

---

*Document Version: 1.0*
*Last Updated: March 23, 2026*
*Status: Ready for Testing*
