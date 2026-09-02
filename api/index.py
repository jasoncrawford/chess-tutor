"""Vercel Python Function entrypoint."""

from CoachingServer.http_app import create_environment_application
from CoachingServer.structured_logging import configure_application_logging


configure_application_logging(suppress_werkzeug=False)
app = create_environment_application()
