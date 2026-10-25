import os
import io
import re
import wave
import logging
from pathlib import Path
from typing import Optional, List
from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException, Query
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel
from supabase import Client

from app.routes.alert_routes import process_alert, get_supabase

logger = logging.getLogger("voice_routes")

router = APIRouter(prefix="/voice", tags=["voice"])

# Directory where fine-tuned Meta MMS / Wav2Vec2 weights will live
MODEL_DIR = Path(__file__).resolve().parent.parent / "models" / "safeguard_mms"

EMERGENCY_KEYWORDS = [
    # Kiswahili emergency triggers
    "tuma msaada",
    "msaada",
    "piga polisi",
    "nisaidie",
    "okoa maisha",
    "hatari",
    "polisi",
    # English emergency triggers
    "send help",
    "help me",
    "help",
    "emergency",
    "call police",
    "call the police",
    "save me",
]

# Lazy-loaded model & processor cache
_model_cache = {
    "model": None,
    "processor": None,
    "loaded": False,
    "error": None
}

def load_voice_model():
    """Attempts to lazy-load fine-tuned Whisper or Meta MMS / Wav2Vec2 model."""
    if _model_cache["loaded"] and _model_cache["model"] is not None:
        return _model_cache["model"], _model_cache["processor"], _model_cache.get("is_whisper", False)

    if not MODEL_DIR.exists():
        _model_cache["error"] = f"Model directory not found at {MODEL_DIR}."
        return None, None, False

    try:
        import json
        import torch
        from transformers import AutoProcessor, AutoModelForSpeechSeq2Seq, Wav2Vec2ForCTC

        cfg_path = MODEL_DIR / "config.json"
        is_whisper = False
        if cfg_path.exists():
            with open(cfg_path, "r", encoding="utf-8") as f:
                cfg = json.load(f)
                archs = cfg.get("architectures", [])
                if any("Whisper" in a for a in archs):
                    is_whisper = True

        logger.info(f"Loading SafeGuard voice model from {MODEL_DIR} (is_whisper={is_whisper})...")
        processor = AutoProcessor.from_pretrained(str(MODEL_DIR))

        if is_whisper:
            model = AutoModelForSpeechSeq2Seq.from_pretrained(str(MODEL_DIR))
        else:
            model = Wav2Vec2ForCTC.from_pretrained(str(MODEL_DIR))

        model.eval()

        _model_cache["model"] = model
        _model_cache["processor"] = processor
        _model_cache["is_whisper"] = is_whisper
        _model_cache["loaded"] = True
        _model_cache["error"] = None
        logger.info("SafeGuard voice model loaded successfully into memory.")
        return model, processor, is_whisper
    except Exception as e:
        logger.warning(f"Could not load voice model from {MODEL_DIR}: {e}")
        _model_cache["error"] = str(e)
        return None, None, False

def transcribe_audio_bytes(audio_bytes: bytes) -> str:
    """Transcribes raw audio bytes using the fine-tuned speech model."""
    model, processor, is_whisper = load_voice_model()

    if model is not None and processor is not None:
        try:
            import torch
            import soundfile as sf

            # Read audio data from memory buffer
            audio_buf = io.BytesIO(audio_bytes)
            speech_array, sampling_rate = sf.read(audio_buf)

            # Convert stereo to mono if necessary
            if len(speech_array.shape) > 1:
                speech_array = speech_array.mean(axis=1)

            # Resample to 16,000 Hz if needed
            if sampling_rate != 16000:
                try:
                    import scipy.signal
                    speech_array = scipy.signal.resample(speech_array, int(len(speech_array) * 16000 / sampling_rate))
                except Exception:
                    pass

            if is_whisper:
                # Ignore near-silent clips: Whisper hallucinates text on silence.
                import numpy as np
                if float(np.sqrt(np.mean(np.square(speech_array)))) < 0.003:
                    return ""

                inputs = processor(speech_array, sampling_rate=16000, return_tensors="pt")
                texts = []
                # whisper-tiny often mis-detects the language of short clips, so
                # decode once as Kiswahili and once as English.
                for lang in ("swahili", "english"):
                    with torch.no_grad():
                        predicted_ids = model.generate(
                            inputs.input_features,
                            language=lang,
                            task="transcribe",
                            max_new_tokens=48,
                        )
                    texts.append(processor.batch_decode(predicted_ids, skip_special_tokens=True)[0].strip())
                transcription = " | ".join(t for t in texts if t)
            else:
                inputs = processor(speech_array, sampling_rate=16000, return_tensors="pt")
                with torch.no_grad():
                    logits = model(inputs.input_values).logits
                predicted_ids = torch.argmax(logits, dim=-1)
                transcription = processor.batch_decode(predicted_ids)[0]

            return transcription.strip().lower()
        except Exception as e:
            logger.error(f"Inference error with voice model: {e}")

    # Fallback: check if standard wav format
    try:
        with wave.open(io.BytesIO(audio_bytes), "rb") as wf:
            n_frames = wf.getnframes()
            rate = wf.getframerate()
            duration_s = n_frames / float(rate)
            logger.info(f"Received audio buffer: {duration_s:.2f}s @ {rate}Hz")
    except Exception:
        pass

    return ""

