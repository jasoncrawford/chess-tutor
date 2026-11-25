"""Keep the installed client protocol stable while new clients opt into visuals."""

from collections.abc import Mapping
from dataclasses import replace

from CoachingServer.service import HostedCoachingServiceError
from CoachingServer.provider_envelope import validate_continuation_id


class VersionedHostedCoachingService:
    def __init__(self, *, legacy, visual):
        self._services = {"hosted-coaching-request.v3": legacy,
                          "hosted-coaching-request.v4": visual}

    def complete(self, request, *, trace_id="direct"):
        version = request.get("schemaVersion") if isinstance(request, Mapping) else None
        if not isinstance(version, str) or version not in self._services:
            raise HostedCoachingServiceError("invalidRequest")
        previous = request.get("previousResponseID")
        visual = version == "hosted-coaching-request.v4"
        if previous is not None:
            try:
                tagged = isinstance(previous, str) and previous.startswith("resp_v4_")
                if tagged:
                    validate_continuation_id("resp_" + previous[len("resp_v4_"):])
                else:
                    validate_continuation_id(previous)
            except ValueError as error:
                raise HostedCoachingServiceError("invalidRequest") from error
            request = dict(request)
            request["previousResponseID"] = (
                "resp_" + previous[len("resp_v4_"):] if visual and tagged
                else previous if not visual and not tagged else None
            )
        completion = self._services[version].complete(request, trace_id=trace_id)
        if visual:
            # A protocol-scoped opaque handle; the provider sees only its own ID.
            response = dict(completion.response)
            response["continuationID"] = "resp_v4_" + response["continuationID"][len("resp_"):]
            completion = replace(completion, response=response)
        return completion
