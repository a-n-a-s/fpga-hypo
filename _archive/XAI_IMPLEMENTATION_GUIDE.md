# XAI Implementation Guide
## Explainable AI for FPGA Hypoglycemia Predictor

**Date:** March 23, 2026  
**Recommended Approach:** Option 1 - Feature Importance Analysis (Simple & Effective)  
**Implementation Time:** 4-6 hours  
**FPGA Overhead:** ~200-400 LUTs, minimal DSPs

---

## Executive Summary

### Why Add XAI?

| Without XAI | With XAI |
|-------------|----------|
| "HYPO RISK detected (89% confidence)" | "HYPO RISK detected because glucose dropped 15 mg/dL in 5 minutes" |
| Black box prediction | Interpretable explanation |
| Hard to trust | Clinically meaningful |
| Judges ask "Why?" | You show "Because..." |

**XAI makes your project clinically relevant and trustworthy!**

---

## XAI Options Comparison

### Option 1: Feature Importance Analysis ⭐ RECOMMENDED

**What:** Calculate glucose trends and output reason codes

**How:**
- Calculate slope/trend of glucose readings
- Identify minimum glucose in window
- Calculate rate of change
- Output 3-bit "reason code" with prediction

**FPGA Cost:** ~200-400 LUTs, 0-2 DSPs

**Implementation Time:** 4-6 hours

**Example Output:**
```
Prediction: HYPO RISK (prob=0.89)
Reason Code: 101 (binary)
Explanation:
  - Glucose dropping rapidly (slope=-15 mg/dL/min)
  - Current value low (70 mg/dL)
```

**Pros:**
- ✅ Simple to implement (basic arithmetic)
- ✅ Low FPGA overhead
- ✅ Clinically meaningful
- ✅ Easy to verify
- ✅ Great for presentation

**Cons:**
- ⚠️ Limited explanation depth

---

### Option 2: Rule-Based Explanations

**What:** Add interpretable rules alongside CNN

**How:**
- Define clinical rules (e.g., glucose < 60 → HYPO)
- Compare CNN predictions with rules
- Output which rules triggered

**FPGA Cost:** ~500-800 LUTs

**Implementation Time:** 8-10 hours

**Pros:**
- ✅ More detailed explanations
- ✅ Matches clinical reasoning

**Cons:**
- ⚠️ More complex implementation
- ⚠️ Higher FPGA overhead
- ⚠️ More verification work

---

### Option 3: Attention Mechanism

**What:** Show which timesteps model "attended" to most

**How:**
- Add attention weights to CNN
- Output attention map (16 values)
- Highlight important timesteps

**FPGA Cost:** ~1,000-1,500 LUTs, +4-8 DSPs

**Implementation Time:** 2-3 days

**Pros:**
- ✅ Most detailed explanation
- ✅ Research-worthy

**Cons:**
- ❌ Complex implementation
- ❌ High FPGA overhead
- ❌ Long implementation time
- ❌ Hard to verify

---

## 🎯 Why Option 1 is BEST for Your Project

### 1. **Perfect for Your Timeline**
- ✅ 4-6 hours vs 2-3 days for Option 3
- ✅ Can complete before submission
- ✅ Low risk of bugs

### 2. **Minimal FPGA Impact**
- ✅ +200-400 LUTs (vs +1,500 for Option 3)
- ✅ No additional DSPs needed
- ✅ Fits easily on Artix-7 (still <35% utilization)

### 3. **Clinically Meaningful**
- ✅ Doctors understand trends and slopes
- ✅ Matches clinical reasoning
- ✅ Actionable explanations

### 4. **Great for Presentation**
- ✅ Clear visual explanations
- ✅ Easy to demonstrate
- ✅ Judges can understand immediately

### 5. **Complements Early Exit**
- ✅ Both add interpretability
- ✅ Both reduce latency
- ✅ Both are innovative features

---

## 🏗️ Option 1 Architecture

### Block Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    XAI MODULE                                    │
│                                                                  │
│  Input: 16 glucose readings (80 minutes)                        │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │ Trend Calculator │  │ Min Detector     │  │ Rate of      │  │
│  │ (slope)          │  │ (lowest value)   │  │ Change       │  │
│  └────────┬─────────┘  └────────┬─────────┘  └──────┬───────┘  │
│           │                     │                    │          │
│           └─────────────────────┴────────────────────┘          │
│                              │                                   │
│                              ▼                                   │
│                    ┌──────────────────┐                         │
│                    │ Reason Encoder   │                         │
│                    │ (3-bit code)     │                         │
│                    └────────┬─────────┘                         │
│                             │                                    │
└─────────────────────────────┼────────────────────────────────────┘
                              │
                              ▼
                    Output: [hypo_risk, probability, reason_code]
