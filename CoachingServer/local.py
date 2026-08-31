"""Run the hosted coaching WSGI app locally."""

import argparse
from wsgiref.simple_server import make_server

from CoachingServer.http_app import create_environment_application


def main(argv=None):
    parser = argparse.ArgumentParser(description="Run ChessTutor hosted coaching")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    arguments = parser.parse_args(argv)
    if not 1 <= arguments.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    application = create_environment_application()
    with make_server(arguments.host, arguments.port, application) as server:
        print(f"ChessTutor coaching server listening on http://{arguments.host}:{arguments.port}")
        server.serve_forever()


if __name__ == "__main__":
    main()
