#!/usr/bin/env bun
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// SPDX-License-Identifier: MPL-2.0
// Check the CI evidence register and prove that planted bad evidence is rejected.
//
// Bun port of the former scripts/assurance.py (Python is banned estate-wide).

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { parseArgs } from "node:util";

const PROJECT = path.resolve(import.meta.dir, "..");

const isObj = (x) => x !== null && typeof x === "object" && !Array.isArray(x);
const isInt = (x) => typeof x === "number" && Number.isInteger(x);

function evaluate(documents) {
  const agda = isObj(documents.agda) ? documents.agda : {};
  const recovery = isObj(documents.recovery) ? documents.recovery : {};
  const checks = isObj(recovery.checks) ? recovery.checks : {};

  return {
    agda_contract: agda.success === true,
    nonempty_runtime_suite: isInt(agda.runtime_tests_passed) && agda.runtime_tests_passed > 0,
    all_elixir_witnesses: agda.elixir_witnesses_checked === 64,
    recovery_experiment: recovery.success === true,
    checkpoint_round_trip: checks.checkpoint_round_trip === true,
    exact_replay: checks.exact_replay === true,
    gap_control: checks.gap_rejected === true,
    truncation_control: checks.truncation_rejected === true,
    checkpoint_measured: isInt(recovery.checkpoint_bytes) && recovery.checkpoint_bytes > 0,
    replay_measured: isInt(recovery.replay_reductions) && recovery.replay_reductions > 0,
  };
}

function negativeControls(documents) {
  const controls = [];
  const mutations = [
    ["failed-agda", (d) => Object.assign(d.agda, { success: false })],
    ["empty-runtime-suite", (d) => Object.assign(d.agda, { runtime_tests_passed: 0 })],
    ["missing-elixir-witness", (d) => Object.assign(d.agda, { elixir_witnesses_checked: 63 })],
    ["failed-recovery", (d) => Object.assign(d.recovery, { success: false })],
    ["unchecked-gap", (d) => Object.assign(d.recovery.checks, { gap_rejected: false })],
    ["unmeasured-checkpoint", (d) => Object.assign(d.recovery, { checkpoint_bytes: 0 })],
  ];
  for (const [name, mutate] of mutations) {
    const planted = structuredClone(documents);
    mutate(planted);
    controls.push({ name, rejected: !Object.values(evaluate(planted)).every(Boolean) });
  }
  return controls;
}

function loadEvidence(resultsDir) {
  const paths = {
    agda: path.join(resultsDir, "agda", "verification.json"),
    recovery: path.join(resultsDir, "recovery", "verification.json"),
  };
  return Object.fromEntries(Object.entries(paths).map(([k, p]) => [k, JSON.parse(readFileSync(p, "utf8"))]));
}

/** JSON with keys sorted at every level, indent 2. */
function sortedJson(x) {
  const sort = (v) =>
    Array.isArray(v) ? v.map(sort)
      : isObj(v) ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, sort(v[k])]))
        : v;
  return JSON.stringify(sort(x), null, 2) + "\n";
}

function main() {
  let parsed;
  try {
    parsed = parseArgs({
      args: process.argv.slice(2),
      options: {
        ci: { type: "boolean", default: false },
        output: { type: "string" },
        "results-dir": { type: "string", default: path.join(PROJECT, ".ci-results") },
      },
      allowPositionals: true,
      strict: true,
    });
  } catch (e) {
    process.stderr.write(`usage: assurance.js [--ci] --output PATH [--results-dir PATH] check\nassurance.js: error: ${e.message}\n`);
    return 2;
  }
  if (parsed.positionals.length !== 1 || parsed.positionals[0] !== "check" || !parsed.values.output) {
    process.stderr.write("usage: assurance.js [--ci] --output PATH [--results-dir PATH] check\n" +
      "assurance.js: error: need the command `check` and --output PATH\n");
    return 2;
  }
  const args = parsed.values;
  const report = { ci: args.ci, requirements: {}, negative_controls: [], success: false };

  try {
    const documents = loadEvidence(path.resolve(args["results-dir"]));
    report.requirements = evaluate(documents);
    if (!Object.values(report.requirements).every(Boolean)) {
      throw new Error("one or more registered assurance requirements failed");
    }
    report.negative_controls = negativeControls(documents);
    if (!report.negative_controls.every((c) => c.rejected)) {
      throw new Error("an assurance negative control was not rejected");
    }
    report.success = true;
  } catch (error) {
    report.error = String(error instanceof Error ? error.message : error);
  }

  const output = path.resolve(args.output);
  mkdirSync(path.dirname(output), { recursive: true });
  writeFileSync(output, sortedJson(report));

  if (report.success) {
    console.log(`PASS: ${Object.keys(report.requirements).length} assurance requirements and ${report.negative_controls.length} negative controls`);
    return 0;
  }
  console.log(`FAIL: ${report.error ?? "assurance register did not pass"}`);
  return 1;
}

process.exit(main());
