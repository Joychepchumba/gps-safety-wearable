import os
import sys
import json
sys.path.insert(0, os.path.dirname(__file__))
from build_nb1 import get_notebook_1
from build_nb2 import get_notebook_2
from build_nb3 import get_notebook_3

def make_master_notebook():
    nb1 = get_notebook_1()
    nb2 = get_notebook_2()
    nb3 = get_notebook_3()
    
    # Header cell for the master notebook
    header_md = {
        "cell_type": "markdown",
        "metadata": {},
        "source": [
            "# 🌟 SafeGuard STT — End-to-End Master NLP Pipeline (All-In-One)\n",
            "### Project: SafeGuard GPS Safety Wearable & Emergency Response System\n",
            "**Institution:** Strathmore University | **Author:** Joy Kipkemboi\n",
            "**Architecture:** Meta MMS (Massively Multilingual Speech) • CTC Alignment • Kenyan Kiswahili + English\n",
            "\n",
            "---\n",
            "### 🎯 What This Single Notebook Does (Complete 6-Stage Engineering Workflow):\n",
            "1. **Environment Setup & Dependencies:** Auto-detects Colab T4 GPU and fast local NVMe storage.\n",
            "2. **Acoustic Preprocessing & VAD:** 16 kHz mono resampling, Voice Activity Detection silence trimming, and peak normalization.\n",
            "3. **Data Ingestion:** Streams Google FLEURS (`sw_ke` & `en_us`) + emergency distress wake phrases (`tuma msaada`, `piga polisi`, `send help`, `call police`).\n",
            "4. **Exploratory Data Analysis (EDA):** Waveform plots, 128-band Mel-Spectrograms, SNR distribution, and character/token vocabulary frequencies.\n",
            "5. **Zero-Leakage Stratified Splitting:** Enforces speaker/recording-disjoint Train (80%) / Dev (10%) / Test (10%) + 10 dB SNR Noisy stress-test set.\n",
            "6. **Negative Control Baseline:** Empirically documents the naive untuned baseline (100% WER) to satisfy scientific peer review.\n",
            "7. **Meta MMS Transfer Learning:** Fine-tunes `facebook/mms-300m` with AdamW, Cosine Annealing, 10% warmup, and SpecAugment.\n",
            "8. **Convergence Visualizations:** Plots Training Loss vs. Validation Loss vs. Validation WER per epoch.\n",
            "9. **Multi-Metric Evaluation:** Clean vs. Noisy Test WER & CER, Wake-Word Precision/Recall/F1, and Seaborn Confusion Matrix.\n",
            "10. **Model Export:** Packages the final weights into `safeguard_voice_model.zip` and triggers an automatic browser download for FastAPI.\n",
            "\n",
            "**Runtime Recommendation:** Runtime → Change runtime type → **T4 GPU** (~10–12 minutes total run time).\n"
        ]
    }
    
    # We combine the cells from nb1, nb2, nb3 cleanly without duplicate drive mounts or redundant pip installs
    master_cells = [header_md]
    
    # Stage 1 Cells (Skip archive packaging since we can flow directly in memory)
    # nb1 cells: 0 is title, 1 is config, 2 is pip, 3 is VAD, 4 is fleurs, 5 is emergency, 6 is noise, 7 is eda acoustic, 8 is eda spectral, 9 is eda lexical, 10 is split, 11 is zip
    for i, c in enumerate(nb1["cells"]):
        if i == 0:
            master_cells.append({
                "cell_type": "markdown",
                "metadata": {},
                "source": ["## 📁 PART 1: Data Ingestion, Acoustic Preprocessing & EDA\n"]
            })
        elif i == 11:
            # skip the zip in stage 1 since stage 2 will run in the same memory/disk!
            continue
        else:
            master_cells.append(c)
            
    # Stage 2 Cells
    # nb2 cells: 0 is title, 1 is setup, 2 is unzip, 3 is pip, 4 is vocab, 5 is baseline, 6 is mms model, 7 is collator, 8 is metrics, 9 is hyperparams, 10 is train, 11 is plot, 12 is save
    for i, c in enumerate(nb2["cells"]):
        if i == 0:
            master_cells.append({
                "cell_type": "markdown",
                "metadata": {},
                "source": ["## 🧠 PART 2: Foundation Model Fine-Tuning & Hyperparameter Optimization\n"]
            })
        elif i in [1, 2, 3]:
            # skip duplicate setup, unzip, and pip install
            continue
        else:
            master_cells.append(c)
            
    # Stage 3 Cells
    # nb3 cells: 0 is title, 1 is setup, 2 is pip, 3 is load model, 4 is eval, 5 is benchmark, 6 is kws, 7 is cm, 8 is latency, 9 is error analysis, 10 is export, 11 is demo
    for i, c in enumerate(nb3["cells"]):
        if i == 0:
            master_cells.append({
                "cell_type": "markdown",
                "metadata": {},
                "source": ["## 📊 PART 3: Multi-Metric Evaluation, Confusion Matrix & Model Export\n"]
            })
        elif i in [1, 2, 3]:
            # skip duplicate setup and reload
            continue
        else:
            master_cells.append(c)
            
    return {
        "nbformat": 4,
        "nbformat_minor": 0,
        "metadata": {
            "accelerator": "GPU",
            "colab": {
                "gpuType": "T4",
                "provenance": []
            },
            "kernelspec": {
                "display_name": "Python 3",
                "name": "python3"
            },
            "language_info": {
                "name": "python",
                "version": "3.10"
            }
        },
        "cells": master_cells
    }

if __name__ == "__main__":
    out_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "ml", "keyword_detection", "notebooks"))
    os.makedirs(out_dir, exist_ok=True)
    master_nb = make_master_notebook()
    
    master_path = os.path.join(out_dir, "SafeGuard_STT_Master_Pipeline.ipynb")
    with open(master_path, "w", encoding="utf-8") as f:
        json.dump(master_nb, f, indent=1, ensure_ascii=False)
        
    print(f"Master Notebook generated successfully at: {master_path}")
    print(f"Total cells: {len(master_nb['cells'])}")
