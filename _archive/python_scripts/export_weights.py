"""
Export model weights to .mem files for FPGA initialization.
Creates memory initialization files in hex format.
"""

import numpy as np
import tensorflow as tf
from tensorflow import keras
import json

# Load trained model
print("Loading trained model...")
model = keras.models.load_model('models/tiny_cnn_hypo.keras')

# Create mem_files directory
import os
os.makedirs('mem_files', exist_ok=True)

print("\n" + "=" * 60)
print("EXTRACTING WEIGHTS AND BIASES")
print("=" * 60)

# Extract weights layer by layer
layer_weights = {}

for layer in model.layers:
    if hasattr(layer, 'get_weights'):
        weights = layer.get_weights()
        if len(weights) > 0:
            layer_name = layer.name
            layer_weights[layer_name] = {}
            
            if len(weights) == 2:
                # Dense or Conv layer: weights + bias
                w, b = weights
                layer_weights[layer_name]['weights'] = w
                layer_weights[layer_name]['biases'] = b
                print(f"\n{layer_name}:")
                print(f"  Weights shape: {w.shape}")
                print(f"  Biases shape: {b.shape}")
            elif len(weights) == 4:
                # BatchNorm: gamma, beta, mean, variance
                gamma, beta, mean, var = weights
                layer_weights[layer_name]['gamma'] = gamma
                layer_weights[layer_name]['beta'] = beta
                layer_weights[layer_name]['mean'] = mean
                layer_weights[layer_name]['variance'] = var
                print(f"\n{layer_name} (BatchNorm):")
                print(f"  Gamma shape: {gamma.shape}")
                print(f"  Beta shape: {beta.shape}")
                print(f"  Mean shape: {mean.shape}")
                print(f"  Variance shape: {var.shape}")

# Save weights as JSON (for reference)
print("\n" + "=" * 60)
print("SAVING WEIGHTS AS JSON (Reference)")
print("=" * 60)

weights_json = {}
for layer_name, weights in layer_weights.items():
    weights_json[layer_name] = {}
    for key, value in weights.items():
        weights_json[layer_name][key] = value.tolist()

with open('mem_files/weights.json', 'w') as f:
    json.dump(weights_json, f, indent=2)

print("Saved: mem_files/weights.json")


def float_to_fixed(value, integer_bits=8, fractional_bits=8):
    """
    Convert float to fixed-point (Q format).
    Q8.8 format: 8 integer bits + 8 fractional bits
    """
    scale = 2 ** fractional_bits
    max_val = (2 ** (integer_bits + fractional_bits - 1)) - 1
    min_val = -(2 ** (integer_bits + fractional_bits - 1))
    
    # Scale and round
    fixed_val = int(round(value * scale))
    
    # Clip to range
    fixed_val = max(min_val, min(max_val, fixed_val))
    
    # Convert to unsigned for memory file
    if fixed_val < 0:
        fixed_val = (1 << (integer_bits + fractional_bits)) + fixed_val
    
    return fixed_val & 0xFFFF


def write_mem_file(values, filename, format='hex'):
    """
    Write values to .mem file in hex format.
    Each line contains one value in hex.
    """
    with open(filename, 'w') as f:
        f.write("// Memory initialization file\n")
        f.write(f"// Format: {format}\n")
        f.write(f"// Total values: {len(values)}\n\n")
        
        for i, val in enumerate(values):
            if format == 'hex':
                f.write(f"{val:04X}\n")
            elif format == 'bin':
                f.write(f"{val:016b}\n")
            elif format == 'dec':
                f.write(f"{val}\n")
    
    print(f"Saved: {filename} ({len(values)} values)")


# =============================================================================
# Create .mem files for each layer
# =============================================================================

print("\n" + "=" * 60)
print("CREATING .MEM FILES (Q8.8 Fixed-Point)")
print("=" * 60)

# 1. Conv1D Layer (conv1)
print("\n--- Conv1D Layer (conv1) ---")
conv_weights = layer_weights['conv1']['weights']  # Shape: (3, 1, 8)
conv_bias = layer_weights['conv1']['biases']      # Shape: (8,)

