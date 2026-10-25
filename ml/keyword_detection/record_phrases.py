"""
SafeGuard Local Voice Collector
Records 16kHz Mono 16-bit WAV samples for emergency wake-word training
Generates custom_train.csv ready for the SafeGuard GitHub dataset repo
"""

import os
import time
import csv

try:
    # pyrefly: ignore [missing-import]
    import sounddevice as sd
    # pyrefly: ignore [missing-import]
    import soundfile as sf
    import numpy as np
except ImportError:
    print("Please install requirements: pip install sounddevice soundfile numpy")
    exit(1)

TARGET_PHRASES = [
    ("tuma msaada", "sw"),   # Kiswahili: Send help
    ("piga polisi", "sw"),   # Kiswahili: Call police
    ("send help", "en"),     # English: Send help
    ("call police", "en"),   # English: Call police
]

SAMPLE_RATE = 16000
DURATION_SECONDS = 2.5
OUTPUT_BASE_DIR = os.path.join(os.path.dirname(__file__), "dataset", "custom")
CSV_OUTPUT_PATH = os.path.join(os.path.dirname(__file__), "dataset", "custom_train.csv")


def record_sample(phrase: str, lang: str, sample_idx: int) -> dict:
    folder_name = phrase.replace(" ", "_")
    target_dir = os.path.join(OUTPUT_BASE_DIR, folder_name)
    os.makedirs(target_dir, exist_ok=True)

    filename = f"{folder_name}_{sample_idx:03d}.wav"
    filepath = os.path.join(target_dir, filename)

    print(f"\n[{lang.upper()}] Say clearly:  >>  \"{phrase}\"  <<")
    print("Ready... 3, 2, 1, speak!")

    recording = sd.rec(
        int(DURATION_SECONDS * SAMPLE_RATE),
        samplerate=SAMPLE_RATE,
        channels=1,
        dtype='int16'
    )
    sd.wait()

    # Peak normalization
    max_val = np.max(np.abs(recording))
    if max_val > 0:
        recording = (recording / max_val * 30000).astype(np.int16)

    sf.write(filepath, recording, SAMPLE_RATE, subtype='PCM_16')
    filesize = os.path.getsize(filepath)

    rel_path = os.path.relpath(filepath, os.path.join(os.path.dirname(__file__), "dataset")).replace("\\", "/")
    print(f" Saved: {rel_path} ({filesize} bytes)")

    return {
        "wav_filename": f"custom/{folder_name}/{filename}",
        "wav_filesize": filesize,
        "transcript": phrase
    }


def main():
    print("=" * 60)
    print("SafeGuard Custom Wake-Word Audio Collector")
    print(f"Sample Rate: {SAMPLE_RATE} Hz | Channels: Mono | Format: 16-bit WAV")
    print("=" * 60)

    num_samples_per_phrase = 25
    try:
        val = input(f"How many samples per phrase? (Default: {num_samples_per_phrase}): ").strip()
        if val:
            num_samples_per_phrase = int(val)
    except ValueError:
        pass

    all_records = []
    
    # Load existing if file exists
    if os.path.exists(CSV_OUTPUT_PATH):
        with open(CSV_OUTPUT_PATH, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            all_records = list(reader)
        print(f"Found {len(all_records)} existing records in {CSV_OUTPUT_PATH}")

    for phrase, lang in TARGET_PHRASES:
        print(f"\n==========================================")
        print(f"PHRASE: '{phrase}' ({lang})")
        print(f"==========================================")
        
        folder_name = phrase.replace(" ", "_")
        existing_in_phrase = len([r for r in all_records if r["transcript"] == phrase])

        for i in range(1, num_samples_per_phrase + 1):
            idx = existing_in_phrase + i
            input(f"\nPress Enter to record clip #{idx} for '{phrase}' (or Ctrl+C to stop)...")
            record_info = record_sample(phrase, lang, idx)
            all_records.append(record_info)

    # Save to CSV
    os.makedirs(os.path.dirname(CSV_OUTPUT_PATH), exist_ok=True)
    with open(CSV_OUTPUT_PATH, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=["wav_filename", "wav_filesize", "transcript"])
        writer.writeheader()
        writer.writerows(all_records)

    print("\n" + "=" * 60)
    print(f" All recordings saved! Total entries in CSV: {len(all_records)}")
    print(f" CSV saved to: {CSV_OUTPUT_PATH}")
    print("Push the 'dataset' folder to your GitHub repo to train in Colab.")
    print("=" * 60)


if __name__ == "__main__":
    main()
