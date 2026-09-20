import os
import httpx
import logging

logger = logging.getLogger(__name__)

class PushService:
    def __init__(self):
        self.server_key = os.getenv("FCM_SERVER_KEY")
        self.url = "https://fcm.googleapis.com/fcm/send"

    async def notify_responders(self, push_tokens: list[str], user_name: str, lat: float, lng: float, distance_m: float = None):
        if not self.server_key:
            logger.warning("FCM Server Key not configured.")
            return
            
        headers = {
            "Authorization": f"key={self.server_key}",
            "Content-Type": "application/json"
        }
        
        message_body = f"Emergency nearby! {user_name} needs help."
        if distance_m is not None:
            message_body += f" Distance: {distance_m:.0f} meters."

        payload = {
            "registration_ids": push_tokens,
            "notification": {
                "title": "Community Responder Alert",
                "body": message_body
            },
            "data": {
                "lat": str(lat),
                "lng": str(lng)
            }
        }
        
        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(self.url, headers=headers, json=payload)
                response.raise_for_status()
                return response.json()
            except Exception as e:
                logger.error(f"Failed to send push notification: {e}")