# Flatten and convert to fixed-point
conv_w_flat = conv_weights.flatten()
conv_w_fixed = [float_to_fixed(w) for w in conv_w_flat]
conv_b_fixed = [float_to_fixed(b) for b in conv_bias]

write_mem_file(conv_w_fixed, 'mem_files/conv1_weights.mem')
write_mem_file(conv_b_fixed, 'mem_files/conv1_bias.mem')

print(f"  Conv1D weights: {conv_weights.shape} → {len(conv_w_fixed)} values")
print(f"  Conv1D bias: {conv_bias.shape} → {len(conv_b_fixed)} values")

# 2. BatchNorm Layer (bn1)
print("\n--- BatchNorm Layer (bn1) ---")
bn_gamma = layer_weights['bn1']['gamma']
bn_beta = layer_weights['bn1']['beta']
bn_mean = layer_weights['bn1']['mean']
bn_var = layer_weights['bn1']['variance']

# Pre-compute scale and shift for FPGA (optimization - removes runtime computation)
# Formula: scale = gamma / sqrt(variance + epsilon)
#          shift = beta - mean * scale
EPSILON = 1e-5
bn_scale = bn_gamma / np.sqrt(bn_var + EPSILON)
bn_shift = bn_beta - bn_mean * bn_scale

# Save pre-computed values (Q8.8 format)
bn_scale_fixed = [float_to_fixed(s) for s in bn_scale]
bn_shift_fixed = [float_to_fixed(s) for s in bn_shift]

write_mem_file(bn_scale_fixed, 'mem_files/bn1_scale.mem')
write_mem_file(bn_shift_fixed, 'mem_files/bn1_shift.mem')

# Also save original values for reference/debugging
bn_gamma_fixed = [float_to_fixed(g) for g in bn_gamma]
bn_beta_fixed = [float_to_fixed(b) for b in bn_beta]
bn_mean_fixed = [float_to_fixed(m) for m in bn_mean]
bn_var_fixed = [float_to_fixed(v) for v in bn_var]

write_mem_file(bn_gamma_fixed, 'mem_files/bn1_gamma.mem')
write_mem_file(bn_beta_fixed, 'mem_files/bn1_beta.mem')
write_mem_file(bn_mean_fixed, 'mem_files/bn1_mean.mem')
write_mem_file(bn_var_fixed, 'mem_files/bn1_variance.mem')

print(f"  Scale (pre-computed): {len(bn_scale_fixed)} values")
print(f"  Shift (pre-computed): {len(bn_shift_fixed)} values")
print(f"  Gamma (reference): {len(bn_gamma_fixed)} values")
print(f"  Beta (reference): {len(bn_beta_fixed)} values")
print(f"  Mean (reference): {len(bn_mean_fixed)} values")
print(f"  Variance (reference): {len(bn_var_fixed)} values")

# 3. Dense Layer (dense1)
print("\n--- Dense Layer (dense1) ---")
dense_weights = layer_weights['dense1']['weights']  # Shape: (8, 16)
dense_bias = layer_weights['dense1']['biases']      # Shape: (16,)

dense_w_flat = dense_weights.flatten()
dense_w_fixed = [float_to_fixed(w) for w in dense_w_flat]
dense_b_fixed = [float_to_fixed(b) for b in dense_bias]

write_mem_file(dense_w_fixed, 'mem_files/dense1_weights.mem')
write_mem_file(dense_b_fixed, 'mem_files/dense1_bias.mem')

print(f"  Dense weights: {dense_weights.shape} → {len(dense_w_fixed)} values")
print(f"  Dense bias: {dense_bias.shape} → {len(dense_b_fixed)} values")

# 4. Output Layer (output)
print("\n--- Output Layer (output) ---")
output_weights = layer_weights['output']['weights']  # Shape: (16, 1)
output_bias = layer_weights['output']['biases']      # Shape: (1,)

output_w_flat = output_weights.flatten()
output_w_fixed = [float_to_fixed(w) for w in output_w_flat]
output_b_fixed = [float_to_fixed(b) for b in output_bias]

write_mem_file(output_w_fixed, 'mem_files/output_weights.mem')
write_mem_file(output_b_fixed, 'mem_files/output_bias.mem')

