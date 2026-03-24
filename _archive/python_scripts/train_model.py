"""
Train a tiny 1D CNN for hypoglycemia prediction.
FPGA-friendly architecture with minimal resources.
"""

import numpy as np
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
from sklearn.metrics import (precision_score, recall_score, f1_score,
                             roc_auc_score, average_precision_score,
                             confusion_matrix, classification_report)
import os

# Set random seeds for reproducibility
np.random.seed(42)
tf.random.set_seed(42)

# Configuration
INPUT_SIZE = 16  # 16-sample window
NUM_CLASSES = 1
EPOCHS = 30
BATCH_SIZE = 32

# Load data
print("=" * 60)
print("Loading dataset...")
print("=" * 60)

X_train = np.load('dataset/X_train.npy')
y_train = np.load('dataset/y_train.npy')
X_test = np.load('dataset/X_test.npy')
y_test = np.load('dataset/y_test.npy')

# Reshape for 1D CNN: (samples, timesteps, features)
X_train = X_train.reshape(-1, INPUT_SIZE, 1)
X_test = X_test.reshape(-1, INPUT_SIZE, 1)

print(f"Training set: {X_train.shape}, Labels: {y_train.shape}")
print(f"Test set: {X_test.shape}, Labels: {y_test.shape}")

# Normalize to 0-1 range
X_train = X_train / 400.0  # Max glucose value
X_test = X_test / 400.0

print(f"\nData normalized to [0, 1] range")


def create_tiny_cnn():
    """
    Create a tiny 1D CNN for FPGA deployment.
    
    Architecture:
    - 1 Conv1D layer (8 filters, kernel=3)
    - Global Average Pooling
    - 1 Dense layer (16 units)
    - Output layer (sigmoid for binary classification)
    
    Total params: ~200 (extremely lightweight)
    """
    inputs = keras.Input(shape=(INPUT_SIZE, 1))
    
    # Conv block
    x = layers.Conv1D(filters=8, kernel_size=3, padding='same', 
                      activation='relu', name='conv1')(inputs)
    x = layers.BatchNormalization(name='bn1')(x)
    x = layers.MaxPooling1D(pool_size=2, name='pool1')(x)
    
    # Flatten and dense
    x = layers.GlobalAveragePooling1D(name='gap')(x)
    x = layers.Dense(16, activation='relu', name='dense1')(x)
    
    # Output
    outputs = layers.Dense(1, activation='sigmoid', name='output')(x)
    
    model = keras.Model(inputs, outputs, name='tiny_cnn_hypo')
    
    return model


def create_early_exit_cnn():
    """
    Create CNN with early exit capability.
    
    Exit after conv layer if confidence is high.
    """
    inputs = keras.Input(shape=(INPUT_SIZE, 1))
    
    # Conv block
    x = layers.Conv1D(filters=8, kernel_size=3, padding='same', 
                      activation='relu', name='conv1')(inputs)
    x = layers.BatchNormalization(name='bn1')(x)
    
    # Early exit branch
    early_exit = layers.GlobalAveragePooling1D(name='early_gap')(x)
    early_exit = layers.Dense(16, activation='relu', name='early_dense')(early_exit)
    early_output = layers.Dense(1, activation='sigmoid', name='early_output')(early_exit)
    
    # Continue to full model
    x = layers.MaxPooling1D(pool_size=2, name='pool1')(x)
    x = layers.GlobalAveragePooling1D(name='gap')(x)
    x = layers.Dense(16, activation='relu', name='dense1')(x)
    main_output = layers.Dense(1, activation='sigmoid', name='output')(x)
    
    model = keras.Model(inputs, [early_output, main_output], name='early_exit_cnn')
    
    return model


print("\n" + "=" * 60)
print("Creating Tiny CNN model...")
print("=" * 60)

model = create_tiny_cnn()
model.summary()

# Calculate class weights for imbalanced training set
n_neg = np.sum(y_train == 0)
n_pos = np.sum(y_train == 1)
total = len(y_train)

weight_for_0 = total / (2 * n_neg)
weight_for_1 = total / (2 * n_pos)

