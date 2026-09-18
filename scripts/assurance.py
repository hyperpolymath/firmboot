#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
# SPDX-License-Identifier: MPL-2.0
"""Check the CI evidence register and prove that planted bad evidence is rejected."""

import argparse
import copy
import json
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[1]


def evaluate(documents):
    agda = documents.get("agda", {})
    recovery = documents.get("recovery", {})
    agda = agda if isinstance(agda, dict) else {}
    recovery = recovery if isinstance(recovery, dict) else {}
    checks = recovery.get("checks", {})
    checks = checks if isinstance(checks, dict) else {}

    return {
        "agda_contract": agda.get("success") is True,
        "nonempty_runtime_suite": (
            isinstance(agda.get("runtime_tests_passed"), int)
            and not isinstance(agda.get("runtime_tests_passed"), bool)
            and agda["runtime_tests_passed"] > 0
        ),
        "all_elixir_witnesses": agda.get("elixir_witnesses_checked") == 64,
        "recovery_experiment": recovery.get("success") is True,
        "checkpoint_round_trip": checks.get("checkpoint_round_trip") is True,
        "exact_replay": checks.get("exact_replay") is True,
        "gap_control": checks.get("gap_rejected") is True,
        "truncation_control": checks.get("truncation_rejected") is True,
        "checkpoint_measured": (
            isinstance(recovery.get("checkpoint_bytes"), int)
            and not isinstance(recovery.get("checkpoint_bytes"), bool)
            and recovery["checkpoint_bytes"] > 0
        ),
        "replay_measured": (
            isinstance(recovery.get("replay_reductions"), int)
            and not isinstance(recovery.get("replay_reductions"), bool)
            and recovery["replay_reductions"] > 0
        ),
    }


def negative_controls(documents):
    controls = []

    for name, mutate in (
        ("failed-agda", lambda data: data["agda"].update(success=False)),
        (
            "empty-runtime-suite",
            lambda data: data["agda"].update(runtime_tests_passed=0),
        ),
        (
            "missing-elixir-witness",
            lambda data: data["agda"].update(elixir_witnesses_checked=63),
        ),
        (
            "failed-recovery",
            lambda data: data["recovery"].update(success=False),
        ),
        (
            "unchecked-gap",
            lambda data: data["recovery"]["checks"].update(gap_rejected=False),
        ),
        (
            "unmeasured-checkpoint",
            lambda data: data["recovery"].update(checkpoint_bytes=0),
        ),
    ):
        planted = copy.deepcopy(documents)
        mutate(planted)
        controls.append({"name": name, "rejected": not all(evaluate(planted).values())})

    return controls


def load_evidence(results_dir):
    paths = {
        "agda": results_dir / "agda" / "verification.json",
        "recovery": results_dir / "recovery" / "verification.json",
    }
    return {name: json.loads(path.read_text()) for name, path in paths.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check",))
    parser.add_argument("--ci", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--results-dir", type=Path, default=PROJECT / ".ci-results")
    args = parser.parse_args()

    report = {"ci": args.ci, "requirements": {}, "negative_controls": [], "success": False}

    try:
        documents = load_evidence(args.results_dir.resolve())
        report["requirements"] = evaluate(documents)

        if not all(report["requirements"].values()):
            raise RuntimeError("one or more registered assurance requirements failed")

        report["negative_controls"] = negative_controls(documents)

        if not all(control["rejected"] for control in report["negative_controls"]):
            raise RuntimeError("an assurance negative control was not rejected")

        report["success"] = True
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
        report["error"] = str(error)

    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

    if report["success"]:
        print(
            f"PASS: {len(report['requirements'])} assurance requirements and "
            f"{len(report['negative_controls'])} negative controls"
        )
        return 0

    print(f"FAIL: {report.get('error', 'assurance register did not pass')}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
