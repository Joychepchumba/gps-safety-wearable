from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime

class AlertFromPendant(BaseModel):
    device_mac: str
    latitude: float
    longitude: float
    accuracy_m: Optional[float] = None
    trigger_method: str = "pendant_touch"
    timestamp: Optional[datetime] = None

class UserLocation(BaseModel):
    user_id: str
    latitude: float
    longitude: float

class NearbyRespondersRequest(BaseModel):
    latitude: float
    longitude: float
    radius_m: float = 1000.0

class SmsRequest(BaseModel):
    to: List[str]
    message: str

class AlertResponse(BaseModel):
    success: bool
    panic_event_id: Optional[str] = None
    sms_results: Optional[dict] = None
    responders_alerted: Optional[int] = 0

class UserRequest(BaseModel):
    user_id: str

class ResponderStatusUpdate(BaseModel):
    user_id: str
    status: str

class SetEmergencyPasswordRequest(BaseModel):
    user_id: str
    emergency_password: str = Field(..., min_length=4, max_length=64, description="Secret emergency duress password or PIN")

class VerifyEmergencyPasswordRequest(BaseModel):
    user_id: str
    password_attempt: str

class UserProfileResponse(BaseModel):
    id: str
    full_name: str
    phone_number: str
    email: Optional[str] = None
    is_community_responder: bool = False
    responder_status: Optional[str] = None
    has_emergency_password: bool = False
    has_wearable: bool = False
    created_at: Optional[str] = None
