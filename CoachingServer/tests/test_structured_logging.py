import json
import logging
import math
import unittest
from unittest import mock

from CoachingServer.structured_logging import (
    configure_application_logging,
    emit_event,
)


class StructuredCoachingLoggingTests(unittest.TestCase):
    def test_emits_one_versioned_json_object_with_common_fields_first(self):
        with mock.patch(
            "CoachingServer.structured_logging._utc_timestamp",
            return_value="2026-09-01T19:05:39.123Z",
        ), self.assertLogs("ChessTutor.CoachingServer", level="INFO") as captured:
            emit_event(
                "provider_request_started",
                trace_id="trace-1",
                game_id="11111111-1111-4111-8111-111111111111",
                episode_id="22222222-2222-4222-8222-222222222222",
                model="gpt-5.6-sol",
            )

        self.assertEqual(1, len(captured.records))
        message = captured.records[0].getMessage()
        self.assertNotIn("\n", message)
        value = json.loads(message)
        self.assertEqual(
            [
                "schema_version",
                "timestamp",
                "level",
                "event",
                "trace_id",
                "game_id",
                "episode_id",
                "model",
            ],
            list(value.keys()),
        )
        self.assertEqual(
            {
                "schema_version": "coaching-log.v1",
                "timestamp": "2026-09-01T19:05:39.123Z",
                "level": "info",
                "event": "provider_request_started",
                "trace_id": "trace-1",
                "game_id": "11111111-1111-4111-8111-111111111111",
                "episode_id": "22222222-2222-4222-8222-222222222222",
                "model": "gpt-5.6-sol",
            },
            value,
        )

    def test_escapes_embedded_newlines_without_splitting_the_record(self):
        with self.assertLogs("ChessTutor.CoachingServer", level="INFO") as captured:
            emit_event("coaching_turn", response={"message": "first\nsecond"})

        message = captured.records[0].getMessage()
        self.assertNotIn("\n", message)
        self.assertEqual("first\nsecond", json.loads(message)["response"]["message"])

    def test_rejects_reserved_fields_and_nonfinite_values(self):
        with self.assertRaisesRegex(ValueError, "reserved log field"):
            emit_event("test", schema_version="wrong")
        with self.assertRaises(ValueError):
            emit_event("test", latency_ms=math.nan)

    def test_configures_message_only_output_and_can_suppress_werkzeug(self):
        werkzeug_logger = logging.getLogger("werkzeug")
        previous_disabled = werkzeug_logger.disabled
        self.addCleanup(setattr, werkzeug_logger, "disabled", previous_disabled)

        with mock.patch("CoachingServer.structured_logging.logging.basicConfig") as basic:
            configure_application_logging(suppress_werkzeug=True)

        basic.assert_called_once_with(level=logging.INFO, format="%(message)s")
        self.assertEqual(
            logging.INFO,
            logging.getLogger("ChessTutor.CoachingServer").level,
        )
        self.assertTrue(werkzeug_logger.disabled)


if __name__ == "__main__":
    unittest.main()
