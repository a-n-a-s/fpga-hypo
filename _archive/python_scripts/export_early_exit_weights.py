"""
Export Early Exit CNN weights to .mem files for FPGA.

Creates memory initialization files for:
- Early exit dense layer (16→1)
- Early exit bias (1)
"""

import numpy as np
import tensorflow as tf
from tensorflow import keras
import os

print("=" * 70)
print("EARLY EXIT WEIGHT EXPORT")
print("=" * 70)

# Load trained early exit model
print("\nLoading early exit model...")
model = keras.models.load_model('models/early_exit_cnn.keras')
print("Model loaded successfully")

# Create mem_files directory
os.makedirs('mem_files', exist_ok=True)


def float_to_fixed(value, integer_bits=8, fractional_bits=8):
    """Convert float to Q8.8 fixed-point."""
    scale = 2 ** fractional_bits
    max_val = (2 ** (integer_bits + fractional_bits - 1)) - 1
    min_val = -(2 ** (integer_bits + fractional_bits - 1))
    
    fixed_val = int(round(value * scale))
    fixed_val = max(min_val, min(max_val, fixed_val))
    
    if fixed_val < 0:
        fixed_val = (1 << (integer_bits + fractional_bits)) + fixed_val
    
    return fixed_val & 0xFFFF


def write_mem_file(values, filename):
    """Write values to .mem file in hex format."""
    with open(filename, 'w') as f:
        f.write("// Memory initialization file\n")
        f.write(f"// Format: hex (Q8.8 fixed-point)\n")
        f.write(f"// Total values: {len(values)}\n\n")
        for val in values:
            f.write(f"{val:04X}\n")
    print(f"Saved: {filename} ({len(values)} values)")


# Extract early exit dense layer weights
print("\n" + "=" * 70)
print("EXTRACTING EARLY EXIT WEIGHTS")
print("=" * 70)

early_exit_layer = model.get_layer('early_output')
ee_weights, ee_bias = early_exit_layer.get_weights()

print(f"\nEarly exit dense layer:")
print(f"  Weights shape: {ee_weights.shape}")  # (16, 1)
print(f"  Bias shape: {ee_bias.shape}")        # (1,)

# Flatten weights (16×1 → 16)
ee_w_flat = ee_weights.flatten()

# Convert to Q8.8
ee_w_fixed = [float_to_fixed(w) for w in ee_w_flat]
ee_b_fixed = [float_to_fixed(b) for b in ee_bias]

# Save to .mem files
print("\n" + "=" * 70)
print("SAVING EARLY EXIT .MEM FILES")
print("=" * 70)

write_mem_file(ee_w_fixed, 'mem_files/early_exit_weights.mem')
write_mem_file(ee_b_fixed, 'mem_files/early_exit_bias.mem')

# Also save full model weights for reference
print("\n" + "=" * 70)
print("SAVING ALL MODEL WEIGHTS")
print("=" * 70)

for layer in model.layers:
    if hasattr(layer, 'get_weights'):
        weights = layer.get_weights()
        if len(weights) > 0:
            layer_name = layer.name
            print(f"\n{layer_name}:")
            
            if len(weights) == 2:
                w, b = weights
                print(f"  Weights shape: {w.shape}")
                print(f"  Bias shape: {b.shape}")
                
                w_fixed = [float_to_fixed(x) for x in w.flatten()]
                b_fixed = [float_to_fixed(x) for x in b.flatten()]
                
                write_mem_file(w_fixed, f'mem_files/ee_{layer_name}_weights.mem')
                write_mem_file(b_fixed, f'mem_files/ee_{layer_name}_bias.mem')
            
            elif len(weights) == 4:
                # BatchNorm
                gamma, beta, mean, var = weights
                print(f"  Gamma/Beta/Mean/Var shape: {gamma.shape}")
                
                gamma_fixed = [float_to_fixed(g) for g in gamma]
                beta_fixed = [float_to_fixed(b) for b in beta]
                mean_fixed = [float_to_fixed(m) for m in mean]
                var_fixed = [float_to_fixed(v) for v in var]
                
                write_mem_file(gamma_fixed, f'mem_files/ee_{layer_name}_gamma.mem')
                write_mem_file(beta_fixed, f'mem_files/ee_{layer_name}_beta.mem')
                write_mem_file(mean_fixed, f'mem_files/ee_{layer_name}_mean.mem')
                write_mem_file(var_fixed, f'mem_files/ee_{layer_name}_variance.mem')

print("\n" + "=" * 70)
print("EXPORT COMPLETE!")
print("=" * 70)
print("\nCreated .mem files:")
print("  - early_exit_weights.mem (16 values)")
print("  - early_exit_bias.mem (1 value)")
print("  - ee_* files for all layers")
