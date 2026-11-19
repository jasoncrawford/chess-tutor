import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading
import time
import unittest

from Tools.CoachingEval.hosted_transport_probe import TimedResponsesClient
from Tools.CoachingEval.tests.test_openai_responses import completed_response, complete


class HostedTransportProbeTests(unittest.TestCase):
    def test_distinguishes_connection_request_headers_and_body_without_private_content(self):
        events = []
        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                self.rfile.read(int(self.headers["Content-Length"]))
                body = json.dumps(completed_response()).encode()
                time.sleep(0.04)
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("openai-processing-ms", "39.5")
                self.send_header("X-Private", "PRIVATE HEADER")
                self.end_headers()
                time.sleep(0.04)
                self.wfile.write(body)
            def log_message(self, *args):
                pass
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            client = TimedResponsesClient(f"http://127.0.0.1:{server.server_port}", emit=events.append)
            response = complete(client)
            self.assertEqual(response["usage"]["output_tokens"], 79)
            self.assertEqual([event["stage"] for event in events],
                             ["connected", "request_sent", "headers", "complete"])
            self.assertEqual(events[2]["provider_processing_ms"], 39.5)
            self.assertGreater(events[2]["elapsed_ms"] - events[1]["elapsed_ms"], 20)
            self.assertGreater(events[3]["elapsed_ms"] - events[2]["elapsed_ms"], 20)
            self.assertEqual(len({event["client_request_id"] for event in events}), 1)
            self.assertNotIn("PRIVATE", json.dumps(events))
            self.assertNotIn("output_text", json.dumps(events))
        finally:
            server.shutdown()
            thread.join()
            server.server_close()