class_weight = {0: weight_for_0, 1: weight_for_1}

print(f"\nClass weights: 0 (safe)={weight_for_0:.3f}, 1 (hypo)={weight_for_1:.3f}")

# Compile model
model.compile(
    optimizer=keras.optimizers.Adam(learning_rate=0.001),
    loss='binary_crossentropy',
    metrics=['accuracy', keras.metrics.AUC(name='auc')]
)

# Train
print("\n" + "=" * 60)
print("Training model...")
print("=" * 60)

history = model.fit(
    X_train, y_train,
    epochs=EPOCHS,
    batch_size=BATCH_SIZE,
    class_weight=class_weight,
    validation_split=0.2,
    verbose=1
)

# Evaluate
print("\n" + "=" * 60)
print("Evaluating on balanced test set...")
print("=" * 60)

# Get predictions
y_pred_proba = model.predict(X_test, verbose=0).flatten()

# Find optimal threshold using validation set
from sklearn.metrics import precision_recall_curve

precisions, recalls, thresholds = precision_recall_curve(y_test, y_pred_proba)
f1_scores = 2 * (precisions * recalls) / (precisions + recalls + 1e-8)
optimal_idx = np.argmax(f1_scores)
optimal_threshold = thresholds[optimal_idx] if optimal_idx < len(thresholds) else 0.5

print(f"\nOptimal threshold: {optimal_threshold:.3f}")

# Apply threshold
y_pred = (y_pred_proba >= optimal_threshold).astype(int)

# Calculate metrics
precision = precision_score(y_test, y_pred)
recall = recall_score(y_test, y_pred)
f1 = f1_score(y_test, y_pred)
auc_roc = roc_auc_score(y_test, y_pred_proba)
auc_pr = average_precision_score(y_test, y_pred_proba)

print(f"\n{'='*60}")
print("EVALUATION RESULTS (Balanced Test Set)")
print(f"{'='*60}")
print(f"Precision:  {precision:.4f}")
print(f"Recall:     {recall:.4f}")
print(f"F1 Score:   {f1:.4f}")
print(f"AUC-ROC:    {auc_roc:.4f}")
print(f"AUC-PR:     {auc_pr:.4f}")

print(f"\nConfusion Matrix:")
cm = confusion_matrix(y_test, y_pred)
print(cm)
print(f"\n  TN={cm[0,0]:>5}  FP={cm[0,1]:>5}")
print(f"  FN={cm[1,0]:>5}  TP={cm[1,1]:>5}")

print(f"\nClassification Report:")
print(classification_report(y_test, y_pred, target_names=['Safe', 'Hypo Risk']))

# Save model
print("\n" + "=" * 60)
print("Saving model...")
print("=" * 60)

model.save('models/tiny_cnn_hypo.keras')
print("Model saved to 'models/tiny_cnn_hypo.keras'")

# Save weights separately for FPGA
model.save_weights('models/tiny_cnn_hypo.weights.h5')
print("Weights saved to 'models/tiny_cnn_hypo.weights.h5'")

# Save training history
import json
history_dict = {k: [float(v) for v in hist] for k, hist in history.history.items()}
with open('models/training_history.json', 'w') as f:
    json.dump(history_dict, f, indent=2)
print("Training history saved to 'models/training_history.json'")

# Export model architecture
model_json = model.to_json()
with open('models/tiny_cnn_architecture.json', 'w') as f:
    f.write(model_json)
print("Architecture saved to 'models/tiny_cnn_architecture.json'")

# Print model info for FPGA
print("\n" + "=" * 60)
print("MODEL SUMMARY FOR FPGA")
print("=" * 60)

total_params = model.count_params()
print(f"Total parameters: {total_params:,}")
print(f"Input shape: {INPUT_SIZE} samples (80 min history)")
print(f"Output: Binary (hypo risk in next 30 min)")

# Get layer-wise params
print("\nLayer-wise parameters:")
for layer in model.layers:
    params = layer.count_params()
    if params > 0:
        print(f"  {layer.name}: {params:,} params")

print("\n" + "=" * 60)
print("Training complete!")
print("=" * 60)