def check_for_emergency_keywords(text: str, custom_phrase: Optional[str] = None) -> tuple[bool, Optional[str]]:
    """Checks whether text contains any emergency wake phrases (supporting exact, token, and subword matching)."""
    clean = text.lower().strip()
    if not clean:
        return False, None

    # 1. Custom user-trained phrase match if provided
    if custom_phrase and custom_phrase.strip():
        cp = custom_phrase.lower().strip()
        if cp in clean:
            return True, cp
        # Token match for custom phrase
        cp_tokens = set(re.findall(r"\w+", cp))
        text_tokens = set(re.findall(r"\w+", clean))
        if cp_tokens and cp_tokens.issubset(text_tokens):
            return True, cp
        # Subword match
        cp_collapsed = "".join([c for c in cp if c.isalpha()])
        text_collapsed = "".join([c for c in clean if c.isalpha()])
        if cp_collapsed and cp_collapsed in text_collapsed:
            return True, cp

    for kw in EMERGENCY_KEYWORDS:
        if kw in clean:
            return True, kw

    # Token overlap check (e.g. 'msaada' or 'polisi' present)
    tokens = set(re.findall(r"\w+", clean))
    critical_singles = ["msaada", "polisi", "hatari", "nisaidie", "help", "emergency"]
    for cs in critical_singles:
        if cs in tokens:
            return True, cs

    # Collapsed/Subword matching (e.g. "tu mam sada" -> "tumamsada" contains "msada" or "tumamsaada")
    collapsed = "".join([c for c in clean if c.isalpha()])
    collapsed_keywords = [
        ("tumamsada", "tuma msaada"),
        ("tumamsaada", "tuma msaada"),
        ("msada", "msaada"),
        ("msaada", "msaada"),
        ("pigapolisi", "piga polisi"),
        ("nisaidie", "nisaidie"),
        ("sendhelp", "send help"),
        ("callpolice", "call police"),
        ("emergency", "emergency")
    ]
    for ck, formal in collapsed_keywords:
        if ck in collapsed:
            return True, formal

    return False, None


class VoiceDetectionTextPayload(BaseModel):
    text: str
    user_id: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    accuracy_m: Optional[float] = 10.0
    auto_trigger: bool = True
    emergency_contacts: Optional[List[str]] = None


@router.get("/status")
def get_voice_service_status():
    """Returns current status of the SafeGuard Speech Recognition Model & API."""
    model, processor, is_whisper = load_voice_model()
    return {
        "status": "ready",
        "service": "SafeGuard Multilingual Voice Recognition & Wake-Word Engine",
        "model_architecture": "Whisper" if is_whisper else "Wav2Vec2/MMS",
        "model_loaded": model is not None,
        "model_dir": str(MODEL_DIR),
        "model_exists_on_disk": MODEL_DIR.exists(),
        "error": _model_cache["error"],
        "supported_keywords": EMERGENCY_KEYWORDS,
        "supported_languages": ["swh (Kiswahili)", "eng (English)"],
        "endpoint": "/voice/detect"
    }


