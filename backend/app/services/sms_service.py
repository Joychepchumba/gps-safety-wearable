import os
import requests
import logging

logger = logging.getLogger(__name__)

class SmsService:
    def __init__(self):
        self.api_key = os.getenv("AT_API_KEY")
        self.username = os.getenv("AT_USERNAME")
        self.sender_id = os.getenv("AT_SENDER_ID")
        self.police_number = os.getenv("POLICE_NUMBER", "0800720999")
        self.url = "https://api.africastalking.com/version1/messaging"

    def send_sms(self, to: list[str], message: str) -> dict:
        if not self.api_key or not self.username:
            logger.warning("SMS credentials not configured.")
            return {}

        headers = {
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
            "apiKey": self.api_key
        }
        
        results = {}
        to_str = ",".join(to)
        
        payload = {
            "username": self.username,
            "to": to_str,
            "message": message
        }
        if self.sender_id:
            payload["from"] = self.sender_id
            
        try:
            response = requests.post(self.url, headers=headers, data=payload)
            response.raise_for_status()
            data = response.json()
            recipients = data.get("SMSMessageData", {}).get("Recipients", [])
            for r in recipients:
                results[r["number"]] = r["status"]
        except Exception as e:
            logger.error(f"Failed to send SMS: {e}")
            
        return results

    def notify_emergency_contacts(self, phones: list[str], user_name: str, lat: float, lng: float):
        map_link = f"https://maps.google.com/?q={lat},{lng}"
        message = f"EMERGENCY: {user_name} has triggered a panic alert! Location: {map_link}"
        return self.send_sms(phones, message)

    def notify_police(self, user_name: str, lat: float, lng: float):
        map_link = f"https://maps.google.com/?q={lat},{lng}"
        message = f"EMERGENCY ALERT: {user_name} needs police assistance. Location: {map_link}"
        return self.send_sms([self.police_number], message)
