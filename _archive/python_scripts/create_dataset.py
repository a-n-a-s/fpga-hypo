"""
FPGA Hypoglycemia Prediction Dataset Creator
Fixed version with proper time-based splitting and no SMOTE.
"""

import xml.etree.ElementTree as ET
import numpy as np
import pandas as pd
from datetime import datetime
from sklearn.model_selection import train_test_split
import os

# Configuration
DATA_DIR = "DATA MODELS AND WEIGHTS/archive"
PATIENT_IDS = ["559", "563", "570", "575", "588", "591"]

# Sliding window parameters
WINDOW_SIZE = 16  # Past 16 samples (80 minutes)
PREDICTION_HORIZON = 6  # Next 6 samples (30 minutes)
HYPO_THRESHOLD = 70  # mg/dL
SAFE_THRESHOLD = 80  # Must be >= this to make prediction

# Quantization for FPGA (8-bit: 0-255 maps to 0-400 mg/dL)
GLUCOSE_MIN = 0
GLUCOSE_MAX = 400

# Downsampling: target ratio of majority:minority
# Since we have ~99% positive, we need aggressive downsampling
TARGET_RATIO = 2  # 2:1 ratio (hypo:safe) for training


def parse_xml_file(filepath):
    """Parse XML file and extract glucose time series."""
    tree = ET.parse(filepath)
    root = tree.getroot()
    
    events = []
    for event in root.findall(".//event"):
        ts_str = event.get("ts")
        value_str = event.get("value")
        
        if ts_str is None or value_str is None:
            continue
            
        try:
            value = float(value_str)
            ts = datetime.strptime(ts_str, "%d-%m-%Y %H:%M:%S")
            events.append({"timestamp": ts, "glucose": value})
        except (ValueError, TypeError):
            continue
    
    events.sort(key=lambda x: x["timestamp"])
    return events


def create_sliding_windows(glucose_values, timestamps=None):
    """
    Create sliding window samples with proper labeling.
    
    Label strategy:
    - Only create samples when current glucose >= SAFE_THRESHOLD (80)
    - Label 1: will drop below HYPO_THRESHOLD (70) in prediction horizon
    - Label 0: will stay above HYPO_THRESHOLD in prediction horizon
    """
    X = []
    y = []
    sample_info = []  # For debugging
    
    max_start = len(glucose_values) - WINDOW_SIZE - PREDICTION_HORIZON
    
    for i in range(max_start + 1):
        window = glucose_values[i:i + WINDOW_SIZE]
        current_glucose = window[-1]
        
        future = glucose_values[i + WINDOW_SIZE:i + WINDOW_SIZE + PREDICTION_HORIZON]
        min_future = min(future)
        
        # Only predict when currently safe
        if current_glucose >= SAFE_THRESHOLD:
            label = 1 if min_future < HYPO_THRESHOLD else 0
            X.append(window)
            y.append(label)
            
            if timestamps and len(sample_info) < 100:  # Store first 100 for inspection
                sample_info.append({
                    'idx': i,
                    'timestamp': timestamps[i + WINDOW_SIZE - 1],
                    'current': current_glucose,
                    'future_min': min_future,
                    'label': label
                })
    
    return np.array(X), np.array(y), sample_info


def downsample_majority(X, y, target_ratio=2, seed=42):
    """
    Downsample the majority class to achieve a target ratio.
    
    Args:
        X: Features
        y: Labels (1 = hypo risk, 0 = safe)
        target_ratio: Desired ratio of majority:minority (e.g., 2 means 2:1)
        seed: Random seed
    """
    np.random.seed(seed)
    
    class_0_idx = np.where(y == 0)[0]  # Safe (minority)
    class_1_idx = np.where(y == 1)[0]  # Hypo risk (majority)
    
    n_minority = len(class_0_idx)
    n_majority = len(class_1_idx)
    
    # Keep all minority samples
    keep_idx = list(class_0_idx)
    
    # Sample majority class to achieve target ratio
    n_majority_to_keep = min(n_majority, int(n_minority * target_ratio))
    sampled_majority = np.random.choice(class_1_idx, size=n_majority_to_keep, replace=False)
    keep_idx.extend(sampled_majority)
    
    # Shuffle
    np.random.shuffle(keep_idx)
    
    return X[keep_idx], y[keep_idx]


def quantize_glucose(values):
    """Quantize glucose values to 8-bit for FPGA."""
    clipped = np.clip(values, GLUCOSE_MIN, GLUCOSE_MAX)
    quantized = ((clipped - GLUCOSE_MIN) / (GLUCOSE_MAX - GLUCOSE_MIN) * 255).astype(np.uint8)
    return quantized


