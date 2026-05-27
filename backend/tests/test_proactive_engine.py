import unittest

from core.proactive_engine import _is_within_quiet_hours, decide_proactive_outreach


class ProactiveEngineTests(unittest.TestCase):
    def test_quiet_hours_wraps_across_midnight(self):
        self.assertTrue(_is_within_quiet_hours(23, 22, 8))
        self.assertTrue(_is_within_quiet_hours(3, 22, 8))
        self.assertFalse(_is_within_quiet_hours(14, 22, 8))

    def test_emotional_callback_requires_trust_and_callbacks(self):
        decision = decide_proactive_outreach(
            proactive_enabled=True,
            pair_enabled=True,
            global_quiet_block=False,
            has_pending_event=False,
            inactivity_hours=26,
            minimum_inactivity_hours=18,
            cooldown_active=False,
            relationship_stage="settled",
            closeness=0.51,
            trust=0.44,
            emotional_callback_ready=True,
            callbacks_enabled=True,
            cadence="balanced",
        )
        self.assertTrue(decision.should_send)
        self.assertEqual(decision.reason, "emotional_callback")

    def test_new_low_trust_relationship_does_not_send(self):
        decision = decide_proactive_outreach(
            proactive_enabled=True,
            pair_enabled=True,
            global_quiet_block=False,
            has_pending_event=False,
            inactivity_hours=30,
            minimum_inactivity_hours=18,
            cooldown_active=False,
            relationship_stage="new",
            closeness=0.2,
            trust=0.18,
            emotional_callback_ready=False,
            callbacks_enabled=True,
            cadence="gentle",
        )
        self.assertFalse(decision.should_send)
        self.assertEqual(decision.blocked_by, "relationship_too_early")


if __name__ == "__main__":
    unittest.main()
