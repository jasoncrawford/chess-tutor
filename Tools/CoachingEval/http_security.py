"""Shared HTTP credential-boundary helpers for evaluation tooling."""

import urllib.parse
import urllib.request


def origin(url):
    parsed = urllib.parse.urlparse(url)
    scheme = parsed.scheme.lower()
    hostname = (parsed.hostname or "").lower()
    if parsed.port is not None:
        port = parsed.port
    elif scheme == "https":
        port = 443
    elif scheme == "http":
        port = 80
    else:
        port = None
    return scheme, hostname, port


def is_https_origin(url, hostname):
    return origin(url) == ("https", hostname.lower(), 443)


class SameOriginAuthorizationRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Forward Authorization only when a redirect preserves the complete origin."""

    def redirect_request(self, request, file_pointer, code, message, headers, new_url):
        redirected = super().redirect_request(
            request, file_pointer, code, message, headers, new_url
        )
        if redirected is None:
            return None
        authorization = request.headers.get("Authorization")
        redirected.remove_header("Authorization")
        if origin(request.full_url) == origin(new_url) and authorization:
            redirected.add_unredirected_header("Authorization", authorization)
        return redirected
