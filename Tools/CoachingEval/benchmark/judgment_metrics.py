"""Decision-usefulness diagnostics that keep failed and ungraded turns visible."""

import statistics


class JudgmentMetrics:
    @classmethod
    def summarize(cls, records, grades):
        record_ids = [row["cellID"] for row in records]
        grade_ids = [row["cellID"] for row in grades]
        if (len(set(record_ids)) != len(record_ids) or len(set(grade_ids)) != len(grade_ids)
                or not set(grade_ids) <= set(record_ids)):
            raise ValueError("Judgment metrics require unique, bound candidate/grade cells")
        by_id = {row["cellID"]: row for row in grades}
        result = {}
        for identifier in sorted({row["configurationID"] for row in records}):
            rows = [row for row in records if row["configurationID"] == identifier]
            result[identifier] = cls._group(rows, by_id)
            result[identifier]["cases"] = {
                case: cls._group([row for row in rows if row["caseID"] == case], by_id)
                for case in sorted({row["caseID"] for row in rows})
            }
        return result

    @staticmethod
    def _group(rows, grades):
        scores, useful, invalid, ungraded, severe = [], 0, 0, 0, 0
        for row in rows:
            grade = grades.get(row["cellID"], {})
            if row.get("mechanicalValidation", {}).get("valid") is not True:
                invalid += 1
                continue
            score = (grade.get("scores") or {}).get("coachingJudgment")
            if grade.get("disposition") != "judged" or type(score) is not int or not 1 <= score <= 5:
                ungraded += 1
                continue
            scores.append(score)
            has_error = grade.get("flags", {}).get("severeError") is not False
            severe += has_error
            useful += score >= 4 and not has_error
        return dict(attemptCount=len(rows), judgedCount=len(scores), scores=scores,
                    judgedMean=statistics.mean(scores) if scores else None,
                    usefulResponseCount=useful, usefulResponseRate=useful / len(rows) if rows else None,
                    failedOrInvalidCount=invalid, ungradedValidCount=ungraded, severeErrorCount=severe)
