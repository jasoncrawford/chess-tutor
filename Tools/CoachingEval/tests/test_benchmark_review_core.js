"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");
const core = require(path.join(__dirname, "../benchmark/review_core.js"));

const SCORE_IDS = [
  "chessCorrectness",
  "coachingJudgment",
  "latestActionResponsiveness",
  "discoveryAndIndependence",
  "coherenceAndAnswerability",
  "childClarity"
];
const FLAG_IDS = [
  "factualOrIllegalAdvice",
  "wrongUrgentPriority",
  "obsoleteStage",
  "mixedStages",
  "answerRevealingGuidance",
  "unavailableUIOrDeadEnd",
  "severeError"
];

function absoluteCase(id, index) {
  return {
    id,
    index,
    kind: "absolute",
    proposed: {
      scores: Object.fromEntries(SCORE_IDS.map((scoreID) => [scoreID, 5])),
      flags: Object.fromEntries(FLAG_IDS.map((flagID) => [flagID, false])),
      rationale: ["Fixture rationale."]
    }
  };
}

function model() {
  return {
    reference: { sha256: "a".repeat(64) },
    reviewStorageKey: "chess-tutor:judge-reference-review:" + "a".repeat(64),
    rubric: {
      scores: SCORE_IDS.map((id) => ({ id, minimum: 1, maximum: 5 })),
      flags: FLAG_IDS.map((id) => ({ id })),
      preferences: ["responseOne", "responseTwo", "tie"].map((id) => ({ id }))
    },
    cases: [
      absoluteCase("ref-01", 1),
      absoluteCase("ref-02", 2),
      {
        id: "pair-01",
        index: 3,
        kind: "pairwise",
        proposed: { preference: "responseOne", rationale: ["Fixture rationale."] }
      }
    ]
  };
}

const tests = [];
function test(name, body) { tests.push({ name, body }); }

test("sanitizes poisoned storage against the exact current model", () => {
  const current = model();
  const poisoned = {
    schemaVersion: "judge-reference-browser-review.v2",
    referenceSHA256: current.reference.sha256,
    reviews: {
      "ref-01": {
        kind: "absolute",
        decision: "agree",
        notes: "bounded",
        scores: { chessCorrectness: 4, injectedDimension: 1 },
        flags: { severeError: true, injectedFlag: false },
        injectedRecordField: "discard"
      },
      "ref-02": { kind: "pairwise", decision: "agree", notes: "wrong kind" },
      "pair-01": { kind: "pairwise", decision: "agree", notes: "", preference: "not-valid" },
      "unknown-case": { kind: "absolute", decision: "agree", notes: "" }
    }
  };

  const reviews = core.sanitizeStoredReview(current, poisoned);

  assert.deepEqual(Object.keys(reviews), ["ref-01", "ref-02", "pair-01"]);
  assert.deepEqual(reviews["ref-01"], {
    kind: "absolute",
    decision: "needsChange",
    notes: "bounded",
    scores: { chessCorrectness: 4 },
    flags: { severeError: true }
  });
  assert.deepEqual(reviews["ref-02"], core.emptyReview(current.cases[1]));
  assert.deepEqual(reviews["pair-01"], core.emptyReview(current.cases[2]));
});

test("invalid wrappers and records reset safely to unreviewed", () => {
  const current = model();
  const wrongSHA = core.sanitizeStoredReview(current, {
    schemaVersion: "judge-reference-browser-review.v2",
    referenceSHA256: "b".repeat(64),
    reviews: { "ref-01": { kind: "absolute", decision: "agree", notes: "" } }
  });
  const invalidRecords = core.sanitizeStoredReview(current, {
    schemaVersion: "judge-reference-browser-review.v2",
    referenceSHA256: current.reference.sha256,
    reviews: {
      "ref-01": { kind: "absolute", decision: "poison", notes: "" },
      "ref-02": { kind: "absolute", decision: "agree", notes: "x".repeat(2001) },
      "pair-01": { kind: "pairwise", decision: "agree", notes: 7 }
    }
  });

  assert.equal(core.progress(current, wrongSHA).reviewed, 0);
  assert.equal(core.progress(current, invalidRecords).reviewed, 0);
});

test("score and flag changes persist and automatically need change", () => {
  const current = model();
  let reviews = core.sanitizeStoredReview(current, null);
  reviews = core.applyScore(current, reviews, "ref-01", "chessCorrectness", 4);
  reviews = core.applyFlag(current, reviews, "ref-01", "severeError", true);
  const payload = core.storagePayload(current, reviews);
  const reloaded = core.sanitizeStoredReview(current, JSON.parse(JSON.stringify(payload)));

  assert.equal(reloaded["ref-01"].decision, "needsChange");
  assert.deepEqual(reloaded["ref-01"].scores, { chessCorrectness: 4 });
  assert.deepEqual(reloaded["ref-01"].flags, { severeError: true });
});

test("pairwise preference changes persist and automatically need change", () => {
  const current = model();
  let reviews = core.sanitizeStoredReview(current, null);
  reviews = core.applyPreference(current, reviews, "pair-01", "responseTwo");
  const reloaded = core.sanitizeStoredReview(current, core.storagePayload(current, reviews));

  assert.equal(reloaded["pair-01"].decision, "needsChange");
  assert.equal(reloaded["pair-01"].preference, "responseTwo");
});

