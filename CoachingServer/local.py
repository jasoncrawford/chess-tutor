"""Run the hosted coaching Flask app locally."""

import argparse
import logging
from CoachingServer.http_app import create_environment_application


def main(argv=None):
    parser = argparse.ArgumentParser(description="Run ChessTutor hosted coaching")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    arguments = parser.parse_args(argv)
    if not 1 <= arguments.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )
    application = create_environment_application()
    application.run(
        host=arguments.host,
        port=arguments.port,
        debug=False,
        use_reloader=False,
    )


if __name__ == "__main__":
    main()
