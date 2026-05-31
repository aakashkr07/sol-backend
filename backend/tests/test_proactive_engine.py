import unittest

from core.proactive_engine import _is_within_quiet_hours, decide_proactive_outreach, ProactiveStyle

# Mock ProactiveStyle for tests
mock_style = ProactiveStyle(
    minimum_inactivity_hours=18,
    cooldown_bias_hours=0,
    initiation_tone="warm",
    preferred_opening_device="question",
    contextual_anchor_instruction="",
    silence_instruction="",
    emotional_instruction="",
    gentle_instruction="",
    notification_templates={},
    notification_mode="preview",
    double_text_likelihood=0.5,
    callback_trust_floor=0.3,
    presence_trust_floor=0.2,
    early_stage_presence=True,
)


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
            style=mock_style,
        )
        self.assertTrue(decision.should_send)
        self.assertEqual(decision.reason, "contextual_callback")

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
            style=mock_style,
        )
        self.assertFalse(decision.should_send)
        self.assertEqual(decision.blocked_by, "relationship_too_early")

    def test_dynamic_cooldowns_adjusted_by_traits(self):
        from core.proactive_engine import _styled_cooldown_hours, ProactiveStyle
        
        style_high = ProactiveStyle(
            minimum_inactivity_hours=18,
            cooldown_bias_hours=0,
            initiation_tone="warm",
            preferred_opening_device="question",
            contextual_anchor_instruction="",
            silence_instruction="",
            emotional_instruction="",
            gentle_instruction="",
            notification_templates={},
            notification_mode="preview",
            double_text_likelihood=0.5,
            callback_trust_floor=0.3,
            presence_trust_floor=0.2,
            early_stage_presence=True,
            impulsiveness=0.8,
        )
        
        cooldown_high = _styled_cooldown_hours(
            cadence="balanced",
            closeness=0.8,
            trust=0.8,
            style=style_high,
        )
        
        style_low = ProactiveStyle(
            minimum_inactivity_hours=18,
            cooldown_bias_hours=0,
            initiation_tone="warm",
            preferred_opening_device="question",
            contextual_anchor_instruction="",
            silence_instruction="",
            emotional_instruction="",
            gentle_instruction="",
            notification_templates={},
            notification_mode="preview",
            double_text_likelihood=0.5,
            callback_trust_floor=0.3,
            presence_trust_floor=0.2,
            early_stage_presence=True,
            impulsiveness=0.2,
        )
        
        cooldown_low = _styled_cooldown_hours(
            cadence="balanced",
            closeness=0.2,
            trust=0.2,
            style=style_low,
        )
        
        # High closeness and impulsiveness reduce the cooldown hours dramatically.
        self.assertTrue(cooldown_high < cooldown_low)


if __name__ == "__main__":
    unittest.main()
