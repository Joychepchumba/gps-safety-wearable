import os
import httpx
import logging

logger = logging.getLogger(__name__)

class SmsService:
    def __init__(self):
        self.api_key = os.getenv("AFRICAS_TALKING_API_KEY") or os.getenv("AT_API_KEY")
        self.username = os.getenv("AFRICAS_TALKING_USERNAME") or os.getenv("AT_USERNAME")
        self.sender_id = os.getenv("AFRICAS_TALKING_SENDER_ID") or os.getenv("AT_SENDER_ID")
        self.police_number = os.getenv("POLICE_NUMBER", "0721228989")
        self.url = os.getenv("AFRICAS_TALKING_BASE_URL", "https://api.sandbox.africastalking.com/version1/messaging")

    def _format_phone(self, phone: str) -> str:
        p = phone.strip().replace(" ", "").replace("-", "")
        if p.startswith("+"):
            return p
        if p.startswith("0") and len(p) == 10:
            return "+254" + p[1:]
        if p.startswith("254") and len(p) == 12:
            return "+" + p
        if not p.startswith("+") and len(p) == 9:
            return "+254" + p
        return p

    def _get_live_base_url(self) -> str:
        # 1. Query live ngrok API on port 4040
        try:
            from app.core.ngrok_sync import get_ngrok_url
            url = get_ngrok_url()
            if url:
                return url
        except Exception:
            pass

        # 2. Check Supabase app_config table
        try:
            from supabase import create_client
            sb_url = os.getenv("SUPABASE_URL", "")
            sb_key = os.getenv("SUPABASE_SERVICE_KEY", os.getenv("SUPABASE_ANON_KEY", ""))
            if sb_url and sb_key:
                client = create_client(sb_url, sb_key)
                res = client.table("app_config").select("value").eq("key", "backend_url").execute()
                if res.data and res.data[0].get("value"):
                    return res.data[0]["value"]
        except Exception:
            pass

        # 3. Environment fallback
        return os.getenv("BACKEND_URL") or os.getenv("NGROK_URL") or "http://localhost:8000"

    def send_sms(self, to: list[str], message: str) -> dict:
        if not self.api_key or not self.username:
            logger.warning("[SMS] Africa's Talking credentials not configured.")
            return {}

        formatted_recipients = []
        seen = set()
        for p in to:
            if not p or not p.strip():
                continue
            fmt = self._format_phone(p)
            if fmt not in seen:
                seen.add(fmt)
                formatted_recipients.append(fmt)

        if not formatted_recipients:
            logger.warning("[SMS] No valid recipient phone numbers provided.")
            return {}

        headers = {
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
            "apiKey": self.api_key
        }
        
        results = {}
        to_str = ",".join(formatted_recipients)
        
        payload = {
            "username": self.username,
            "to": to_str,
            "message": message
        }
        if self.sender_id and self.username.strip().lower() != "sandbox":
            payload["from"] = self.sender_id
            
        try:
            with httpx.Client(timeout=10.0) as client:
                response = client.post(self.url, headers=headers, data=payload)
                response.raise_for_status()
                data = response.json()
                recipients = data.get("SMSMessageData", {}).get("Recipients", [])
                for r in recipients:
                    results[r.get("number", "")] = r.get("status", "")
                logger.info(f"[SMS SUCCESS] Africa's Talking dispatched SMS to {len(recipients)} numbers: {results}")
        except Exception as e:
            logger.error(f"[SMS ERROR] Failed to send SMS via Africa's Talking: {e}")
            
        return results

    def notify_emergency_contacts(self, phones: list[str], user_name: str, lat: float, lng: float, panic_event_id: str = None):
        base_url = self._get_live_base_url()
        from urllib.parse import quote
        if panic_event_id:
            mapbox_live_url = f"{base_url}/alert/track/{panic_event_id}"
        else:
            mapbox_live_url = f"{base_url}/alert/track/live?lat={lat}&lng={lng}&name={quote(user_name)}"
        
        message = (
            f"🚨 EMERGENCY ALERT: {user_name} triggered an SOS panic alarm!\n"
            f"Location: Lat {lat:.5f}, Lng {lng:.5f}\n"
            f"Live 3D Tracking: {mapbox_live_url}"
        )
        return self.send_sms(phones, message)

    def notify_police(self, user_name: str, lat: float, lng: float, panic_event_id: str = None):
        clean_police = (self.police_number or "").strip()
        if not clean_police or clean_police.startswith("0800") or clean_police.startswith("+254800"):
            logger.info(f"[SMS NOTICE] Police hotline ({clean_police}) is voice-only; skipping SMS dispatch.")
            return {}

        formatted_police = self._format_phone(clean_police)
        base_url = self._get_live_base_url()
        from urllib.parse import quote
        if panic_event_id:
            mapbox_live_url = f"{base_url}/alert/track/{panic_event_id}"
        else:
            mapbox_live_url = f"{base_url}/alert/track/live?lat={lat}&lng={lng}&name={quote(user_name)}"
        
        message = (
            f"🚨 POLICE DISPATCH: {user_name} needs urgent assistance!\n"
            f"Live 3D Tracking: {mapbox_live_url}"
        )
        return self.send_sms([formatted_police], message)
