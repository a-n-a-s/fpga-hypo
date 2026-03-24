"""
Train Early Exit CNN for Hypoglycemia Prediction.

This model has TWO outputs:
1. Early exit output (after Dense1) - for confident predictions
2. Full model output - for uncertain predictions

Architecture:
Input → Conv1D → BatchNorm → MaxPool → GAP → Dense1 → [Early Exit] → Dense2 → Output
                                                      ↓
                                              Exit if confident
"""

import numpy as np
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
from sklearn.metrics import precision_score, recall_score, f1_score, confusion_matrix
import os
import json

# Set random seeds
np.random.seed(42)
tf.random.set_seed(42)

# Configuration
INPUT_SIZE = 16
EPOCHS = 10  # Reduced for faster training
BATCH_SIZE = 64  # Larger batch for speed

print("=" * 70)
print("EARLY EXIT CNN TRAINING")
print("=" * 70)

# Load data
print("\nLoading dataset...")
X_train = np.load('dataset/X_train.npy')
y_train = np.load('dataset/y_train.npy')
X_test = np.load('dataset/X_test.npy')
y_test = np.load('dataset/y_test.npy')

# Reshape for 1D CNN
X_train = X_train.reshape(-1, INPUT_SIZE, 1)
X_test = X_test.reshape(-1, INPUT_SIZE, 1)

# Normalize
X_train = X_train / 400.0
X_test = X_test / 400.0

print(f"Training set: {X_train.shape}, Labels: {y_train.shape}")
print(f"Test set: {X_test.shape}, Labels: {y_test.shape}")


def create_early_exit_cnn():
    """
    Create CNN with early exit capability.
    
    Returns two outputs:
    - early_output: Prediction after Dense1 (for confident samples)
    - main_output: Prediction after Dense2 (for uncertain samples)
    """
    inputs = keras.Input(shape=(INPUT_SIZE, 1))

    # Conv block
    x = layers.Conv1D(filters=8, kernel_size=3, padding='same',
                      activation='relu', name='conv1')(inputs)
    x = layers.BatchNormalization(name='bn1')(x)
    x = layers.MaxPooling1D(pool_size=2, name='pool1')(x)
    x = layers.GlobalAveragePooling1D(name='gap')(x)
    
    # Dense1
    x = layers.Dense(16, activation='relu', name='dense1')(x)
    
    # EARLY EXIT BRANCH (after Dense1)
    early_output = layers.Dense(1, activation='sigmoid', 
                                 name='early_output')(x)
    
    # Continue to full model (Dense2)
    main_output = layers.Dense(1, activation='sigmoid', 
                                name='output')(x)

    # Model with TWO outputs
    model = keras.Model(inputs, [early_output, main_output], 
                        name='early_exit_cnn')

    return model


print("\n" + "=" * 70)
print("Creating Early Exit CNN model...")
print("=" * 70)

model = create_early_exit_cnn()
model.summary()

# Calculate class weights
n_neg = np.sum(y_train == 0)
n_pos = np.sum(y_train == 1)
total = len(y_train)

weight_for_0 = total / (2 * n_neg)
weight_for_1 = total / (2 * n_pos)

class_weight = {0: weight_for_0, 1: weight_for_1}

print(f"\nClass weights: 0 (safe)={weight_for_0:.3f}, 1 (hypo)={weight_for_1:.3f}")

# Compile with multi-output loss (no class weights - model is robust enough)
model.compile(
    optimizer=keras.optimizers.Adam(learning_rate=0.001),
    loss={
        'early_output': 'binary_crossentropy',
        'output': 'binary_crossentropy'
    },
    loss_weights={
        'early_output': 0.3,  # Lower weight for early exit
        'output': 0.7         # Higher weight for main output
    },
    metrics={
        'early_output': 'accuracy',
        'output': 'accuracy'
    }
)

# Train
print("\n" + "=" * 70)
print("Training Early Exit CNN...")
print("=" * 70)

history = model.fit(
    X_train, 
    {'early_output': y_train, 'output': y_train},
    epochs=EPOCHS,
    batch_size=BATCH_SIZE,
    validation_split=0.2,
    verbose=1
)

# Evaluate
print("\n" + "=" * 70)
print("Evaluating Early Exit CNN...")
print("=" * 70)

# Get predictions from both outputs
early_pred, main_pred = model.predict(X_test, verbose=0)
early_pred = early_pred.flatten()
main_pred = main_pred.flatten()

# Find optimal threshold for early exit
# Exit if early_pred >= 0.8 (confident HYPO) or <= 0.2 (confident SAFE)
EARLY_EXIT_HIGH = 0.8
EARLY_EXIT_LOW = 0.2

# Determine which samples would exit early
would_exit_early = (early_pred >= EARLY_EXIT_HIGH) | (early_pred <= EARLY_EXIT_LOW)
exit_rate = np.sum(would_exit_early) / len(would_exit_early) * 100

print(f"\nEarly Exit Threshold: >= {EARLY_EXIT_HIGH} or <= {EARLY_EXIT_LOW}")
print(f"Early Exit Rate: {exit_rate:.1f}% ({np.sum(would_exit_early)}/{len(would_exit_early)} samples)")

# Calculate metrics for different strategies

# Strategy 1: Early Exit (use early_pred for confident, main_pred for uncertain)
final_pred = np.where(would_exit_early, early_pred, main_pred)
final_pred_binary = (final_pred >= 0.5).astype(int)

