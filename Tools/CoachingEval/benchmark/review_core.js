(function (factory) {
  "use strict";
  const api = factory();
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.JudgeReviewCore = api;
}(function () {
  "use strict";

  const STORAGE_SCHEMA = "judge-reference-browser-review.v2";
  const MAXIMUM_NOTE_LENGTH = 2000;
  const DECISIONS = new Set(["unreviewed", "agree", "needsChange"]);
  const PREFERENCES = new Set(["responseOne", "responseTwo", "tie"]);
  const PIECES = {
    K: ["♔", "white king"], Q: ["♕", "white queen"],
    R: ["♖", "white rook"], B: ["♗", "white bishop"],
    N: ["♘", "white knight"], P: ["♙", "white pawn"],
    k: ["♚", "black king"], q: ["♛", "black queen"],
    r: ["♜", "black rook"], b: ["♝", "black bishop"],
    n: ["♞", "black knight"], p: ["♟", "black pawn"]
  };

  function plainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function emptyReview(item) {
    return { kind: item.kind, decision: "unreviewed", notes: "" };
  }

  function emptyReviews(model) {
    return Object.fromEntries(model.cases.map(function (item) {
      return [item.id, emptyReview(item)];
    }));
  }

  function allowedIDs(model, kind) {
    return new Set(model.rubric[kind].map(function (item) { return item.id; }));
  }

  function sanitizeAbsolute(model, item, raw, result) {
    const scoreIDs = allowedIDs(model, "scores");
    const flagIDs = allowedIDs(model, "flags");
    if (raw.scores !== undefined) {
      if (!plainObject(raw.scores)) return false;
      const scores = {};
      for (const entry of Object.entries(raw.scores)) {
        const id = entry[0];
        const value = entry[1];
        if (!scoreIDs.has(id)) continue;
        if (!Number.isInteger(value) || value < 1 || value > 5) return false;
        if (value !== item.proposed.scores[id]) scores[id] = value;
      }
      if (Object.keys(scores).length) result.scores = scores;
    }
    if (raw.flags !== undefined) {
      if (!plainObject(raw.flags)) return false;
      const flags = {};
      for (const entry of Object.entries(raw.flags)) {
        const id = entry[0];
        const value = entry[1];
        if (!flagIDs.has(id)) continue;
        if (typeof value !== "boolean") return false;
        if (value !== item.proposed.flags[id]) flags[id] = value;
      }
      if (Object.keys(flags).length) result.flags = flags;
    }
    return true;
  }

  function sanitizePairwise(item, raw, result) {
    if (raw.preference === undefined) return true;
    if (!PREFERENCES.has(raw.preference)) return false;
    if (raw.preference !== item.proposed.preference) result.preference = raw.preference;
    return true;
  }

  function hasJudgmentChanges(item, review) {
    if (item.kind === "absolute") {
      return Boolean(
        (review.scores && Object.keys(review.scores).length) ||
        (review.flags && Object.keys(review.flags).length)
      );
    }
    return Boolean(review.preference && review.preference !== item.proposed.preference);
  }

  function sanitizeRecord(model, item, raw) {
    const reset = emptyReview(item);
    if (!plainObject(raw) || raw.kind !== item.kind || !DECISIONS.has(raw.decision) ||
        typeof raw.notes !== "string" || raw.notes.length > MAXIMUM_NOTE_LENGTH) {
      return reset;
    }
    const result = { kind: item.kind, decision: raw.decision, notes: raw.notes };
    const valid = item.kind === "absolute" ?
      sanitizeAbsolute(model, item, raw, result) : sanitizePairwise(item, raw, result);
    if (!valid) return reset;
    if (hasJudgmentChanges(item, result) && result.decision !== "needsChange") {
      result.decision = "needsChange";
    }
    return result;
  }

  function normalizeReviews(model, reviews) {
    const raw = plainObject(reviews) ? reviews : {};
    return Object.fromEntries(model.cases.map(function (item) {
      return [item.id, sanitizeRecord(model, item, raw[item.id])];
    }));
  }

  function sanitizeStoredReview(model, payload) {
    if (!plainObject(payload) || payload.schemaVersion !== STORAGE_SCHEMA ||
        payload.referenceSHA256 !== model.reference.sha256 || !plainObject(payload.reviews)) {
      return emptyReviews(model);
    }
    return normalizeReviews(model, payload.reviews);
  }

  function storagePayload(model, reviews) {
    return {
      schemaVersion: STORAGE_SCHEMA,
      referenceSHA256: model.reference.sha256,
      reviews: normalizeReviews(model, reviews)
    };
  }

  function caseByID(model, caseID) {
    const item = model.cases.find(function (candidate) { return candidate.id === caseID; });
    if (!item) throw new Error("Unknown review case");
    return item;
  }

  function editReview(model, reviews, caseID, change) {
    const normalized = normalizeReviews(model, reviews);
    const item = caseByID(model, caseID);
    const review = normalized[caseID];
    change(item, review);
    return normalizeReviews(model, normalized);
  }

  function applyScore(model, reviews, caseID, scoreID, value) {
    return editReview(model, reviews, caseID, function (item, review) {
      if (item.kind !== "absolute" || !allowedIDs(model, "scores").has(scoreID) ||
          !Number.isInteger(value) || value < 1 || value > 5) {
        throw new Error("Invalid score change");
      }
      if (!review.scores) review.scores = {};
      if (value === item.proposed.scores[scoreID]) delete review.scores[scoreID];
      else review.scores[scoreID] = value;
      if (!Object.keys(review.scores).length) delete review.scores;
      review.decision = "needsChange";
    });
  }

  function applyFlag(model, reviews, caseID, flagID, value) {
    return editReview(model, reviews, caseID, function (item, review) {
      if (item.kind !== "absolute" || !allowedIDs(model, "flags").has(flagID) ||
          typeof value !== "boolean") {
        throw new Error("Invalid flag change");
      }
      if (!review.flags) review.flags = {};
      if (value === item.proposed.flags[flagID]) delete review.flags[flagID];
      else review.flags[flagID] = value;
      if (!Object.keys(review.flags).length) delete review.flags;
      review.decision = "needsChange";
    });
  }

  function applyPreference(model, reviews, caseID, preference) {
    return editReview(model, reviews, caseID, function (item, review) {
      if (item.kind !== "pairwise" || !PREFERENCES.has(preference)) {
        throw new Error("Invalid preference change");
      }
      if (preference === item.proposed.preference) delete review.preference;
      else review.preference = preference;
      review.decision = "needsChange";
    });
  }

  function setNotes(model, reviews, caseID, notes) {
    if (typeof notes !== "string") throw new Error("Invalid review notes");
    return editReview(model, reviews, caseID, function (_item, review) {
      review.notes = notes.slice(0, MAXIMUM_NOTE_LENGTH);
    });
  }

  function setDecision(model, reviews, caseID, decision) {
    if (decision !== "agree" && decision !== "needsChange") {
      throw new Error("Invalid review decision");
    }
    return editReview(model, reviews, caseID, function (_item, review) {
      review.decision = decision;
      if (decision === "agree") {
        delete review.scores;
        delete review.flags;
        delete review.preference;
      }
    });
  }

  function hasEdits(item, review) {
    return hasJudgmentChanges(item, review) || Boolean(review.notes.trim());
  }

  function approveRemaining(model, reviews) {
    const normalized = normalizeReviews(model, reviews);
    const skippedEdited = [];
    let approved = 0;
    model.cases.forEach(function (item) {
      const review = normalized[item.id];
      if (hasEdits(item, review)) skippedEdited.push(item.id);
      if (review.decision === "unreviewed" && !hasEdits(item, review)) {
        review.decision = "agree";
        approved += 1;
      }
    });
    return { reviews: normalizeReviews(model, normalized), approved, skippedEdited };
  }

  function progress(model, reviews) {
    const normalized = normalizeReviews(model, reviews);
    const decisions = model.cases.map(function (item) { return normalized[item.id].decision; });
    return {
      reviewed: decisions.filter(function (value) { return value === "agree" || value === "needsChange"; }).length,
      needsChange: decisions.filter(function (value) { return value === "needsChange"; }).length,
      total: model.cases.length
    };
  }

  function visibleCases(model, reviews, filter) {
    const normalized = normalizeReviews(model, reviews);
    if (filter !== "unreviewed" && filter !== "needsChange") return model.cases.slice();
    return model.cases.filter(function (item) {
      return normalized[item.id].decision === filter;
    });
  }

  function adjacentCaseID(cases, currentID, offset) {
    const index = cases.findIndex(function (item) { return item.id === currentID; });
    const target = cases[index + offset];
    return index >= 0 && target ? target.id : null;
  }

  function resolveCurrentCaseID(allCases, visible, currentID, retainCurrent) {
    const exists = allCases.some(function (item) { return item.id === currentID; });
    if (retainCurrent && exists) return currentID;
    if (visible.some(function (item) { return item.id === currentID; })) return currentID;
    return visible.length ? visible[0].id : null;
  }

  function navigationTargets(allCases, visible, currentID) {
    const visibleIndex = visible.findIndex(function (item) { return item.id === currentID; });
    if (visibleIndex >= 0) {
      return {
        previous: visibleIndex > 0 ? visible[visibleIndex - 1].id : null,
        next: visibleIndex < visible.length - 1 ? visible[visibleIndex + 1].id : null
      };
    }
    const currentIndex = allCases.findIndex(function (item) { return item.id === currentID; });
    if (currentIndex < 0) return { previous: null, next: visible.length ? visible[0].id : null };
    let previous = null;
    let next = null;
    visible.forEach(function (item) {
      const index = allCases.findIndex(function (candidate) { return candidate.id === item.id; });
      if (index < currentIndex) previous = item.id;
      else if (index > currentIndex && next === null) next = item.id;
    });
    return { previous, next };
  }

  function shortcutAction(event) {
    const tag = String(event.targetTagName || "").toUpperCase();
    if (["INPUT", "TEXTAREA", "SELECT"].includes(tag) || event.targetIsContentEditable ||
        event.metaKey || event.ctrlKey || event.altKey) return null;
    if (event.key === "ArrowLeft") return "previous";
    if (event.key === "ArrowRight") return "next";
    if (String(event.key).toLowerCase() === "a") return "agree";
    if (String(event.key).toLowerCase() === "c") return "needsChange";
    return null;
  }

  function summaryLine(model, item, review) {
    const parts = ["case=" + item.id, "decision=" + review.decision];
    if (item.kind === "absolute") {
      const scoreChanges = model.rubric.scores.filter(function (rubric) {
        return review.scores && review.scores[rubric.id] !== undefined;
      }).map(function (rubric) {
        return rubric.id + ":" + item.proposed.scores[rubric.id] + "->" + review.scores[rubric.id];
      });
      const flagChanges = model.rubric.flags.filter(function (rubric) {
        return review.flags && review.flags[rubric.id] !== undefined;
      }).map(function (rubric) {
        return rubric.id + ":" + item.proposed.flags[rubric.id] + "->" + review.flags[rubric.id];
      });
      if (scoreChanges.length) parts.push("scores=[" + scoreChanges.join(",") + "]");
      if (flagChanges.length) parts.push("flags=[" + flagChanges.join(",") + "]");
    } else if (review.preference) {
      parts.push("preference=" + item.proposed.preference + "->" + review.preference);
    }
    const note = review.notes.trim().replace(/\s+/g, " ");
    if (note) parts.push("note=" + JSON.stringify(note));
    return parts.join(" ");
  }

  function formatSummary(model, reviews) {
    const normalized = normalizeReviews(model, reviews);
    const counts = progress(model, normalized);
    return [
      "JUDGE REFERENCE REVIEW v1",
      "referenceSHA256=" + model.reference.sha256,
      "reviewed=" + counts.reviewed + "/" + counts.total
    ].concat(model.cases.map(function (item) {
      return summaryLine(model, item, normalized[item.id]);
    })).join("\n") + "\n";
  }

  function parseFen(fen) {
    if (typeof fen !== "string") throw new Error("Invalid FEN");
    const parts = fen.trim().split(/\s+/);
    const rows = parts[0] ? parts[0].split("/") : [];
    if (rows.length !== 8 || (parts[1] !== "w" && parts[1] !== "b")) throw new Error("Invalid FEN");
    const squares = [];
    rows.forEach(function (row, rowIndex) {
      let fileIndex = 0;
      Array.from(row).forEach(function (symbol) {
        if (/^[1-8]$/.test(symbol)) {
          const count = Number(symbol);
          for (let offset = 0; offset < count; offset += 1) {
            squares.push(fenSquare(rowIndex, fileIndex, null));
            fileIndex += 1;
          }
        } else {
          if (!PIECES[symbol]) throw new Error("Invalid FEN");
          squares.push(fenSquare(rowIndex, fileIndex, symbol));
          fileIndex += 1;
        }
      });
      if (fileIndex !== 8) throw new Error("Invalid FEN");
    });
    return { sideToMove: parts[1] === "w" ? "white" : "black", squares };
  }

  function fenSquare(rowIndex, fileIndex, pieceCode) {
    const file = String.fromCharCode(97 + fileIndex);
    const rank = 8 - rowIndex;
    const piece = pieceCode ? PIECES[pieceCode] : null;
    return {
      square: file + rank,
      file,
      rank,
      pieceCode,
      piece: piece ? piece[0] : null,
      pieceName: piece ? piece[1] : null
    };
  }

  return {
    emptyReview,
    sanitizeStoredReview,
    storagePayload,
    applyScore,
    applyFlag,
    applyPreference,
    setNotes,
    setDecision,
    approveRemaining,
    progress,
    visibleCases,
    adjacentCaseID,
    resolveCurrentCaseID,
    navigationTargets,
    shortcutAction,
    formatSummary,
    parseFen
  };
}));