```

---

## 📋 Implementation Details

### Reason Code Encoding (3 bits)

```verilog
// Reason code bits
Bit 0: Rapid drop detected (slope < -10 mg/dL/min)
Bit 1: Recent low detected (min in last 20 min < 70 mg/dL)
Bit 2: Current value low (current < 80 mg/dL)

// Example encodings:
3'b000 = No risk factors detected
3'b001 = Current value low only
3'b010 = Recent low detected only
3'b011 = Current low + Recent low
3'b100 = Rapid drop only
3'b101 = Rapid drop + Current low  ← Most dangerous!
3'b110 = Rapid drop + Recent low
3'b111 = All three risk factors    ← Critical!
```

### Clinical Interpretation

| Reason Code | Binary | Interpretation | Action |
|-------------|--------|----------------|--------|
| Low Risk | 000 | Stable glucose | Continue monitoring |
| Low Risk | 001 | Slightly low | Watch closely |
| Medium Risk | 010 | Recent low | Consider snack |
| Medium Risk | 011 | Low + recent low | Take action |
| High Risk | 100 | Rapid drop | Prepare carbs |
| **High Risk** | **101** | **Rapid drop + low** | **IMMEDIATE ACTION** |
| High Risk | 110 | Drop + recent low | Prepare treatment |
| Critical | 111 | All factors | EMERGENCY |

---

## 📝 RTL Implementation Plan

### New Modules to Create

#### 1. `trend_calculator.v`
```verilog
module trend_calculator (
    input  wire [127:0] glucose_in,  // 16 × 8-bit
    output reg [15:0] slope,         // mg/dL per 5 min
    output reg trend_direction       // 0=stable/rising, 1=dropping
);
    // Calculate linear regression slope
    // Or simple: (last_5_avg - first_5_avg) / 10 min
endmodule
```

#### 2. `min_detector.v`
```verilog
module min_detector (
    input  wire [127:0] glucose_in,  // 16 × 8-bit
    output reg [7:0] min_value,      // Minimum glucose
    output reg [3:0] min_index       // When it occurred
);
    // Find minimum value and its timestep
endmodule
```

#### 3. `rate_of_change.v`
```verilog
module rate_of_change (
    input  wire [127:0] glucose_in,
    output reg [15:0] rate,          // mg/dL per minute
    output reg rapid_drop            // 1 if rate < -10
);
    // Calculate (glucose[15] - glucose[0]) / 80 min
endmodule
```

#### 4. `reason_encoder.v`
```verilog
module reason_encoder (
    input  wire [15:0] slope,
    input  wire [7:0] min_value,
    input  wire [7:0] current_value,
    input  wire rapid_drop,
    output reg [2:0] reason_code
);
    // Encode 3-bit reason code
    always @(*) begin
        reason_code[0] = rapid_drop;
        reason_code[1] = (min_value < 70);
        reason_code[2] = (current_value < 80);
    end
endmodule
```

#### 5. `xai_output_formatter.v`
```verilog
module xai_output_formatter (
    input  wire hypo_risk,
    input  wire [15:0] probability,
    input  wire [2:0] reason_code,
    input  wire [15:0] slope,
    output reg [31:0] xai_output  // Combined output
);
    // Format: [hypo_risk, probability, reason_code, slope]
endmodule
```

---

### Modified Top Module

```verilog
module hypoglycemia_predictor_xai (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [127:0] glucose_in,
    output reg         valid,
    output reg         hypo_risk,
    output reg [15:0]  probability,
    output reg [2:0]   reason_code,      // NEW: XAI output
    output reg [15:0]  slope,            // NEW: Trend info
    output reg         trend_direction,  // NEW: 0=stable, 1=dropping
    output wire        busy
);

    // Existing CNN modules
    hypoglycemia_predictor u_cnn (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .glucose_in(glucose_in),
        .valid(valid),
        .hypo_risk(hypo_risk),
        .probability(probability),
        .busy(busy)
    );

    // NEW: XAI modules
    trend_calculator u_trend (
        .glucose_in(glucose_in),
        .slope(slope),
        .trend_direction(trend_direction)
    );

    min_detector u_min (
        .glucose_in(glucose_in),
        .min_value(min_val),
        .min_index(min_idx)
    );

    rate_of_change u_rate (
        .glucose_in(glucose_in),
        .rate(rate),
        .rapid_drop(rapid_drop_flag)
    );

    reason_encoder u_reason (
        .slope(slope),
        .min_value(min_val),
        .current_value(glucose_in[127:120]),
        .rapid_drop(rapid_drop_flag),
        .reason_code(reason_code)
    );

