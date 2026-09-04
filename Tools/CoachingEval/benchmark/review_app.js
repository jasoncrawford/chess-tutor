(function () {
  "use strict";

  const core = window.JudgeReviewCore;
  const state = { model: null, reviews: {}, filter: "all", currentID: null };

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function humanize(value) {
    if (!value) return "None";
    return String(value)
      .replace(/([a-z])([A-Z])/g, "$1 $2")
      .replace(/^./, function (letter) { return letter.toUpperCase(); });
  }

  function reviewFor(caseID) {
    return state.reviews[caseID];
  }

  function saveReviews() {
    try {
      localStorage.setItem(
        state.model.reviewStorageKey,
        JSON.stringify(core.storagePayload(state.model, state.reviews))
      );
    } catch (_error) {
      announce("Review changed, but browser storage is unavailable.");
    }
  }

  function loadReviews() {
    try {
      const saved = JSON.parse(localStorage.getItem(state.model.reviewStorageKey) || "null");
      state.reviews = core.sanitizeStoredReview(state.model, saved);
    } catch (_error) {
      state.reviews = core.sanitizeStoredReview(state.model, null);
      announce("A saved review could not be read. Starting with a clean review.");
    }
  }

  function currentCase() {
    return state.model.cases.find(function (item) { return item.id === state.currentID; });
  }

  function visibleCases() {
    return core.visibleCases(state.model, state.reviews, state.filter);
  }

  function setCurrent(caseID, focusReview) {
    state.currentID = caseID;
    const stage = document.getElementById("case-stage");
    stage.classList.remove("changing");
    void stage.offsetWidth;
    stage.classList.add("changing");
    render();
    if (focusReview) document.getElementById("case-review").focus();
  }

  function render(options) {
    const filtered = visibleCases();
    state.currentID = core.resolveCurrentCaseID(
      state.model.cases,
      filtered,
      state.currentID,
      Boolean(options && options.retainCurrent)
    );
    renderHeader();
    renderProgress();
    renderLedger(filtered);
    if (state.currentID) {
      document.getElementById("case-stage").hidden = false;
      renderCase(currentCase(), filtered);
    } else {
      document.getElementById("case-stage").hidden = true;
      document.getElementById("case-position").textContent = "No cases in this filter";
    }
  }

  function renderHeader() {
    const reference = state.model.reference;
    document.getElementById("reference-status").textContent =
      reference.reviewStatus === "pending" ? "Human provenance pending" : humanize(reference.reviewStatus);
    document.getElementById("reference-sha").textContent = reference.sha256;
    document.getElementById("source-git-sha").textContent = reference.sourceGitSHA;
    document.getElementById("source-cases-sha").textContent = reference.sourceCasesSHA256;
    document.getElementById("source-manifest-sha").textContent = reference.sourceManifestSHA256;
  }

  function renderProgress() {
    const counts = core.progress(state.model, state.reviews);
    const reviewed = counts.reviewed;
    const needsChange = counts.needsChange;
    const total = counts.total;
    const percent = total ? Math.round((reviewed / total) * 100) : 0;
    document.getElementById("progress-copy").textContent = reviewed + " of " + total + " reviewed" +
      (needsChange ? " · " + needsChange + " need change" : "");
    document.getElementById("progress-number").textContent = reviewed;
    document.getElementById("progress-ring").setAttribute("aria-label", percent + "% reviewed");
    document.getElementById("progress-bar").style.width = percent + "%";
  }

  function renderLedger(cases) {
    const list = document.getElementById("case-list");
    list.replaceChildren();
    cases.forEach(function (item) {
      const review = reviewFor(item.id);
      const entry = element("li");
      const button = element("button");
      button.type = "button";
      button.dataset.caseID = item.id;
      button.setAttribute("aria-current", String(item.id === state.currentID));
      button.append(
        element("span", "case-number", String(item.index).padStart(2, "0")),
        element("span", "case-label", item.kind === "absolute" ? "Score " + humanize(item.source.category) : "Compare " + humanize(item.source.category)),
        element("span", "case-state " + review.decision)
      );
      button.lastElementChild.setAttribute("aria-label", humanize(review.decision));
      button.addEventListener("click", function () { setCurrent(item.id, true); });
      entry.append(button);
      list.append(entry);
    });
  }

  function renderCase(item, filtered) {
    const review = reviewFor(item.id);
    const navigation = core.navigationTargets(state.model.cases, filtered, item.id);
    const allIndex = state.model.cases.findIndex(function (value) { return value.id === item.id; });
    document.getElementById("case-position").textContent = "Case " + (allIndex + 1) + " of " + state.model.cases.length;
    document.getElementById("previous-case").disabled = navigation.previous === null;
    document.getElementById("next-case").disabled = navigation.next === null;
    document.getElementById("case-kind").textContent = item.kind === "absolute" ? "Score one response" : "Compare two responses";
    document.getElementById("case-category").textContent = humanize(item.source.category) + " position · step " + item.source.stepIndex;
    document.getElementById("case-title").textContent = item.kind === "absolute" ? "Is this judgment right?" : "Which coaching response is better?";
    const stamp = document.getElementById("decision-stamp");
    stamp.className = "decision-stamp " + review.decision;
    stamp.textContent = humanize(review.decision);
    renderPosition(item.position);
    renderContent(item, review);
    renderBrief(item.brief);
    document.getElementById("technical-content").textContent = JSON.stringify(item.technical, null, 2);
    const notes = document.getElementById("review-notes");
    notes.value = typeof review.notes === "string" ? review.notes : "";
    document.querySelectorAll("[data-decision]").forEach(function (button) {
      button.setAttribute("aria-pressed", String(button.dataset.decision === review.decision));
    });
  }

  function renderPosition(position) {
    document.getElementById("position-summary").textContent = humanize(position.sideToMove) + " to move · " + humanize(position.status);
    document.getElementById("move-history").textContent = position.moveHistory.length ? position.moveHistory.join(" ") : "No moves yet";
    const references = position.latestInteraction.referencedIDs;
    document.getElementById("latest-interaction").textContent = humanize(position.latestInteraction.kind) +
      (references.length ? " · " + references.join(", ") : "");
    document.getElementById("tentative-move").textContent = position.tentativeMove ?
      position.tentativeMove.san + (position.tentativeMove.isLegal ? " · legal" : " · not legal") : "None";
    renderBoard(position.fen);
  }

  function renderBoard(fen) {
    const board = document.getElementById("chess-board");
    board.replaceChildren();
    const parsed = core.parseFen(fen);
    parsed.squares.forEach(function (value, index) {
      const rowIndex = Math.floor(index / 8);
      const fileIndex = index % 8;
      const square = element("div", "square " + ((rowIndex + fileIndex) % 2 === 0 ? "light" : "dark"));
      square.setAttribute("role", "gridcell");
      square.dataset.file = value.file;
      square.dataset.rank = String(value.rank);
      square.textContent = value.piece || "";
      square.setAttribute("aria-label", value.square + ", " + (value.pieceName || "empty"));
      board.append(square);
    });
  }

  function turnBlock(turn, heading) {
    const section = element("section", "response-choice");
    if (heading) section.append(element("h3", "", heading));
    section.append(element("p", "coaching-message", turn.message));
    const controls = [];
    controls.push("Next interaction: " + humanize(turn.expects));
    controls.push("Controls: " + (turn.actions.length ? turn.actions.map(humanize).join(", ") : "none"));
    controls.push("Board focus: " + (turn.focus.length ? turn.focus.map(focusLabel).join(", ") : "none"));
    const result = element("p", "turn-result");
    result.append(element("strong", "", controls.shift()), document.createTextNode(" · " + controls.join(" · ")));
    section.append(result);
    return section;
  }

  function focusLabel(focus) {
    return focus.from && focus.to ? focus.from + " to " + focus.to : humanize(focus.type || "focus");
  }

  function renderContent(item, review) {
    const container = document.getElementById("case-content");
    container.replaceChildren();
    if (item.kind === "absolute") {
      const candidate = turnBlock(item.candidate);
      candidate.className = "candidate-response";
      container.append(candidate, rationaleBlock(item.proposed.rationale));
      container.append(element("h3", "proposed-heading", "Proposed scores"));
      const scores = element("ul", "score-list");
      state.model.rubric.scores.forEach(function (rubric) {
        const row = element("li", "score-row");
        const label = element("label", "", rubric.label);
        const selectID = "score-" + rubric.id;
        label.htmlFor = selectID;
        const controls = element("div", "score-control");
        const select = element("select");
        select.id = selectID;
        select.dataset.score = rubric.id;
        for (let score = rubric.minimum; score <= rubric.maximum; score += 1) {
          const option = element("option", "", String(score));
          option.value = String(score);
          select.append(option);
        }
        const current = review.scores && review.scores[rubric.id] !== undefined ? review.scores[rubric.id] : item.proposed.scores[rubric.id];
        select.value = String(current);
        controls.append(select, element("span", "proposed-value", "Proposed " + item.proposed.scores[rubric.id]));
        row.append(label, controls);
        scores.append(row);
      });
      container.append(scores, element("h3", "proposed-heading", "Proposed issue flags"));
      const flags = element("div", "flag-list");
      state.model.rubric.flags.forEach(function (rubric) {
        const label = element("label", "flag-control");
        const input = element("input");
        input.type = "checkbox";
        input.dataset.flag = rubric.id;
        input.checked = review.flags && review.flags[rubric.id] !== undefined ? review.flags[rubric.id] : item.proposed.flags[rubric.id];
        label.append(input, element("span", "", rubric.label + " (proposed " + (item.proposed.flags[rubric.id] ? "yes" : "no") + ")"));
        flags.append(label);
      });
      container.append(flags);
    } else {
      const comparison = element("div", "response-comparison");
      comparison.append(turnBlock(item.responses[0], "Response one"), turnBlock(item.responses[1], "Response two"));
      container.append(comparison, rationaleBlock(item.proposed.rationale));
      container.append(element("h3", "proposed-heading", "Your preferred response"));
      const preference = element("fieldset", "preference-control");
      const legend = element("legend", "", "Proposed: " + preferenceLabel(item.proposed.preference));
      preference.append(legend);
      state.model.rubric.preferences.forEach(function (choice) {
        const label = element("label");
        const input = element("input");
        input.type = "radio";
        input.name = "preference";
        input.value = choice.id;
        input.checked = (review.preference || item.proposed.preference) === choice.id;
        label.append(input, document.createTextNode(choice.label));
        preference.append(label);
      });
      container.append(preference);
    }
  }

  function rationaleBlock(lines) {
    const block = element("section", "rationale");
    block.append(element("h3", "", "Why this was proposed"));
    lines.forEach(function (line) { block.append(element("p", "", line)); });
    return block;
  }

  function renderBrief(brief) {
    const container = document.getElementById("brief-content");
    container.replaceChildren();
    [
      ["Verified facts", brief.verifiedFacts],
      ["Coaching purpose", [brief.coachingPurpose]],
      ["Acceptable alternatives", brief.acceptableAlternatives],
      ["Success criteria", brief.successCriteria],
      ["Severe failure criteria", brief.severeFailureCriteria]
    ].forEach(function (entry) {
      const section = element("section");
      section.append(element("h3", "", entry[0]));
      const values = entry[1];
      if (!values.length) {
        section.append(element("p", "", "None"));
      } else if (values.length === 1) {
        section.append(element("p", "", values[0]));
      } else {
        const list = element("ul");
        values.forEach(function (value) { list.append(element("li", "", value)); });
        section.append(list);
      }
      container.append(section);
    });
  }

  function preferenceLabel(value) {
    const match = state.model.rubric.preferences.find(function (choice) { return choice.id === value; });
    return match ? match.label : humanize(value);
  }

  function updateDecision(decision) {
    if (!state.currentID) return;
    state.reviews = core.setDecision(state.model, state.reviews, state.currentID, decision);
    saveReviews();
    render();
  }

  function updateScore(input) {
    const value = Number(input.value);
    state.reviews = core.applyScore(
      state.model, state.reviews, state.currentID, input.dataset.score, value
    );
    saveReviews();
    render({ retainCurrent: true });
  }

  function updateFlag(input) {
    state.reviews = core.applyFlag(
      state.model, state.reviews, state.currentID, input.dataset.flag, input.checked
    );
    saveReviews();
    render({ retainCurrent: true });
  }

  function changeCase(offset) {
    const filtered = visibleCases();
    const targets = core.navigationTargets(state.model.cases, filtered, state.currentID);
    const targetID = offset < 0 ? targets.previous : targets.next;
    if (targetID) setCurrent(targetID, true);
  }

  async function copySummary() {
    const summary = core.formatSummary(state.model, state.reviews);
    try {
      await navigator.clipboard.writeText(summary);
      announce("Review summary copied.");
    } catch (_error) {
      const textarea = element("textarea");
      textarea.value = summary;
      textarea.setAttribute("aria-hidden", "true");
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.append(textarea);
      textarea.select();
      const copied = document.execCommand("copy");
      textarea.remove();
      announce(copied ? "Review summary copied." : "Copy failed. Select and copy from browser storage tools.");
    }
  }

  function announce(message) {
    document.getElementById("copy-status").textContent = message;
  }

  function bindControls() {
    document.getElementById("previous-case").addEventListener("click", function () { changeCase(-1); });
    document.getElementById("next-case").addEventListener("click", function () { changeCase(1); });
    document.getElementById("agree-decision").addEventListener("click", function () { updateDecision("agree"); });
    document.getElementById("change-decision").addEventListener("click", function () { updateDecision("needsChange"); });
    document.getElementById("review-form").addEventListener("submit", function (event) { event.preventDefault(); });
    document.getElementById("review-notes").addEventListener("input", function (event) {
      state.reviews = core.setNotes(
        state.model, state.reviews, state.currentID, event.target.value
      );
      saveReviews();
    });
    document.getElementById("case-content").addEventListener("change", function (event) {
      if (event.target.matches("[data-score]")) updateScore(event.target);
      else if (event.target.matches("[data-flag]")) updateFlag(event.target);
      else if (event.target.matches('input[name="preference"]')) {
        state.reviews = core.applyPreference(
          state.model, state.reviews, state.currentID, event.target.value
        );
        saveReviews();
        render({ retainCurrent: true });
      }
    });
    document.getElementById("case-filters").addEventListener("click", function (event) {
      const button = event.target.closest("[data-filter]");
      if (!button) return;
      state.filter = button.dataset.filter;
      document.querySelectorAll("[data-filter]").forEach(function (item) {
        item.setAttribute("aria-pressed", String(item === button));
      });
      render();
    });
    document.getElementById("approve-remaining").addEventListener("click", function () {
      const result = core.approveRemaining(state.model, state.reviews);
      state.reviews = result.reviews;
      saveReviews();
      render();
      const approvedLabel = result.approved === 1 ? "case" : "cases";
      const skippedLabel = result.skippedEdited.length === 1 ? "case" : "cases";
      announce(
        "Approved " + result.approved + " unchanged " + approvedLabel + "." +
        (result.skippedEdited.length ? " " + result.skippedEdited.length +
          " edited " + skippedLabel + " left unchanged." : "")
      );
    });
    document.getElementById("copy-summary").addEventListener("click", copySummary);
    document.addEventListener("keydown", function (event) {
      const action = core.shortcutAction({
        key: event.key,
        targetTagName: event.target.tagName,
        targetIsContentEditable: event.target.isContentEditable,
        metaKey: event.metaKey,
        ctrlKey: event.ctrlKey,
        altKey: event.altKey
      });
      if (!action) return;
      event.preventDefault();
      if (action === "previous") changeCase(-1);
      else if (action === "next") changeCase(1);
      else updateDecision(action);
    });
  }

  async function start() {
    bindControls();
    try {
      const response = await fetch("/api/review", { headers: { Accept: "application/json" } });
      if (!response.ok) throw new Error("HTTP " + response.status);
      state.model = await response.json();
      loadReviews();
      state.currentID = state.model.cases[0] ? state.model.cases[0].id : null;
      render();
      document.getElementById("review-app").setAttribute("aria-busy", "false");
    } catch (_error) {
      const error = document.getElementById("app-error");
      error.hidden = false;
      error.textContent = "The pinned judge reference could not be loaded. Stop the review server, inspect its error, and restart it.";
      document.getElementById("review-app").hidden = true;
    }
  }

  document.addEventListener("DOMContentLoaded", start);
}());
