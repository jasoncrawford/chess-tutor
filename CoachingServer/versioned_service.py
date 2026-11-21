"""Keep the installed client protocol stable while new clients opt into visuals."""

from collections.abc import Mapping

from CoachingServer.service import HostedCoachingServiceError


class VersionedHostedCoachingService:
    def __init__(self, *, legacy, visual):
        self._services = {"hosted-coaching-request.v3": legacy,
                          "hosted-coaching-request.v4": visual}

    def complete(self, request, *, trace_id="direct"):
        version = request.get("schemaVersion") if isinstance(request, Mapping) else None
        if not isinstance(version, str) or version not in self._services:
            raise HostedCoachingServiceError("invalidRequest")
        return self._services[version].complete(request, trace_id=trace_id)
