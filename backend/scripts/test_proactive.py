import os
import sys
import asyncio
import logging

# Insert parent directory to allow direct imports of backend modules
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from memory.store import db
from core.proactive_engine import maybe_generate_for_user

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("test_proactive")

async def run_immediate_check():
    logger.info("Connecting SQLite database...")
    db.connect()
    
    logger.info("Fetching registered users...")
    users = db.conn.execute("SELECT id FROM users").fetchall()
    if not users:
        logger.warning("No users found in database! Make sure you have completed onboarding.")
        return
    
    # Let's use the first user in the database for testing
    user_id = users[0]["id"]
    logger.info(f"Setting up test environment for user: {user_id}...")

    # 1. Temporarily bump relationship scores to bypass the "relationship_too_early" gate
    db.conn.execute(
        """
        UPDATE relationship_pairs 
        SET closeness_score = 0.5, trust_score = 0.5 
        WHERE user_id = ? AND companion_id = 'nova'
        """,
        (user_id,)
    )

    # 2. Register a dummy device token so the proactive engine attempts an FCM dispatch
    db.conn.execute(
        """
        INSERT INTO device_registrations (id, user_id, platform, push_token, is_enabled)
        VALUES ('test_device_id', ?, 'android', 'dummy_testing_token_fcm', 1)
        ON CONFLICT(user_id, push_token) DO UPDATE SET is_enabled = 1
        """,
        (user_id,)
    )
    logger.info("Database prepared: closeness/trust set to 0.5, dummy token registered.")

    # 3. Trigger the FORCED proactive generation
    logger.info(f"Triggering FORCED proactive check for user: {user_id}...")
    events = await maybe_generate_for_user(user_id, limit=1, force=True)
    
    if events:
        logger.info(f"SUCCESS: Generated and dispatched {len(events)} event(s) for user {user_id}!")
        for i, ev in enumerate(events):
            logger.info(f"Event {i+1} Details: {ev}")
    else:
        logger.warning(
            f"No proactive events generated for user {user_id}. "
            "Please check backend logs above for any errors."
        )

if __name__ == "__main__":
    asyncio.run(run_immediate_check())