# Strategy 2: Full Model Only (always use main_pred)
main_pred_binary = (main_pred >= 0.5).astype(int)

# Strategy 3: Early Exit Only (always use early_pred)
early_pred_binary = (early_pred >= 0.5).astype(int)

print("\n" + "=" * 70)
print("COMPARISON: Early Exit vs Full Model")
print("=" * 70)

# Full Model metrics
main_f1 = f1_score(y_test, main_pred_binary)
main_precision = precision_score(y_test, main_pred_binary)
main_recall = recall_score(y_test, main_pred_binary)

# Early Exit Only metrics
early_f1 = f1_score(y_test, early_pred_binary)
early_precision = precision_score(y_test, early_pred_binary)
early_recall = recall_score(y_test, early_pred_binary)

# Hybrid (Early Exit when confident) metrics
hybrid_f1 = f1_score(y_test, final_pred_binary)
hybrid_precision = precision_score(y_test, final_pred_binary)
hybrid_recall = recall_score(y_test, final_pred_binary)

print(f"\n{'Metric':<15} {'Full Model':<15} {'Early Only':<15} {'Hybrid':<15}")
print("-" * 60)
print(f"{'F1 Score':<15} {main_f1:<15.4f} {early_f1:<15.4f} {hybrid_f1:<15.4f}")
print(f"{'Precision':<15} {main_precision:<15.4f} {early_precision:<15.4f} {hybrid_precision:<15.4f}")
print(f"{'Recall':<15} {main_recall:<15.4f} {early_recall:<15.4f} {hybrid_recall:<15.4f}")
print(f"{'Early Exit %':<15} {'0%':<15} {'100%':<15} {exit_rate:.1f}%")

# Confusion matrices
print("\n" + "=" * 70)
print("CONFUSION MATRICES")
print("=" * 70)

print("\nFull Model:")
cm_main = confusion_matrix(y_test, main_pred_binary)
print(cm_main)
print(f"  TN={cm_main[0,0]:>5}  FP={cm_main[0,1]:>5}")
print(f"  FN={cm_main[1,0]:>5}  TP={cm_main[1,1]:>5}")

print("\nHybrid (Early Exit when confident):")
cm_hybrid = confusion_matrix(y_test, final_pred_binary)
print(cm_hybrid)
print(f"  TN={cm_hybrid[0,0]:>5}  FP={cm_hybrid[0,1]:>5}")
print(f"  FN={cm_hybrid[1,0]:>5}  TP={cm_hybrid[1,1]:>5}")

# Save model
print("\n" + "=" * 70)
print("Saving model...")
print("=" * 70)

model.save('models/early_exit_cnn.keras')
print("Model saved to 'models/early_exit_cnn.keras'")

# Save weights separately
model.save_weights('models/early_exit_cnn.weights.h5')
print("Weights saved to 'models/early_exit_cnn.weights.h5'")

# Save training history
history_dict = {k: [float(v) for v in hist] for k, hist in history.history.items()}
with open('models/early_exit_history.json', 'w') as f:
    json.dump(history_dict, f, indent=2)
print("Training history saved to 'models/early_exit_history.json'")

# Save comparison metrics
metrics = {
    'early_exit_threshold_high': EARLY_EXIT_HIGH,
    'early_exit_threshold_low': EARLY_EXIT_LOW,
    'early_exit_rate': float(exit_rate),
    'full_model': {
        'f1': float(main_f1),
        'precision': float(main_precision),
        'recall': float(main_recall)
    },
    'early_only': {
        'f1': float(early_f1),
        'precision': float(early_precision),
        'recall': float(early_recall)
    },
    'hybrid': {
        'f1': float(hybrid_f1),
        'precision': float(hybrid_precision),
        'recall': float(hybrid_recall)
    }
}

with open('models/early_exit_metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
print("Metrics saved to 'models/early_exit_metrics.json'")

# Print layer weights for FPGA export
print("\n" + "=" * 70)
print("MODEL SUMMARY FOR FPGA")
print("=" * 70)

total_params = model.count_params()
print(f"Total parameters: {total_params:,}")

print("\nLayer-wise parameters:")
for layer in model.layers:
    params = layer.count_params()
    if params > 0:
        print(f"  {layer.name}: {params:,} params")

# Extract early exit dense layer weights
print("\n" + "=" * 70)
print("EARLY EXIT DENSE LAYER WEIGHTS")
print("=" * 70)

early_exit_layer = model.get_layer('early_output')
ee_weights = early_exit_layer.get_weights()
print(f"Early exit weights shape: {ee_weights[0].shape}")
print(f"Early exit bias shape: {ee_weights[1].shape}")

print("\n" + "=" * 70)
print("TRAINING COMPLETE!")
print("=" * 70)
print(f"\nEarly Exit Rate: {exit_rate:.1f}%")
print(f"Hybrid F1 Score: {hybrid_f1:.4f}")
print(f"Full Model F1 Score: {main_f1:.4f}")
print(f"F1 Difference: {abs(hybrid_f1 - main_f1):.4f}")

if abs(hybrid_f1 - main_f1) < 0.01:
    print("\n✅ SUCCESS: Early exit achieves similar accuracy with {exit_rate:.1f}% faster inference!")
else:
    print(f"\n⚠️ WARNING: Early exit has {abs(hybrid_f1 - main_f1):.4f} F1 drop")
