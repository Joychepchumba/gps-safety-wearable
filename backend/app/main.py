from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routes import alert_routes, user_routes, responder_routes
import logging

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

@app.on_event("startup")
async def startup_event():
    logger.info("GPS Safety Wearable Backend is ready!")

@app.get("/")
def read_root():
    return {"status": "ok", "service": "GPS Safety Wearable Backend"}