def load_patient_data(patient_id):
    """Load data for a single patient (training + testing)."""
    train_file = os.path.join(DATA_DIR, f"{patient_id}-ws-training.xml")
    test_file = os.path.join(DATA_DIR, f"{patient_id}-ws-testing.xml")
    
    all_events = []
    for filepath in [train_file, test_file]:
        if os.path.exists(filepath):
            events = parse_xml_file(filepath)
            all_events.extend(events)
    
    # Sort by timestamp (important for time-based split)
    all_events.sort(key=lambda x: x["timestamp"])
    
    glucose_values = [e["glucose"] for e in all_events]
    timestamps = [e["timestamp"] for e in all_events]
    
    return glucose_values, timestamps


def main():
    print("=" * 60)
    print("FPGA Hypoglycemia Prediction Dataset Creator (FIXED)")
    print("=" * 60)
    print(f"\nConfiguration:")
    print(f"  Window size: {WINDOW_SIZE} samples ({WINDOW_SIZE * 5} min)")
    print(f"  Prediction horizon: {PREDICTION_HORIZON} samples ({PREDICTION_HORIZON * 5} min)")
    print(f"  Hypo threshold: {HYPO_THRESHOLD} mg/dL")
    print(f"  Safe threshold: {SAFE_THRESHOLD} mg/dL")
    print(f"  Downsampling: {TARGET_RATIO}:1 ratio (hypo:safe)")
    print()
    
    # Process each patient separately
    all_patient_data = {}
    
    print("Processing patients individually...")
    for patient_id in PATIENT_IDS:
        glucose_values, timestamps = load_patient_data(patient_id)
        X, y, sample_info = create_sliding_windows(glucose_values, timestamps)
        
        all_patient_data[patient_id] = {
            'X': X,
            'y': y,
            'n_samples': len(y),
            'n_hypo': sum(y),
            'sample_info': sample_info[:10]  # Keep first 10 for inspection
        }
        
        print(f"  Patient {patient_id}: {len(y)} samples, "
              f"{sum(y)} hypo-risk ({100*sum(y)/len(y):.1f}%)")
    
    # Show sample inspection for first patient
    print("\n" + "=" * 60)
    print("Sample Window Inspection (Patient 559, first 10):")
    print("=" * 60)
    for info in all_patient_data["559"]['sample_info']:
        status = "HYPO RISK" if info['label'] == 1 else "SAFE"
        print(f"  {info['timestamp']}: current={info['current']:.1f}, "
              f"future_min={info['future_min']:.1f} -> {status}")
    
    # Combine all patients
    print("\n" + "=" * 60)
    print("Combining all patients...")
    print("=" * 60)
    
    X_all = np.vstack([data['X'] for data in all_patient_data.values()])
    y_all = np.concatenate([data['y'] for data in all_patient_data.values()])
    
    print(f"\nTotal before balancing: {len(y_all)} samples")
    print(f"  Class 0 (safe): {sum(y_all == 0)} ({100*sum(y_all == 0)/len(y_all):.1f}%)")
    print(f"  Class 1 (hypo risk): {sum(y_all == 1)} ({100*sum(y_all == 1)/len(y_all):.1f}%)")
    
    # Downsample majority class (hypo risk) to achieve better balance
    print(f"\nDownsampling majority class to {TARGET_RATIO}:1 ratio...")
    X_balanced, y_balanced = downsample_majority(X_all, y_all, target_ratio=TARGET_RATIO)
    
    print(f"After downsampling: {len(y_balanced)} samples")
    print(f"  Class 0 (safe): {sum(y_balanced == 0)} ({100*sum(y_balanced == 0)/len(y_balanced):.1f}%)")
    print(f"  Class 1 (hypo risk): {sum(y_balanced == 1)} ({100*sum(y_balanced == 1)/len(y_balanced):.1f}%)")
    
    # Patient-wise train/test split
    # Use first 4 patients for training, last 2 for testing
    train_patients = PATIENT_IDS[:4]
    test_patients = PATIENT_IDS[4:]
    
    print(f"\nPatient-wise split:")
    print(f"  Training patients: {train_patients}")
    print(f"  Testing patients: {test_patients}")
    
    X_train_list = []
    y_train_list = []
    X_test_list = []
    y_test_list = []
    
    for pid in train_patients:
        glucose_values, timestamps = load_patient_data(pid)
        X, y, _ = create_sliding_windows(glucose_values, timestamps)
        X_down, y_down = downsample_majority(X, y, target_ratio=TARGET_RATIO)
        X_train_list.append(X_down)
        y_train_list.append(y_down)
    
    for pid in test_patients:
        glucose_values, timestamps = load_patient_data(pid)
        X, y, _ = create_sliding_windows(glucose_values, timestamps)
        # Create balanced test subset for proper evaluation
        X_bal, y_bal = downsample_majority(X, y, target_ratio=1)  # 1:1 for evaluation
        X_test_list.append(X_bal)
        y_test_list.append(y_bal)
    
    X_train = np.vstack(X_train_list)
    y_train = np.concatenate(y_train_list)
    X_test = np.vstack(X_test_list)
    y_test = np.concatenate(y_test_list)
    
    # Quantize for FPGA
    X_train_q = quantize_glucose(X_train)
    X_test_q = quantize_glucose(X_test)
    
    print(f"\nFinal datasets:")
    print(f"  Training: {len(y_train)} samples ({sum(y_train)} hypo-risk)")
    print(f"  Testing (balanced): {len(y_test)} samples ({sum(y_test)} hypo-risk)")
    print(f"\n  Note: Test set balanced 1:1 for proper evaluation metrics.")
    print(f"  Use precision, recall, F1, AUC-ROC, AUC-PR for evaluation.")
    
    # Save datasets
    output_dir = "dataset"
    os.makedirs(output_dir, exist_ok=True)
    
    # Save numpy arrays
    np.save(os.path.join(output_dir, "X_train.npy"), X_train)
    np.save(os.path.join(output_dir, "X_train_quantized.npy"), X_train_q)
    np.save(os.path.join(output_dir, "y_train.npy"), y_train)
    np.save(os.path.join(output_dir, "X_test.npy"), X_test)
    np.save(os.path.join(output_dir, "X_test_quantized.npy"), X_test_q)
    np.save(os.path.join(output_dir, "y_test.npy"), y_test)
    
    # Save CSV for inspection
    pd.DataFrame(X_train[:1000], 
                 columns=[f"t-{i}" for i in range(WINDOW_SIZE-1, -1, -1)]).to_csv(
        os.path.join(output_dir, "X_train_sample.csv"), index=False)
    pd.DataFrame({"label": y_train[:1000]}).to_csv(
        os.path.join(output_dir, "y_train_sample.csv"), index=False)
    
    # Save dataset info
    with open(os.path.join(output_dir, "dataset_info.txt"), "w") as f:
        f.write("FPGA Hypoglycemia Prediction Dataset (FIXED)\n")
        f.write("=" * 50 + "\n\n")
        f.write("Configuration:\n")
        f.write(f"  Window size: {WINDOW_SIZE} samples ({WINDOW_SIZE * 5} min)\n")
        f.write(f"  Prediction horizon: {PREDICTION_HORIZON} samples ({PREDICTION_HORIZON * 5} min)\n")
        f.write(f"  Hypoglycemia threshold: {HYPO_THRESHOLD} mg/dL\n")
        f.write(f"  Safe threshold: {SAFE_THRESHOLD} mg/dL\n")
        f.write(f"  Quantization: 8-bit (0-255 maps to {GLUCOSE_MIN}-{GLUCOSE_MAX} mg/dL)\n\n")
        
        f.write("Split Strategy: Patient-wise (no leakage)\n")
        f.write(f"  Training patients: {train_patients}\n")
        f.write(f"  Testing patients: {test_patients}\n\n")
        
        f.write("Balancing: Downsampling majority class\n\n")
        
        f.write("Training Set:\n")
        f.write(f"  Total samples: {len(y_train)}\n")
        f.write(f"  Class 0 (safe): {sum(y_train == 0)}\n")
        f.write(f"  Class 1 (hypo risk): {sum(y_train == 1)}\n\n")
        
        f.write("Testing Set (balanced 1:1 for evaluation):\n")
        f.write(f"  Total samples: {len(y_test)}\n")
        f.write(f"  Class 0 (safe): {sum(y_test == 0)}\n")
        f.write(f"  Class 1 (hypo risk): {sum(y_test == 1)}\n\n")
        
        f.write("Recommended Evaluation Metrics:\n")
        f.write("  - Precision, Recall, F1-Score\n")
        f.write("  - AUC-ROC, AUC-PR (Average Precision)\n")
        f.write("  - Confusion Matrix\n")
        f.write("  - DO NOT use accuracy (misleading for imbalanced data)\n")
    
    print(f"\nDatasets saved to '{output_dir}/' directory:")
    print("  - X_train.npy, X_test.npy (balanced)")
    print("  - X_train_quantized.npy, X_test_quantized.npy (FPGA-ready)")
    print("  - y_train.npy, y_test.npy (labels)")
    print("  - X_train_sample.csv, y_train_sample.csv (inspection)")
    print("  - dataset_info.txt (summary)")
    
    print("\n" + "=" * 60)
    print("Dataset creation complete!")
    print("=" * 60)


if __name__ == "__main__":
    main()
