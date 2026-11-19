"""Only copied into the short-lived diagnostic preview by probe_hosted_coaching."""
import os
from pathlib import Path
import time

from CoachingServer.http_app import create_application
from CoachingServer.model_configuration import HostedModelConfiguration
from CoachingServer.service import HostedCoachingService
from CoachingServer.structured_logging import configure_application_logging, emit_event
from Tools.CoachingEval.hosted_transport_probe import TimedResponsesClient


configure_application_logging(suppress_werkzeug=False)
configuration = HostedModelConfiguration.load(os.environ["CHESS_TUTOR_COACHING_MODEL_CONFIG"], Path.cwd())
expires_at = float(os.environ["COACHING_DIAGNOSTIC_EXPIRES_AT"])
provider = TimedResponsesClient(api_key=os.environ["OPENAI_API_KEY"],
                                emit=lambda fields: emit_event("diagnostic_transport", **fields))
app = create_application(service=HostedCoachingService(provider=provider, configuration=configuration),
                         access_token=os.environ["CHESS_TUTOR_COACHING_ACCESS_TOKEN"])


@app.before_request
def expire_diagnostic():
    if time.time() >= expires_at:
        return {"error": {"code": "diagnosticExpired"}}, 503
    return None
