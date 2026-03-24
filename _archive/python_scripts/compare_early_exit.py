"""
Compare Baseline vs Early Exit CNN models.

This script:
1. Loads both baseline and early exit models
2. Runs inference on test set
3. Compares accuracy, latency, and early exit rate
4. Generates comparison report
"""

import numpy as np
import tensorflow as tf
from tensorflow import keras
import json
from sklearn.metrics import f1_score, precision_score, recall_score

print("=" * 70)
print("BASELINE vs EARLY EXIT COMPARISON")
print("=" * 70)

# Load test data
print("\nLoading test data...")
X_test = np.load('dataset/X_test.npy')
y_test = np.load('dataset/y_test.npy')
X_test = X_test.reshape(-1, 16, 1) / 400.0

print(f"Test samples: {len(X_test)}")

# Load baseline model
print("\nLoading baseline model...")
baseline_model = keras.models.load_model('models/tiny_cnn_hypo.keras')
print("Baseline model loaded")

# Load early exit model
print("Loading early exit model...")
early_exit_model = keras.models.load_model('models/early_exit_cnn.keras')
print("Early exit model loaded")

# Load early exit metrics
with open('models/early_exit_metrics.json', 'r') as f:
    ee_metrics = json.load(f)

EARLY_EXIT_HIGH = ee_metrics['early_exit_threshold_high']
EARLY_EXIT_LOW = ee_metrics['early_exit_threshold_low']

print(f"\nEarly exit thresholds: >= {EARLY_EXIT_HIGH} or <= {EARLY_EXIT_LOW}")

# Run inference
print("\n" + "=" * 70)
print("RUNNING INFERENCE")
print("=" * 70)

print("\nBaseline model inference...")
baseline_pred = baseline_model.predict(X_test, verbose=0).flatten()
baseline_binary = (baseline_pred >= 0.5).astype(int)

print("Early exit model inference...")
early_pred, main_pred = early_exit_model.predict(X_test, verbose=0)
early_pred = early_pred.flatten()
main_pred = main_pred.flatten()

# Determine early exit samples
would_exit_early = (early_pred >= EARLY_EXIT_HIGH) | (early_pred <= EARLY_EXIT_LOW)
exit_rate = np.sum(would_exit_early) / len(would_exit_early) * 100

# Hybrid prediction (early exit when confident)
hybrid_pred = np.where(would_exit_early, early_pred, main_pred)
hybrid_binary = (hybrid_pred >= 0.5).astype(int)

# Calculate metrics
print("\n" + "=" * 70)
print("COMPARISON RESULTS")
print("=" * 70)

# Baseline metrics
baseline_f1 = f1_score(y_test, baseline_binary)
baseline_precision = precision_score(y_test, baseline_binary)
baseline_recall = recall_score(y_test, baseline_binary)

# Early exit only metrics
early_binary = (early_pred >= 0.5).astype(int)
early_f1 = f1_score(y_test, early_binary)
early_precision = precision_score(y_test, early_binary)
early_recall = recall_score(y_test, early_binary)

# Hybrid metrics
hybrid_f1 = f1_score(y_test, hybrid_binary)
hybrid_precision = precision_score(y_test, hybrid_binary)
hybrid_recall = recall_score(y_test, hybrid_binary)

print(f"\n{'Metric':<20} {'Baseline':<15} {'Early Only':<15} {'Hybrid':<15}")
print("-" * 65)
print(f"{'F1 Score':<20} {baseline_f1:<15.4f} {early_f1:<15.4f} {hybrid_f1:<15.4f}")
print(f"{'Precision':<20} {baseline_precision:<15.4f} {early_precision:<15.4f} {hybrid_precision:<15.4f}")
print(f"{'Recall':<20} {baseline_recall:<15.4f} {early_recall:<15.4f} {hybrid_recall:<15.4f}")
print(f"{'Early Exit Rate':<20} {'N/A':<15} {'N/A':<15} {exit_rate:.1f}%")

# Latency comparison (in clock cycles)
BASELINE_LATENCY = 281  # cycles (from original design)
EARLY_EXIT_LATENCY = 150  # cycles (approx, after Dense1)
FULL_LATENCY = 281  # cycles (with Dense2)

# Average latency for hybrid
avg_latency = (exit_rate/100) * EARLY_EXIT_LATENCY + (1 - exit_rate/100) * FULL_LATENCY
latency_reduction = (BASELINE_LATENCY - avg_latency) / BASELINE_LATENCY * 100

print("\n" + "=" * 70)
print("LATENCY COMPARISON")
print("=" * 70)
print(f"\nBaseline latency: {BASELINE_LATENCY} cycles")
print(f"Early exit latency: {EARLY_EXIT_LATENCY} cycles")
print(f"Full model latency: {FULL_LATENCY} cycles")
print(f"\nAverage hybrid latency: {avg_latency:.1f} cycles")
print(f"Latency reduction: {latency_reduction:.1f}%")

# Power estimation (rough)
print("\n" + "=" * 70)
print("POWER ESTIMATION")
print("=" * 70)
print(f"\nBaseline power: 100% (reference)")
print(f"Early exit power: ~{50 + (100-50)*(exit_rate/100):.1f}% (estimated)")
print(f"Power reduction: ~{100 - (50 + (100-50)*(exit_rate/100)):.1f}% (estimated)")

# Save comparison results
comparison_results = {
    'baseline': {
        'f1': float(baseline_f1),
        'precision': float(baseline_precision),
        'recall': float(baseline_recall),
        'latency_cycles': BASELINE_LATENCY
    },
    'early_exit_only': {
        'f1': float(early_f1),
        'precision': float(early_precision),
        'recall': float(early_recall),
        'latency_cycles': EARLY_EXIT_LATENCY
    },
    'hybrid': {
        'f1': float(hybrid_f1),
        'precision': float(hybrid_precision),
        'recall': float(hybrid_recall),
        'early_exit_rate': float(exit_rate),
        'avg_latency_cycles': float(avg_latency),
        'latency_reduction': float(latency_reduction)
    }
}

with open('models/baseline_vs_early_exit_comparison.json', 'w') as f:
    json.dump(comparison_results, f, indent=2)

print("\n" + "=" * 70)
print("COMPARISON COMPLETE")
print("=" * 70)

print(f"\nResults saved to: models/baseline_vs_early_exit_comparison.json")

# Verdict
print("\n" + "=" * 70)
print("VERDICT")
print("=" * 70)

f1_diff = abs(hybrid_f1 - baseline_f1)

if f1_diff < 0.01:
    print(f"\n✅ EXCELLENT: Early exit achieves similar accuracy (F1 diff: {f1_diff:.4f})")
    print(f"   with {exit_rate:.1f}% early exit rate and {latency_reduction:.1f}% latency reduction!")
elif f1_diff < 0.02:
    print(f"\n✅ GOOD: Small accuracy drop (F1 diff: {f1_diff:.4f})")
    print(f"   with {exit_rate:.1f}% early exit rate and {latency_reduction:.1f}% latency reduction")
else:
    print(f"\n⚠️ WARNING: Notable accuracy drop (F1 diff: {f1_diff:.4f})")
    print(f"   Consider adjusting early exit thresholds")

print("\n" + "=" * 70)