print(f"  Output weights: {output_weights.shape} → {len(output_w_fixed)} values")
print(f"  Output bias: {output_bias.shape} → {len(output_b_fixed)} values")


# =============================================================================
# Create combined weights file
# =============================================================================

print("\n" + "=" * 60)
print("CREATING COMBINED WEIGHTS FILE")
print("=" * 60)

all_weights = []
weight_info = []

# Order matters! Must match FPGA loading order
layers_order = [
    ('conv1_weights', conv_w_fixed),
    ('conv1_bias', conv_b_fixed),
    ('bn1_gamma', bn_gamma_fixed),
    ('bn1_beta', bn_beta_fixed),
    ('bn1_mean', bn_mean_fixed),
    ('bn1_variance', bn_var_fixed),
    ('dense1_weights', dense_w_fixed),
    ('dense1_bias', dense_b_fixed),
    ('output_weights', output_w_fixed),
    ('output_bias', output_b_fixed),
]

for name, values in layers_order:
    start_addr = len(all_weights)
    all_weights.extend(values)
    end_addr = len(all_weights) - 1
    weight_info.append({
        'name': name,
        'start_address': start_addr,
        'end_address': end_addr,
        'count': len(values)
    })
    print(f"  {name}: addr {start_addr}-{end_addr} ({len(values)} values)")

write_mem_file(all_weights, 'mem_files/all_weights.mem')

# Save weight map as JSON
weight_map = {
    'format': 'Q8.8 fixed-point',
    'total_weights': len(all_weights),
    'memory_size_bytes': len(all_weights) * 2,  # 2 bytes per 16-bit value
    'layers': weight_info
}

with open('mem_files/weight_map.json', 'w') as f:
    json.dump(weight_map, f, indent=2)

print(f"\nSaved: mem_files/weight_map.json")
print(f"Total weights: {len(all_weights)}")
print(f"Memory size: {len(all_weights) * 2:,} bytes")


# =============================================================================
# Create test input .mem file
# =============================================================================

print("\n" + "=" * 60)
print("CREATING TEST INPUT FILE")
print("=" * 60)

# Load test data
X_test = np.load('dataset/X_test.npy')
X_test_q = np.load('dataset/X_test_quantized.npy')

# Take first sample as test input
test_input = X_test_q[0]  # Already uint8 quantized

# Write as .mem file
with open('mem_files/test_input.mem', 'w') as f:
    f.write("// Test input: 16 glucose samples (uint8)\n")
    f.write(f"// Total values: {len(test_input)}\n\n")
    for val in test_input:
        f.write(f"{int(val):02X}\n")

print(f"Saved: mem_files/test_input.mem")
print(f"Test input shape: {test_input.shape}")
print(f"Sample values: {test_input[:5]}...")

# Also save expected output
model_input = X_test[0:1].reshape(1, 16, 1) / 400.0
expected_output = model.predict(model_input, verbose=0)[0, 0]

with open('mem_files/expected_output.txt', 'w') as f:
    f.write(f"Expected output (float32): {expected_output:.6f}\n")
    f.write(f"Expected classification: {'HYPO RISK' if expected_output >= 0.667 else 'SAFE'}\n")

print(f"Expected output: {expected_output:.6f}")
print(f"Expected classification: {'HYPO RISK' if expected_output >= 0.667 else 'SAFE'}")


# =============================================================================
# Generate Golden Reference Test Vectors for RTL Verification
# =============================================================================

print("\n" + "=" * 60)
print("GENERATING GOLDEN REFERENCE TEST VECTORS")
print("=" * 60)