@router.post("/detect")
async def detect_voice_emergency(
    audio: Optional[UploadFile] = File(None),
    text: Optional[str] = Form(None),
    custom_phrase: Optional[str] = Form(None),
    user_id: Optional[str] = Form(None),
    latitude: Optional[float] = Form(None),
    longitude: Optional[float] = Form(None),
    accuracy_m: Optional[float] = Form(10.0),
    auto_trigger: bool = Form(True),
):
    """
    Main Speech Recognition & Emergency Trigger Endpoint:
    1. Accepts voice audio stream/file OR client-transcribed text
    2. Transcribes using fine-tuned Whisper / MMS Swahili/English model
    3. Evaluates wake phrase match against custom phrase & defaults
    4. Automatically dispatches SOS alert, SMS, and 3D Live Mapbox Tracking if coordinates provided!
    """
    transcription = ""

    if audio is not None:
        raw_bytes = await audio.read()
        # Model inference is CPU-heavy and blocking: keep it off the event loop.
        transcription = await run_in_threadpool(transcribe_audio_bytes, raw_bytes)

    if not transcription and text:
        transcription = text.strip()

    is_emergency, matched_keyword = check_for_emergency_keywords(transcription, custom_phrase=custom_phrase)

    alert_result = None
    tracking_url = None

    if is_emergency and auto_trigger and user_id and latitude is not None and longitude is not None:
        try:
            logger.info(f"🎙️ [EMERGENCY VOICE CONFIRMED] Triggering SOS for user {user_id} with keyword '{matched_keyword}'")
            alert_resp = await process_alert(
                user_id=user_id,
                trigger_method="voice_keyword",
                lat=latitude,
                lng=longitude,
                accuracy=accuracy_m or 10.0,
                wearable_id=None,
                supabase=get_supabase()
            )
            base_url = os.getenv("BACKEND_URL") or os.getenv("NGROK_URL") or "https://unpaved-coherent-encroach.ngrok-free.dev"
            tracking_url = f"{base_url}/alert/track/{alert_resp.panic_event_id}"
            alert_result = {
                "success": alert_resp.success,
                "panic_event_id": alert_resp.panic_event_id,
                "sms_results": alert_resp.sms_results,
                "responders_alerted": alert_resp.responders_alerted
            }
        except Exception as e:
            logger.error(f"Failed to auto-dispatch alert from voice endpoint: {e}")
            alert_result = {"success": False, "error": str(e)}

    return {
        "transcription": transcription,
        "emergency_detected": is_emergency,
        "matched_keyword": matched_keyword,
        "sos_triggered": alert_result is not None and alert_result.get("success", False),
        "tracking_url": tracking_url,
        "alert_details": alert_result
    }


@router.post("/detect/text")
async def detect_voice_emergency_text(
    payload: VoiceDetectionTextPayload,
    supabase: Client = Depends(get_supabase)
):
    """Helper endpoint for JSON text-based detection from mobile app."""
    is_emergency, matched_keyword = check_for_emergency_keywords(payload.text)

    alert_result = None
    tracking_url = None

    if is_emergency and payload.auto_trigger and payload.user_id and payload.latitude is not None and payload.longitude is not None:
        try:
            logger.info(f"🎙️ [EMERGENCY VOICE CONFIRMED] Triggering SOS for user {payload.user_id} with keyword '{matched_keyword}'")
            alert_resp = await process_alert(
                user_id=payload.user_id,
                trigger_method="voice_keyword",
                lat=payload.latitude,
                lng=payload.longitude,
                accuracy=payload.accuracy_m or 10.0,
                wearable_id=None,
                supabase=supabase,
                provided_contacts=payload.emergency_contacts
            )
            base_url = os.getenv("BACKEND_URL") or os.getenv("NGROK_URL") or "https://unpaved-coherent-encroach.ngrok-free.dev"
            tracking_url = f"{base_url}/alert/track/{alert_resp.panic_event_id}"
            alert_result = {
                "success": alert_resp.success,
                "panic_event_id": alert_resp.panic_event_id,
                "sms_results": alert_resp.sms_results,
                "responders_alerted": alert_resp.responders_alerted
            }
        except Exception as e:
            logger.error(f"Failed to auto-dispatch alert: {e}")
            alert_result = {"success": False, "error": str(e)}

    return {
        "transcription": payload.text,
        "emergency_detected": is_emergency,
        "matched_keyword": matched_keyword,
        "sos_triggered": alert_result is not None and alert_result.get("success", False),
        "tracking_url": tracking_url,
        "alert_details": alert_result
    }
