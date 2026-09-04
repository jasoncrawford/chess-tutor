"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");

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

class FakeClassList {
  constructor() { this.values = new Set(); }
  add(value) { this.values.add(value); }
  remove(value) { this.values.delete(value); }
}

class FakeElement {
  constructor(tagName, id) {
    this.tagName = tagName.toUpperCase();
    this.id = id || "";
    this.children = [];
    this.listeners = {};
    this.attributes = {};
    this.dataset = {};
    this.style = {};
    this.classList = new FakeClassList();
    this.textContent = "";
    this.value = "";
    this.checked = false;
    this.disabled = false;
    this.hidden = false;
    this.isContentEditable = false;
  }
  addEventListener(name, listener) { this.listeners[name] = listener; }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this.children = children; }
  setAttribute(name, value) { this.attributes[name] = String(value); }
  get lastElementChild() { return this.children[this.children.length - 1]; }
  focus() { this.focused = true; }
  select() {}
  remove() {}
  matches(selector) {
    if (selector === "[data-score]") return this.dataset.score !== undefined;
    if (selector === "[data-flag]") return this.dataset.flag !== undefined;
    if (selector === 'input[name="preference"]') return this.name === "preference";
    if (selector === "[data-filter]") return this.dataset.filter !== undefined;
    return false;
  }
  closest(selector) { return this.matches(selector) ? this : null; }
}

function reviewCase(id, index) {
  return {
    id,
    index,
    kind: "absolute",
    source: { category: "quiet", stepIndex: index, sideToMove: "white" },
    position: {
      fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1",
      sideToMove: "white",
      status: "ongoing",
      moveHistory: [],
      latestInteraction: { kind: "helpOpened", referencedIDs: [] },
      tentativeMove: null
    },
    brief: {
      verifiedFacts: ["Fixture fact."],
      coachingPurpose: "Fixture purpose.",
      acceptableAlternatives: [],
      successCriteria: ["Fixture success."],
      severeFailureCriteria: []
    },
    technical: { sourceID: "source-" + index },
    candidate: { message: "Fixture coaching.", actions: [], focus: [], expects: "stageMove" },
    proposed: {
      scores: Object.fromEntries(SCORE_IDS.map((scoreID) => [scoreID, 5])),
      flags: Object.fromEntries(FLAG_IDS.map((flagID) => [flagID, false])),
      rationale: ["Fixture rationale."]
    }
  };
}

function model() {
  const sha = "a".repeat(64);
  return {
    reference: {
      sha256: sha,
      reviewStatus: "pending",
      sourceGitSHA: "b".repeat(40),
      sourceCasesSHA256: "c".repeat(64),
      sourceManifestSHA256: "d".repeat(64)
    },
    reviewStorageKey: "chess-tutor:judge-reference-review:" + sha,
    rubric: {
      scores: SCORE_IDS.map((id) => ({ id, label: id, minimum: 1, maximum: 5 })),
      flags: FLAG_IDS.map((id) => ({ id, label: id })),
      preferences: ["responseOne", "responseTwo", "tie"].map((id) => ({ id, label: id }))
    },
    cases: [reviewCase("ref-01", 1), reviewCase("ref-02", 2)]
  };
}

const elementIDs = [
  "agree-decision", "app-error", "approve-remaining", "case-content", "case-filters",
  "case-category", "case-kind", "case-list", "case-position", "case-review", "case-stage", "case-title",
  "change-decision", "chess-board", "copy-status", "copy-summary", "decision-stamp",
  "latest-interaction", "move-history", "next-case", "position-summary", "previous-case",
  "progress-bar", "progress-copy", "progress-number", "progress-ring", "reference-sha",
  "reference-status", "review-app", "review-form", "review-notes", "source-cases-sha",
  "source-git-sha", "source-manifest-sha", "technical-content", "tentative-move",
  "brief-content"
];
const elements = Object.fromEntries(elementIDs.map((id) => [id, new FakeElement("div", id)]));
elements["review-notes"].tagName = "TEXTAREA";
const filterButtons = ["all", "unreviewed", "needsChange"].map((filter) => {
  const button = new FakeElement("button");
  button.dataset.filter = filter;
  return button;
});
const decisionButtons = [
  Object.assign(elements["agree-decision"], { dataset: { decision: "agree" } }),
  Object.assign(elements["change-decision"], { dataset: { decision: "needsChange" } })
];
let domContentLoaded;
const document = {
  body: new FakeElement("body"),
  createElement(tagName) { return new FakeElement(tagName); },
  createTextNode(text) { return Object.assign(new FakeElement("#text"), { textContent: text }); },
  getElementById(id) { return elements[id]; },
  querySelectorAll(selector) {
    if (selector === "[data-filter]") return filterButtons;
    if (selector === "[data-decision]") return decisionButtons;
    return [];
  },
  addEventListener(name, listener) {
    if (name === "DOMContentLoaded") domContentLoaded = listener;
    else this.listeners[name] = listener;
  },
  listeners: {},
  execCommand() { return true; }
};
const stored = new Map();
let copiedSummary = "";

global.document = document;
global.localStorage = {
  getItem(key) { return stored.has(key) ? stored.get(key) : null; },
  setItem(key, value) { stored.set(key, value); }
};
global.navigator = { clipboard: { async writeText(value) { copiedSummary = value; } } };
global.fetch = async function () { return { ok: true, async json() { return model(); } }; };
global.window = {
  JudgeReviewCore: require(path.join(__dirname, "../benchmark/review_core.js"))
};

require(path.join(__dirname, "../benchmark/review_app.js"));

(async function run() {
  await domContentLoaded();
  elements["case-filters"].listeners.click({ target: filterButtons[1] });

  const score = new FakeElement("select");
  score.dataset.score = "chessCorrectness";
  score.value = "4";
  elements["case-content"].listeners.change({ target: score });
  assert.equal(elements["case-position"].textContent, "Case 1 of 2");
  assert.equal(elements["next-case"].disabled, false);

  const flag = new FakeElement("input");
  flag.dataset.flag = "severeError";
  flag.checked = true;
  elements["case-content"].listeners.change({ target: flag });
  elements["review-notes"].listeners.input({ target: { value: "Finish checking this case." } });
  assert.equal(elements["case-position"].textContent, "Case 1 of 2");
  assert.equal(elements["progress-copy"].textContent, "1 of 2 reviewed · 1 need change");
  assert.equal(elements["case-list"].children.length, 1);
  assert.equal(elements["case-list"].children[0].children[0].dataset.caseID, "ref-02");

  await elements["copy-summary"].listeners.click();
  assert.match(copiedSummary, /case=ref-01 decision=needsChange/);
  assert.match(copiedSummary, /scores=\[chessCorrectness:5->4\]/);
  assert.match(copiedSummary, /flags=\[severeError:false->true\]/);
  assert.match(copiedSummary, /note="Finish checking this case\."/);

  elements["next-case"].listeners.click();
  assert.equal(elements["case-position"].textContent, "Case 2 of 2");
  assert.equal(elements["case-list"].children.length, 1);
  assert.equal(elements["case-list"].children[0].children[0].dataset.caseID, "ref-02");
  process.stdout.write("1 review controller integration test passed\n");
}()).catch((error) => {
  process.stderr.write(error.stack + "\n");
  process.exitCode = 1;
});