def generate_test_vectors(model, X_float, X_quantized, num_samples=10):
    """
    Generate test vectors with inputs and expected outputs from Python model.
    This creates golden references for RTL verification.
    
    Note: Model expects normalized input (0-1 range, divided by 400).
    RTL uses quantized input (0-255 range).
    """
    test_vectors = []
    
    for i in range(min(num_samples, len(X_float))):
        # Get raw input (float) - normalize to 0-1 for model
        x_raw = (X_float[i] / 400.0).reshape(1, 16, 1)
        
        # Get model prediction (golden reference)
        pred = model.predict(x_raw, verbose=0)[0, 0]
        pred_fixed = int(round(pred * 255))  # Convert to Q8.8 (0-255)
        classification = 1 if pred >= 0.667 else 0
        
        # Use quantized input for FPGA (uint8 0-255)
        x_quantized = X_quantized[i]
        
        test_vectors.append({
            'index': i,
            'input_float': X_float[i].tolist(),
            'input_q8_8': [int(x) for x in x_quantized],
            'output_float': float(pred),
            'output_q8_8': pred_fixed,
            'classification': classification
        })
        
        print(f"  Sample {i}: output={pred:.6f} ({pred_fixed}/255), class={classification}")
    
    return test_vectors


# Generate test vectors using quantized input for RTL
test_vectors = generate_test_vectors(model, X_test, X_test_q, num_samples=20)

# Save as JSON
import json
with open('mem_files/golden_test_vectors.json', 'w') as f:
    json.dump(test_vectors, f, indent=2)
print(f"\nSaved: mem_files/golden_test_vectors.json")

# Generate individual .mem files for each test case
os.makedirs('mem_files/test_cases', exist_ok=True)

for tv in test_vectors:
    idx = tv['index']
    
    # Input file
    with open(f'mem_files/test_cases/test_{idx:02d}_input.mem', 'w') as f:
        f.write(f"// Test case {idx}: Input (16 uint8 values)\n")
        for val in tv['input_q8_8']:
            f.write(f"{val:02X}\n")
    
    # Expected output file
    with open(f'mem_files/test_cases/test_{idx:02d}_expected.txt', 'w') as f:
        f.write(f"// Test case {idx}: Expected output\n")
        f.write(f"output_float: {tv['output_float']:.6f}\n")
        f.write(f"output_q8_8: {tv['output_q8_8']}\n")
        f.write(f"classification: {tv['classification']}\n")

print(f"Saved: mem_files/test_cases/test_XX_*.mem (individual test cases)")

# Generate a single SystemVerilog-compatible test vector file
with open('mem_files/rtl_golden_vectors.hex', 'w') as f:
    f.write("// Golden reference vectors for RTL testbench\n")
    f.write("// Format: [output_q8_8(8 bits)][classification(1 bit)][input(16 bytes)]\n")
    f.write("// Each line: output_hex input_hex_concatenated\n\n")
    for tv in test_vectors:
        output_hex = f"{tv['output_q8_8']:02X}"
        input_hex = ''.join([f"{v:02X}" for v in tv['input_q8_8']])
        f.write(f"{output_hex} {input_hex}\n")

print(f"Saved: mem_files/rtl_golden_vectors.hex")


# =============================================================================
# Summary
# =============================================================================

print("\n" + "=" * 60)
print("SUMMARY")
print("=" * 60)

print("""
Created .mem files in 'mem_files/' directory:

Weights (Q8.8 fixed-point, 16-bit):
  - conv1_weights.mem    (24 values = 3×1×8)
  - conv1_bias.mem       (8 values)
  - bn1_gamma.mem        (8 values)
  - bn1_beta.mem         (8 values)
  - bn1_mean.mem         (8 values)
  - bn1_variance.mem     (8 values)
  - dense1_weights.mem   (128 values = 8×16)
  - dense1_bias.mem      (16 values)
  - output_weights.mem   (16 values = 16×1)
  - output_bias.mem      (1 value)
  - all_weights.mem      (225 values total)

Test Files:
  - test_input.mem       (16 uint8 values)
  - expected_output.txt  (reference output)

Reference Files:
  - weights.json         (float32 weights for debugging)
  - weight_map.json      (memory map)

Format: Q8.8 Fixed-Point
  - 8 integer bits + 8 fractional bits
  - 16 bits per value (2 bytes)
  - Range: 0 to 255.996
  - Precision: 1/256 ≈ 0.0039

Usage in Verilog:
  $readmemh("mem_files/conv1_weights.mem", conv_weights_mem);
  $readmemh("mem_files/conv1_bias.mem", conv_bias_mem);
  ...
""")

print("=" * 60)
print("Weight export complete!")
print("=" * 60)
