"""Decision-usefulness diagnostics that keep failed and ungraded turns visible."""

import statistics


class JudgmentMetrics:
    @classmethod
    def summarize(cls, records, grades, *, expected_cells=None, unknown_cells=()):
        record_ids = [row["cellID"] for row in records]
        grade_ids = [row["cellID"] for row in grades]
        if (len(set(record_ids)) != len(record_ids) or len(set(grade_ids)) != len(grade_ids)
                or not set(grade_ids) <= set(record_ids)):
            raise ValueError("Judgment metrics require unique, bound candidate/grade cells")
        by_id = {row["cellID"]: row for row in grades}
        planned = records if expected_cells is None else expected_cells
        planned_ids = [row["cellID"] for row in planned]
        if (len(set(planned_ids)) != len(planned_ids) or not set(record_ids) <= set(planned_ids)
                or not set(unknown_cells) <= set(planned_ids)):
            raise ValueError("Judgment metrics require a unique, bound planned matrix")
        actual = {row["cellID"]: row for row in records}
        rows = [dict(cell, **{"_outcome": "unknown" if cell["cellID"] in unknown_cells else "notAttempted"})
                if cell["cellID"] not in actual else actual[cell["cellID"]] for cell in planned]
        result = {}
        for identifier in sorted({row["configurationID"] for row in rows}):
            selected = [row for row in rows if row["configurationID"] == identifier]
            result[identifier] = cls._group(selected, by_id)
            result[identifier]["cases"] = {
                case: cls._group([row for row in selected if row["caseID"] == case], by_id)
                for case in sorted({row["caseID"] for row in selected})
            }
        return result

    @staticmethod
    def _group(rows, grades):
        scores, useful, invalid, ungraded, severe = [], 0, 0, 0, 0
        unknown, unattempted = 0, 0
        for row in rows:
            if row.get("_outcome") == "unknown":
                unknown += 1
                continue
            if row.get("_outcome") == "notAttempted":
                unattempted += 1
                continue
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
        return dict(plannedCount=len(rows), attemptCount=len(rows) - unattempted,
                    unknownOutcomeCount=unknown, notAttemptedCount=unattempted,
                    complete=not (unknown or unattempted or ungraded),
                    judgedCount=len(scores), scores=scores,
                    judgedMean=statistics.mean(scores) if scores else None,
                    usefulResponseCount=useful, usefulResponseRate=useful / len(rows) if rows else None,
                    failedOrInvalidCount=invalid, ungradedValidCount=ungraded, severeErrorCount=severe)