endmodule
```

---

## 🐍 Python Verification

### New Python Scripts

#### 1. `generate_xai_rules.py`
```python
"""
Generate XAI rules from training data.
Analyzes which trends correlate with hypoglycemia.
"""

import numpy as np
from sklearn.metrics import accuracy_score

# Load data
X_test = np.load('dataset/X_test.npy')
y_test = np.load('dataset/y_test.npy')

# Define XAI rules
def xai_rule_1(glucose):
    """Rapid drop: slope < -10 mg/dL/min"""
    slope = (glucose[-1] - glucose[0]) / 80.0
    return slope < -10

def xai_rule_2(glucose):
    """Recent low: min in last 20 min < 70"""
    return np.min(glucose[-4:]) < 70

def xai_rule_3(glucose):
    """Current low: current < 80"""
    return glucose[-1] < 80

# Evaluate rules
rule1_pred = np.array([xai_rule_1(x) for x in X_test])
rule2_pred = np.array([xai_rule_2(x) for x in X_test])
rule3_pred = np.array([xai_rule_3(x) for x in X_test])

# Combine rules (any 2 out of 3)
combined_pred = ((rule1_pred + rule2_pred + rule3_pred) >= 2).astype(int)

# Calculate accuracy
rule1_acc = accuracy_score(y_test, rule1_pred)
rule2_acc = accuracy_score(y_test, rule2_pred)
rule3_acc = accuracy_score(y_test, rule3_pred)
combined_acc = accuracy_score(y_test, combined_pred)

print(f"Rule 1 (Rapid drop) accuracy: {rule1_acc:.3f}")
print(f"Rule 2 (Recent low) accuracy: {rule2_acc:.3f}")
print(f"Rule 3 (Current low) accuracy: {rule3_acc:.3f}")
print(f"Combined (2/3 rules) accuracy: {combined_acc:.3f}")
```

**Expected Output:**
```
Rule 1 (Rapid drop) accuracy: 0.78
Rule 2 (Recent low) accuracy: 0.82
Rule 3 (Current low) accuracy: 0.85
Combined (2/3 rules) accuracy: 0.88
```

#### 2. `compare_xai_vs_cnn.py`
```python
"""
Compare XAI explanations with CNN predictions.
"""

# Load CNN predictions
cnn_pred = model.predict(X_test)

# Load XAI predictions
xai_reason_codes = generate_reason_codes(X_test)

# Analyze agreement
agreement = (cnn_pred == xai_pred).mean()
print(f"CNN-XAI agreement: {agreement:.3f}")

# Cases where they disagree
disagree_mask = (cnn_pred != xai_pred)
print(f"Disagreement rate: {disagree_mask.mean():.3f}")
```

---

## 📊 Expected Results

### XAI Performance Metrics

| Metric | Target | Expected |
|--------|--------|----------|
| **Rule Accuracy** | >85% | ~88% |
| **Coverage** | >90% | ~95% |
| **CNN-XAI Agreement** | >80% | ~85% |
| **FPGA Overhead** | <500 LUTs | ~300 LUTs |
| **Latency Impact** | <10 cycles | ~5 cycles |

### Example XAI Output Table

| Sample | CNN Output | XAI Reason Code | Explanation | Match? |
|--------|------------|-----------------|-------------|--------|
| 1 | HYPO (0.89) | 101 | Rapid drop + Low current | ✅ Yes |
| 2 | SAFE (0.12) | 000 | No risk factors | ✅ Yes |
| 3 | HYPO (0.78) | 010 | Recent low detected | ✅ Yes |
| 4 | SAFE (0.45) | 001 | Only current low | ⚠️ Partial |
| 5 | HYPO (0.92) | 111 | All three factors | ✅ Yes |

---

## 🎯 Integration with Early Exit

### Combined Architecture

```
Input → CNN → [Early Exit?] → Output
         │
         └─→ XAI → Reason Code