test("agree restores every proposed judgment before recording agreement", () => {
  const current = model();
  let reviews = core.sanitizeStoredReview(current, null);
  reviews = core.applyScore(current, reviews, "ref-01", "childClarity", 2);
  reviews = core.applyFlag(current, reviews, "ref-01", "mixedStages", true);
  reviews = core.setNotes(current, reviews, "ref-01", "Keep this audit note.");
  reviews = core.setDecision(current, reviews, "ref-01", "agree");

  assert.deepEqual(reviews["ref-01"], {
    kind: "absolute",
    decision: "agree",
    notes: "Keep this audit note."
  });
});

test("bulk approval skips every edited case and approves only pristine unreviewed cases", () => {
  const current = model();
  let reviews = core.sanitizeStoredReview(current, null);
  reviews = core.applyScore(current, reviews, "ref-01", "chessCorrectness", 4);
  reviews = core.setNotes(current, reviews, "pair-01", "Needs a deliberate decision.");
  const result = core.approveRemaining(current, reviews);

  assert.equal(result.approved, 1);
  assert.deepEqual(result.skippedEdited, ["ref-01", "pair-01"]);
  assert.equal(result.reviews["ref-01"].decision, "needsChange");
  assert.equal(result.reviews["ref-02"].decision, "agree");
  assert.equal(result.reviews["pair-01"].decision, "unreviewed");
});

test("summary is deterministic complete escaped and never agrees with changes", () => {
  const current = model();
  const unsafe = {
    "ref-01": {
      kind: "absolute",
      decision: "agree",
      notes: "first line\n\"quoted\"\tend",
      scores: { chessCorrectness: 4 },
      flags: { severeError: true }
    },
    "pair-01": {
      kind: "pairwise",
      decision: "unreviewed",
      notes: "",
      preference: "responseTwo"
    }
  };

  const first = core.formatSummary(current, unsafe);
  const second = core.formatSummary(current, unsafe);

  assert.equal(first, second);
  assert.match(first, new RegExp("referenceSHA256=" + "a".repeat(64)));
  assert.match(first, /reviewed=2\/3/);
  assert.match(first, /case=ref-01 decision=needsChange scores=\[chessCorrectness:5->4\] flags=\[severeError:false->true\] note="first line \\\"quoted\\\" end"/);
  assert.match(first, /case=ref-02 decision=unreviewed/);
  assert.match(first, /case=pair-01 decision=needsChange preference=responseOne->responseTwo/);
  assert.doesNotMatch(first, /decision=agree[^\n]*(scores|flags|preference)=/);
});

test("filters navigation and shortcuts share safe deterministic behavior", () => {
  const current = model();
  let reviews = core.sanitizeStoredReview(current, null);
  reviews = core.setDecision(current, reviews, "ref-01", "agree");
  reviews = core.setDecision(current, reviews, "ref-02", "needsChange");

  assert.deepEqual(core.visibleCases(current, reviews, "unreviewed").map((item) => item.id), ["pair-01"]);
  assert.deepEqual(core.visibleCases(current, reviews, "needsChange").map((item) => item.id), ["ref-02"]);
  assert.equal(core.adjacentCaseID(current.cases, "ref-01", 1), "ref-02");
  assert.equal(core.adjacentCaseID(current.cases, "ref-01", -1), null);
  assert.equal(core.shortcutAction({ key: "ArrowRight", targetTagName: "BODY" }), "next");
  assert.equal(core.shortcutAction({ key: "a", targetTagName: "DIV" }), "agree");
  assert.equal(core.shortcutAction({ key: "c", targetTagName: "DIV" }), "needsChange");
  assert.equal(core.shortcutAction({ key: "a", targetTagName: "TEXTAREA" }), null);
  assert.equal(core.shortcutAction({ key: "ArrowLeft", targetTagName: "INPUT" }), null);
  assert.equal(core.shortcutAction({ key: "c", targetTagName: "DIV", metaKey: true }), null);
  assert.equal(core.shortcutAction({ key: "c", targetTagName: "DIV", targetIsContentEditable: true }), null);
});

test("FEN parsing maps a black-to-move position onto named board squares", () => {
  const parsed = core.parseFen("8/8/8/3k4/8/8/4P3/4K3 b - - 0 1");

  assert.equal(parsed.sideToMove, "black");
  assert.equal(parsed.squares.length, 64);
  assert.deepEqual(parsed.squares.find((square) => square.square === "d5"), {
    square: "d5", file: "d", rank: 5, pieceCode: "k", piece: "♚", pieceName: "black king"
  });
  assert.equal(parsed.squares.find((square) => square.square === "e2").pieceName, "white pawn");
  assert.equal(parsed.squares.find((square) => square.square === "a8").piece, null);
});

for (const item of tests) {
  try {
    item.body();
    process.stdout.write("ok - " + item.name + "\n");
  } catch (error) {
    process.stderr.write("not ok - " + item.name + "\n");
    throw error;
  }
}
process.stdout.write(tests.length + " review core tests passed\n");
