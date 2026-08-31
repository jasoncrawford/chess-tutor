"""Vercel Python Function entrypoint."""

from CoachingServer.http_app import create_environment_application


app = create_environment_application()
