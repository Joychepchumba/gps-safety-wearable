import os
import httpx
import logging

logger = logging.getLogger(__name__)

class SmsService:
    def __init__(self):
        # Support both AFRICAS_TALKING_* and AT_* environment variable conventions
        self.api_key = os.getenv("AFRICAS_TALKING_API_KEY") or os.getenv("AT_API_KEY")
        self.username = os.getenv("AFRICAS_TALKING_USERNAME") or os.getenv("AT_USERNAME") or "sandbox"
        self.sender_id = os.getenv("AFRICAS_TALKING_SENDER_ID") or os.getenv("AT_SENDER_ID")
        self.police_number = os.getenv("POLICE_NUMBER", "0800720999")
        
        # Determine endpoint URL
        default_url = (
            "https://api.sandbox.africastalking.com/version1/messaging"
            if self.username == "sandbox"
            else "https://api.africastalking.com/version1/messaging"
        )
        self.url = os.getenv("AFRICAS_TALKING_BASE_URL", default_url)
        
        if not self.api_key:
            logger.warning("[SMS SERVICE] AFRICAS_TALKING_API_KEY not configured in environment variables.")
        else:
            logger.info(
                "[SMS SERVICE] Initialized Africa's Talking SMS Service (Username: %s, Endpoint: %s)",
                self.username,
                self.url
            )

    def format_phone_number(self, phone: str) -> str:
        """Format phone number to international E.164 format (+254...)"""
        if not phone:
            return ""
        digits = ''.join(filter(str.isdigit, str(phone)))
        if not digits:
            return ""
        if digits.startswith("254"):
            return "+" + digits
        if digits.startswith("0"):
            return "+254" + digits[1:]
        if not digits.startswith("+"):
            return "+254" + digits
        return "+" + digits

    def send_sms(self, to: list[str], message: str) -> dict:
        """
        Dispatches SMS via Africa's Talking API (Sandbox or Production) using httpx.
        Returns a dict of {recipient_phone: delivery_status}.
        """
        if not self.api_key or not self.username:
            logger.warning("[SMS SERVICE] Cannot dispatch SMS: missing credentials.")
            return {}

        formatted_recipients = []
        for p in to:
            formatted = self.format_phone_number(p)
            if formatted and formatted not in formatted_recipients:
                formatted_recipients.append(formatted)

        if not formatted_recipients:
            logger.warning("[SMS SERVICE] No valid phone numbers provided to send_sms.")
            return {}

        to_str = ",".join(formatted_recipients)
        payload = {
            "username": self.username,
            "to": to_str,
            "message": message,
        }
        if self.sender_id:
            payload["from"] = self.sender_id

        headers = {
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
            "apiKey": self.api_key,
        }

        results = {}
        try:
            logger.info("[SMS SERVICE] Dispatching SMS via Africa's Talking to %s...", to_str)
            with httpx.Client(timeout=10.0) as client:
                response = client.post(self.url, headers=headers, data=payload)
                response.raise_for_status()
                data = response.json()
                
                sms_data = data.get("SMSMessageData", {})
                recipients = sms_data.get("Recipients", [])
                logger.info("[SMS SERVICE SUCCESS] %s", sms_data.get("Message", "Sent"))
                
                for r in recipients:
                    phone_num = r.get("number", "unknown")
                    status = r.get("status", "Unknown")
                    status_code = r.get("statusCode")
                    results[phone_num] = status
                    logger.info("  -> Recipient: %s, Status: %s (Code: %s)", phone_num, status, status_code)
                    
        except httpx.HTTPStatusError as e:
            logger.error("[SMS SERVICE HTTP ERROR] Status %s: %s", e.response.status_code, e.response.text)
        except Exception as e:
            logger.error("[SMS SERVICE ERROR] Failed to send SMS: %s", e)

        return results

    def notify_emergency_contacts(self, phones: list[str], user_name: str, lat: float, lng: float, tracking_link: str = None) -> dict:
        """Sends urgent SOS distress alert with real-time 3D tracking link to guardians."""
        link_str = tracking_link if tracking_link else f"https://maps.google.com/?q={lat},{lng}"
        message = (
            f"🚨 EMERGENCY SOS: {user_name} triggered a distress alert!\n"
            f"Live 3D Telemetry & Tracking: {link_str}\n"
            f"Coordinates: {lat:.5f}, {lng:.5f}"
        )
        return self.send_sms(phones, message)

    def notify_police(self, user_name: str, lat: float, lng: float, tracking_link: str = None) -> dict:
        """Sends police dispatch notification with live location link."""
        link_str = tracking_link if tracking_link else f"https://maps.google.com/?q={lat},{lng}"
        message = (
            f"🚨 POLICE DISPATCH ALERT: {user_name} activated emergency SOS.\n"
            f"Live 3D Incident Tracking: {link_str}\n"
            f"Coordinates: {lat:.5f}, {lng:.5f}"
        )
        return self.send_sms([self.police_number], message)
