"""Shared coaching experience diagnostics for comparisons and regression runs."""

import math
import re
import statistics


class ExperienceMetrics:
    @staticmethod
    def summarize(records, conversation_reuse):
        """Latency thresholds are diagnostic UX targets, not chess grades.

        Include failed/invalid requests in timing. This counts conventional
        keep/play confirmation questions; it is a repetition indicator, not a
        semantic judge of whether a response was useful. Exclamation counts
        describe visible punctuation, not a standalone tone or quality grade.
        """
        result = {}
        for identifier, reuse in conversation_reuse.items():
            rows = [r for r in records if r["configurationID"] == identifier]
            timings = {"fresh": [], "followUp": []}
            endings, confirmation_count = [], 0
            failed = 0
            blocked = 0
            valid_messages = 0
            exclamatory_messages = 0
            exclamation_marks = 0
            for row in rows:
                if row.get("generationStatus") == "blockedByPriorTurn":
                    blocked += 1
                    continue
                bucket = "followUp" if reuse and row["stepIndex"] > 1 else "fresh"
                latency = row.get("latencyMilliseconds")
                if isinstance(latency, (int, float)) and math.isfinite(latency) and latency >= 0:
                    timings[bucket].append(latency)
                valid = row.get("mechanicalValidation", {}).get("valid") is True
                failed += not valid
                turn = row.get("parsedTurn") or {}
                if valid:
                    valid_messages += 1
                    marks = turn.get("message", "").count("!")
                    exclamatory_messages += marks > 0
                    exclamation_marks += marks
                if valid and turn.get("expects") == "chooseWhetherToPlay":
                    confirmation_count += 1
                    message = turn.get("message", "").strip().lower()
                    closing = re.split(r"[.!]", message)[-1].strip()
                    if closing.endswith("?") and re.search(r"\b(keep|play|try another)\b", closing):
                        endings.append(closing)
            stats = dict(failedOrInvalidCount=failed, blockedCount=blocked,
                         validMessageCount=valid_messages, exclamatoryMessageCount=exclamatory_messages,
                         exclamationMarkCount=exclamation_marks, confirmationTurnCount=confirmation_count,
                         confirmationQuestionCount=len(endings),
                         mostRepeatedConfirmationEndingCount=max((endings.count(s) for s in set(endings)), default=0))
            for bucket, values in timings.items():
                target = 3000 if bucket == "followUp" else 5000
                stats[bucket] = dict(count=len(values), targetMilliseconds=target,
                                    overTargetCount=sum(v > target for v in values),
                                    medianMilliseconds=statistics.median(values) if values else None,
                                    p90Milliseconds=sorted(values)[math.ceil(len(values) * .9) - 1] if values else None,
                                    maximumMilliseconds=max(values) if values else None)
            result[identifier] = stats
        return result


