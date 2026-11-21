"""Mechanical visual diagnostics; no semantic quality claims or altered artifacts."""
import re


def message_text(turn):
    value = turn.get("message", "")
    return "".join(run["text"] for run in value) if isinstance(value, list) else value


class VisualMetrics:
    @staticmethod
    def summarize(records):
        result = {}
        for row in records:
            stats = result.setdefault(row["configurationID"], dict(visualResponseCount=0,
                mechanicallyInvalidCount=0, visualCapabilityUnavailableCount=0,
                linkedReferenceCount=0, arrowCount=0, coordinateMentionCount=0))
            if not row.get("mechanicalValidation", {}).get("valid"):
                stats["mechanicallyInvalidCount"] += 1
                continue
            turn = row.get("parsedTurn") or {}
            stats["coordinateMentionCount"] += len(re.findall(r"\b[a-h][1-8]\b", message_text(turn)))
            if not isinstance(turn.get("message"), list):
                stats["visualCapabilityUnavailableCount"] += 1
                continue
            stats["visualResponseCount"] += 1
            stats["linkedReferenceCount"] += sum(run["type"] != "text" for run in turn["message"])
            stats["arrowCount"] += len(turn["visuals"])
        return result
