# FPGA Hypoglycemia Predictor - Project Directory

**Last Updated:** March 23, 2026  
**Status:** ✅ Organized & Ready for Submission

---

## 📁 Directory Structure

```
D:\final FPGA\
│
├── 📄 README.md                       ← This file (directory guide)
│
├── 📁 submission/                     ← ⭐ SUBMISSION PACKAGE (ready to submit)
│   ├── README.md                      ← How to use submission package
│   ├── SUBMISSION_SUMMARY.md          ← Quick overview
│   ├── fpga/                          ← RTL source files + testbenches
│   ├── python/                        ← Python scripts
│   ├── docs/                          ← Documentation
│   └── simulation_results/            ← All PASS logs
│
├── 📁 fpga/                           ← FPGA development directory
│   ├── src/                           ← RTL source files
│   ├── tb/                            ← Testbenches
│   ├── sim_output/                    ← Simulation outputs
│   └── *.mem                          ← Weight files
│
├── 📁 mem_files/                      ← Weight export directory
│   ├── *.mem                          ← All weight files
│   └── golden_test_vectors.json       ← Python reference outputs
│
├── 📁 models/                         ← Trained Keras models
│   └── tiny_cnn_hypo.keras            ← Trained model
│
├── 📁 dataset/                        ← Dataset files
│   └── *.npy, *.csv                   ← Processed data
│
└── 📁 _archive/                       ← Working files & history
    ├── python_scripts/                ← Python scripts (working copies)
    ├── documentation/                 ← Documentation drafts
    ├── optimization_study/            ← Optimization experiments
    └── plans/                         ← Implementation plans
```

---

## 🎯 Quick Navigation

### For Submission
**Go to:** `submission/`  
**Contains:** Everything needed for submission (verified, working code)

### For Running Simulation
**Go to:** `fpga/`  
**Command:** `iverilog -o sim.vvp src/*.v tb/tb_hypoglycemia_predictor.v && vvp sim.vvp`

### For Exporting Weights
**Go to:** `mem_files/`  
**Command:** `python ../_archive/python_scripts/export_weights.py`

### For Training Model
**Go to:** `models/`  
**Command:** `python ../_archive/python_scripts/train_model.py`

---

## 📦 What's in Each Folder

### `submission/` - ⭐ Ready for Submission
- ✅ All working RTL code
- ✅ All testbenches (PASS)
- ✅ All weight files
- ✅ Python scripts
- ✅ Documentation
- ✅ Simulation results

**Use this folder for submission!**

### `fpga/` - FPGA Development
- `src/` - RTL source files (9 modules)
- `tb/` - Testbenches (5 files)
- `sim_output/` - Simulation logs
- `*.mem` - Weight initialization files

**Use this for running simulations!**

### `mem_files/` - Weight Export
- `*.mem` - All weight files in Q8.8 format
- `golden_test_vectors.json` - Python reference outputs
- `weight_map.json` - Memory map

**Use this for weight files!**

### `models/` - Trained Models
- `tiny_cnn_hypo.keras` - Trained Keras model
- `tiny_cnn_hypo.weights.h5` - Weights only
- `training_history.json` - Training history

**Use this for model!**

### `dataset/` - Dataset
- `X_train.npy`, `X_test.npy` - Features
- `y_train.npy`, `y_test.npy` - Labels
- `dataset_info.txt` - Dataset documentation

**Use this for data!**

### `_archive/` - Working Files
- `python_scripts/` - Working Python scripts
- `documentation/` - Documentation drafts
- `optimization_study/` - Optimization experiments
- `plans/` - Implementation plans

**These are working/history files - not needed for submission!**

---

## ✅ Clean Directory Status

### Main Directory (D:\final FPGA\)
```
✅ submission/          ← Ready for submission
✅ fpga/                ← FPGA development
✅ mem_files/           ← Weight files
✅ models/              ← Trained models
✅ dataset/             ← Dataset
✅ _archive/            ← Working files (hidden)
```

**No loose files in main directory!**

---

## 📊 File Organization Summary

| Location | Purpose | Files |
|----------|---------|-------|
| `submission/` | ⭐ Submission | 40 files |
| `fpga/` | FPGA development | ~20 files |
| `mem_files/` | Weights | ~15 files |
| `models/` | Trained models | ~5 files |
| `dataset/` | Dataset | ~13 files |
| `_archive/` | Working files | ~25 files |

---

## 🚀 Common Tasks

### Task 1: Run Simulation
```bash
cd D:\final FPGA\fpga
iverilog -o sim.vvp src/*.v tb/tb_hypoglycemia_predictor.v
vvp sim.vvp
```

### Task 2: Export Weights
```bash
cd D:\final FPGA
python _archive/python_scripts/export_weights.py
```

### Task 3: Train Model
```bash
cd D:\final FPGA
python _archive/python_scripts/train_model.py
```

### Task 4: Verify RTL vs Python
```bash
cd D:\final FPGA
python _archive/python_scripts/compare_rtl_vs_python.py
```

---

## 📝 Notes

1. **`submission/` is self-contained** - Can be copied and submitted as-is
2. **`_archive/` contains working files** - Not needed for submission
3. **All loose files moved to `_archive/`** - Main directory is clean
4. **Documentation in `submission/docs/`** - Ready for review

---

## 🎯 Next Steps

1. ✅ Directory is clean and organized
2. ✅ Submission package ready (`submission/`)
3. ⏳ Proceed with Early Exit implementation (optional)
4. ⏳ Final review before submission

---

**Directory Status:** ✅ **CLEAN & ORGANIZED**  
**Submission Package:** ✅ **READY**  
**Date:** March 23, 2026