```

### Combined Output

```verilog
output reg         hypo_risk,        // From CNN
output reg [15:0]  probability,      // From CNN
output reg         early_exit_used,  // From Early Exit
output reg [2:0]   reason_code,      // From XAI
output reg [15:0]  slope             // From XAI
```

### Benefits of Combination

| Feature | Benefit |
|---------|---------|
| Early Exit | 43% faster inference |
| XAI | Interpretable predictions |
| **Combined** | **Fast AND explainable** |

---

## 📝 Documentation to Create

### 1. `XAI_IMPLEMENTATION_GUIDE.md`
- Architecture details
- Module specifications
- Integration instructions

### 2. `XAI_RESULTS.md`
- Rule accuracy results
- CNN-XAI comparison
- FPGA utilization impact

### 3. `XAI_CLINICAL_RELEVANCE.md`
- Why these explanations matter
- Comparison with clinical practice
- Doctor feedback (if available)

---

## ⏰ Implementation Timeline

### Day 1: RTL Implementation (4-6 hours)
```
Hour 1-2: Create trend_calculator.v
Hour 2-3: Create min_detector.v
Hour 3-4: Create rate_of_change.v
Hour 4-5: Create reason_encoder.v
Hour 5-6: Integrate into top module
```

### Day 2: Verification & Documentation (3-4 hours)
```
Hour 1: Python rule generation
Hour 2: CNN-XAI comparison
Hour 3: FPGA synthesis (estimate resources)
Hour 4: Documentation
```

**Total Time:** 7-10 hours (1-2 days)

---

## 🏆 How This Helps You Win

### Before XAI:
> "Our model predicts hypoglycemia with 90% accuracy."

### After XAI:
> "Our model predicts hypoglycemia with 90% accuracy AND explains why:
> - 'HYPO RISK: Glucose dropped 15 mg/dL in 5 minutes'
> - 'Patient had recent low of 55 mg/dL'
> - 'Current glucose 70 mg/dL and falling'
> 
> This helps clinicians trust and act on predictions."

**Much more compelling!** 🏆

---

## ✅ XAI Checklist

### RTL Modules
- [ ] `trend_calculator.v`
- [ ] `min_detector.v`
- [ ] `rate_of_change.v`
- [ ] `reason_encoder.v`
- [ ] `xai_output_formatter.v`
- [ ] Modified top module

### Python Scripts
- [ ] `generate_xai_rules.py`
- [ ] `compare_xai_vs_cnn.py`
- [ ] `xai_accuracy_analysis.py`

### Documentation
- [ ] `XAI_IMPLEMENTATION_GUIDE.md`
- [ ] `XAI_RESULTS.md`
- [ ] `XAI_CLINICAL_RELEVANCE.md`

### Verification
- [ ] Python rules accuracy >85%
- [ ] CNN-XAI agreement >80%
- [ ] FPGA synthesis complete
- [ ] Simulation testbench PASS

---

## 🎯 Success Criteria

| Criterion | Target | Status |
|-----------|--------|--------|
| Rule Accuracy | >85% | ⏳ Pending |
| CNN-XAI Agreement | >80% | ⏳ Pending |
| FPGA Overhead | <500 LUTs | ⏳ Pending |
| Implementation Time | <10 hours | ⏳ Pending |
| Documentation | Complete | ⏳ Pending |

---

## 💡 Final Recommendation

**Option 1 (Feature Importance) is PERFECT for your project because:**

1. ✅ **Fits your timeline** - 7-10 hours vs 2-3 days
2. ✅ **Low risk** - Simple arithmetic, easy to debug
3. ✅ **Minimal FPGA impact** - +300 LUTs (still <30% utilization)
4. ✅ **Clinically meaningful** - Doctors understand trends
5. ✅ **Great for presentation** - Clear, visual explanations
6. ✅ **Complements early exit** - Both add value

**You'll have:**
- ✅ Baseline CNN (90.5% F1)
- ✅ Early Exit (92.2% exit rate, 43% faster)
- ✅ XAI (interpretable predictions)

**This is a WINNING combination!** 🏆

---

**Document Status:** ✅ **COMPLETE**  
**Ready to Implement:** YES  
**Recommended Next Step:** Start with `trend_calculator.v`

---

*Document Version: 1.0*  
*Last Updated: March 23, 2026*  
*Recommendation: Option 1 - Feature Importance Analysis*
