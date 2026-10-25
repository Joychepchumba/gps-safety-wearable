"""
Script to generate production-grade, university-level NLP speech notebooks
for the SafeGuard GPS Wearable project.
"""
import json
import os

def create_notebook(cells, metadata=None):
    if metadata is None:
        metadata = {
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
        }
    return {
        "nbformat": 4,
        "nbformat_minor": 0,
        "metadata": metadata,
        "cells": cells
    }

def md_cell(source):
    if isinstance(source, list):
        src = [s if s.endswith("\n") else s + "\n" for s in source]
    else:
        src = [s + "\n" for s in source.split("\n")]
        # remove trailing newline on last line
        if src:
            src[-1] = src[-1].rstrip("\n")
    return {
        "cell_type": "markdown",
        "metadata": {},
        "source": src
    }

def code_cell(source):
    if isinstance(source, list):
        src = [s if s.endswith("\n") else s + "\n" for s in source]
    else:
        src = [s + "\n" for s in source.split("\n")]
        if src:
            src[-1] = src[-1].rstrip("\n")
    return {
        "cell_type": "code",
        "execution_count": None,
        "metadata": {},
        "outputs": [],
        "source": src
    }

print("Generator helper loaded successfully.")
