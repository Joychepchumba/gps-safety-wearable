import os
from pathlib import Path
from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import logging

# Load environment variables from backend/.env or root .env
backend_env = Path(__file__).resolve().parent.parent / ".env"
root_env = Path(__file__).resolve().parent.parent.parent / ".env"
if backend_env.exists():
    load_dotenv(backend_env)
elif root_env.exists():
    load_dotenv(root_env)

from app.routes import alert_routes, user_routes, responder_routes, gps_routes
from app.core.ngrok_sync import run_auto_sync

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="GPS Safety Wearable Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(alert_routes.router)
app.include_router(user_routes.router)
app.include_router(responder_routes.router)
app.include_router(gps_routes.router)

@app.on_event("startup")
async def startup_event():
    logger.info("GPS Safety Wearable Backend is starting up...")
    ngrok_url = run_auto_sync(8000)
    print("\n" + "=" * 55)
    print("  SAFEGUARD / SAFELINK BACKEND READY")
    print("  Local API:  http://localhost:8000")
    if ngrok_url:
        print(f"  Live ngrok: {ngrok_url}")
        print("  Mobile app will sync with this tunnel automatically!")
    else:
        print("  ngrok:      Not detected. Running on local network.")
    print("=" * 55 + "\n")

@app.get("/")
def read_root():
    return {"status": "ok", "service": "GPS Safety Wearable Backend"}