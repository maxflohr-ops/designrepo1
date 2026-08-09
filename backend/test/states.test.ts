import { describe, expect, it } from "vitest";
import { assertTransition, InvalidTransition } from "../src/domain/states.js";

describe("state machines (§3)", () => {
  it("bounty: draft → funding → live → closing → settled", () => {
    assertTransition("bounty", "draft", "funding");
    assertTransition("bounty", "funding", "live");
    assertTransition("bounty", "live", "closing");
    assertTransition("bounty", "closing", "settled");
  });

  it("bounty: cancelled reachable from draft and funding only; a live bounty cannot lose funding", () => {
    assertTransition("bounty", "draft", "cancelled");
    assertTransition("bounty", "funding", "cancelled");
    expect(() => assertTransition("bounty", "live", "cancelled")).toThrow(InvalidTransition);
    expect(() => assertTransition("bounty", "live", "funding")).toThrow(InvalidTransition);
    expect(() => assertTransition("bounty", "live", "draft")).toThrow(InvalidTransition);
    expect(() => assertTransition("bounty", "settled", "live")).toThrow(InvalidTransition);
  });

  it("claim: open → submitted → settled, open → expired, nothing else", () => {
    assertTransition("claim", "open", "submitted");
    assertTransition("claim", "submitted", "settled");
    assertTransition("claim", "open", "expired");
    expect(() => assertTransition("claim", "expired", "open")).toThrow(InvalidTransition);
    expect(() => assertTransition("claim", "open", "settled")).toThrow(InvalidTransition);
    expect(() => assertTransition("claim", "settled", "open")).toThrow(InvalidTransition);
  });

  it("submission: held branches off counting or payable and can resolve back or void", () => {
    assertTransition("submission", "pending_checks", "counting");
    assertTransition("submission", "pending_checks", "rejected");
    assertTransition("submission", "counting", "payable");
    assertTransition("submission", "counting", "held");
    assertTransition("submission", "payable", "held");
    assertTransition("submission", "payable", "paid");
    assertTransition("submission", "held", "payable");
    assertTransition("submission", "held", "void");
    assertTransition("submission", "counting", "void");
    expect(() => assertTransition("submission", "paid", "held")).toThrow(InvalidTransition);
    expect(() => assertTransition("submission", "void", "counting")).toThrow(InvalidTransition);
    expect(() => assertTransition("submission", "pending_checks", "paid")).toThrow(InvalidTransition);
  });
});
