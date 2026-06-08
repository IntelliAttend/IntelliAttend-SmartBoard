import logging
import httpx
import os
from datetime import datetime, timezone

logger = logging.getLogger("IntelliAttend.Alerts")

# In production, these should be real webhook URLs or email SMTP settings
SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL")

class AlertService:
    @staticmethod
    async def notify_stale_board(board_id: str, last_seen: datetime):
        """
        Notifies IT staff when a Smart Board stops sending heartbeats.
        """
        message = (
            f"🚨 *CRITICAL: Heartbeat Lost*\n"
            f"*Board ID:* `{board_id}`\n"
            f"*Last Seen:* {last_seen.strftime('%Y-%m-%d %H:%M:%S')} UTC\n"
            f"*Status:* DISCONNECTED\n"
            f"Please check classroom connectivity or hardware state."
        )
        
        logger.error(f"📡 [Alert] Heartbeat lost for board {board_id}. Last seen: {last_seen}")
        
        if SLACK_WEBHOOK_URL:
            try:
                async with httpx.AsyncClient() as client:
                    await client.post(SLACK_WEBHOOK_URL, json={"text": message})
            except Exception as e:
                logger.error(f"❌ [Alert] Failed to send Slack notification: {e}")
        else:
            logger.info("ℹ️ [Alert] No Slack Webhook configured. Notification logged locally.")

    @staticmethod
    async def notify_security_violation(board_id: str, reason: str):
        """
        Notifies IT staff of potential tampering or spoofing attempts.
        """
        message = (
            f"🛡️ *SECURITY ALERT: Potential Tampering*\n"
            f"*Board ID:* `{board_id}`\n"
            f"*Reason:* {reason}\n"
            f"*Action:* Access blocked. Investigate hardware integrity."
        )
        
        logger.warning(f"🚨 [Security] Potential violation on board {board_id}: {reason}")
        
        if SLACK_WEBHOOK_URL:
            try:
                async with httpx.AsyncClient() as client:
                    await client.post(SLACK_WEBHOOK_URL, json={"text": message})
            except Exception as e:
                logger.error(f"❌ [Alert] Failed to send security notification: {e}")
