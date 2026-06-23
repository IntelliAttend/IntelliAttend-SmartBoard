import asyncio
import httpx
import time
import uuid
import random
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("LoadTest")

# Configuration
BASE_URL = "http://127.0.0.1:8000"
NUM_BOARDS = 10
NUM_SCANS_PER_BOARD = 50
CONCURRENT_REQUESTS = 20

async def simulate_board_lifecycle(board_id: str):
    """
    Simulates a Smart Board's heartbeat and session initiation.
    """
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=10.0) as client:
        # 1. Heartbeat
        try:
            start_time = time.perf_counter()
            resp = await client.post("/api/v1/device/heartbeat", 
                headers={"X-Device-ID": f"HW-{board_id}"},
                json={
                    "screen_state": "active",
                    "uptime_seconds": 3600,
                    "app_version": "6.4.0",
                    "timestamp_ms": int(time.time() * 1000)
                }
            )
            latency = (time.perf_counter() - start_time) * 1000
            if resp.status_code == 200:
                logger.info(f"✅ Board {board_id} heartbeat success ({latency:.2f}ms)")
            else:
                logger.error(f"❌ Board {board_id} heartbeat failed: {resp.status_code}")
        except Exception as e:
            logger.error(f"💥 Board {board_id} connection error: {e}")

async def simulate_attendance_scan(session_id: str, board_id: str):
    """
    Simulates a student scanning a QR code.
    """
    student_id = f"STU-{uuid.uuid4().hex[:8]}"
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=10.0) as client:
        try:
            start_time = time.perf_counter()
            # Note: In production this would hit the Trust Engine /attendance endpoint
            # For this test, we hit the Vault Sync which handles batched scans.
            resp = await client.post("/api/v1/board/sync/vault", 
                headers={"X-Device-ID": f"HW-{board_id}"},
                json={
                    "session_id": session_id,
                    "queued_scans": [
                        {
                            "student_id": student_id,
                            "qr_payload": f"TOKEN-{uuid.uuid4().hex}",
                            "timestamp": int(time.time())
                        }
                    ]
                }
            )
            latency = (time.perf_counter() - start_time) * 1000
            if resp.status_code == 200:
                return latency
            else:
                logger.warning(f"⚠️ Scan failed: {resp.status_code}")
                return None
        except Exception as e:
            logger.error(f"💥 Scan connection error: {e}")
            return None

async def run_load_test():
    logger.info(f"🚀 Starting Load Test: {NUM_BOARDS} boards, {NUM_SCANS_PER_BOARD} scans each.")
    
    # Simulate boards starting up
    board_tasks = [simulate_board_lifecycle(f"BOARD-{i}") for i in range(NUM_BOARDS)]
    await asyncio.gather(*board_tasks)
    
    # Simulate concurrent scans
    session_id = f"SESS-{uuid.uuid4().hex[:8]}"
    scan_tasks = []
    for i in range(NUM_BOARDS):
        for _ in range(NUM_SCANS_PER_BOARD):
            scan_tasks.append(simulate_attendance_scan(session_id, f"BOARD-{i}"))
    
    start_test = time.perf_counter()
    latencies = await asyncio.gather(*scan_tasks)
    total_time = time.perf_counter() - start_test
    
    valid_latencies = [l for l in latencies if l is not None]
    if valid_latencies:
        avg_latency = sum(valid_latencies) / len(valid_latencies)
        p95_latency = sorted(valid_latencies)[int(len(valid_latencies) * 0.95)]
        logger.info(f"📊 --- Results ---")
        logger.info(f"Total Requests: {len(scan_tasks)}")
        logger.info(f"Success Rate: {(len(valid_latencies)/len(scan_tasks))*100:.1f}%")
        logger.info(f"Average Latency: {avg_latency:.2f}ms")
        logger.info(f"P95 Latency: {p95_latency:.2f}ms")
        logger.info(f"Throughput: {len(valid_latencies)/total_time:.2f} req/s")
    else:
        logger.error("❌ No successful requests recorded.")

if __name__ == "__main__":
    asyncio.run(run_load_test())
