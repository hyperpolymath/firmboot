#!/usr/bin/env python3
"""Recheck the contract, semantic rejection controls and observed Elixir cases."""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
PROOFS = PROJECT / "proofs/agda"
DEFAULT_SOURCE = PROJECT / ".ci-deps/epistemic-types/src"

# Pin the reason as well as the failing expression: import, syntax, environment
# and unrelated type errors must never count as successful negative controls.
REJECTIONS = {
    "DroppedCancellationSample": (r"3 != 2 of type Nat", "refl"),
    "DuplicateAuthority": (r"false != true of type Bool", "refl"),
    "DuplicateReport": (r"1 != 2 of type Nat", "refl"),
    "ForgedFlag": (r"false != true of type Bool", "refl"),
    "ForgedWindow": (r"false != true of type Bool", "refl"),
    "InsufficientHistory": (r"false != true of type Bool", "refl"),
    "InventedHistory": (r"true != false of type Bool", "refl"),
    "MissingAuthority": (r"false != true of type Bool", "refl"),
    "StaleAdmission": (r"3 != 4 of type Nat", "goodAccepted"),
    "StaleRead": (
        r"Read.initial initial !=[\s\S]+of type Read.Store Boundary", "currentRead"
    ),
    "WrongRepresentation": (r"false != true of type Bool", "refl"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--epistemic-src", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument(
        "--ci", action="store_true",
        help="Run proof/runtime checks without local Sonar scanning or source archiving; CI requires a separate secret-scanning job",
    )
    parser.add_argument(
        "--report-dir", type=Path,
        default=PROJECT / ".ci-results/agda",
    )
    args = parser.parse_args()
    upstream = args.epistemic_src.resolve()
    report_dir = args.report_dir.resolve()
    report_dir.mkdir(parents=True, exist_ok=True)
    logs = report_dir / "logs"
    logs.mkdir(exist_ok=True)
    report = {
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "project": str(PROJECT),
        "epistemic_src": str(upstream),
        "scope": {
            "core": "arbitrary finite executions of the Agda transition model",
            "rejections": sorted(REJECTIONS),
            "elixir": "all 32 binary lists of length 5 under 2 fixed activation schedules",
            "comparison_fields": ["normalized detector", "history", "frames", "events"],
            "general_implementation_refinement": False,
            "physical_continuity": False,
        },
        "steps": [],
        "success": False,
    }

    def run(name, command, *, mismatch=None, expression=None, timeout=120):
        result = subprocess.run(
            [str(x) for x in command], cwd=PROJECT,
            capture_output=True, text=True, timeout=timeout,
        )
        output = result.stdout + result.stderr
        log = logs / f"{name}.log"
        log.write_text(output)
        if mismatch is None:
            passed = result.returncode == 0
            if name.startswith("scan-"):
                passed = passed and "No issues found" in output
        else:
            passed = (
                result.returncode == 42
                and re.search(mismatch, output) is not None
                and f"when checking that the expression {expression} has type" in output
                and f"/{name}.agda:14," in output
            )
        report["steps"].append({
            "name": name, "argv": [str(x) for x in command],
            "exit_code": result.returncode, "passed": passed,
            "expected_mismatch": mismatch, "log": str(log.relative_to(report_dir)),
        })
        print(f"{'PASS' if passed else 'FAIL'} {name}", flush=True)
        if not passed:
            # Sonar output could contain a value; retain the diagnostic locally
            # and name the failed scan without echoing it into the conversation.
            detail = str(log) if name.startswith("scan-") else output
            raise RuntimeError(f"{name} did not meet its expected result: {detail}")
        return output

    try:
        if not upstream.is_dir():
            raise RuntimeError(f"Missing canonical epistemic source: {upstream}")
        scan_paths = [
            PROOFS, upstream, PROJECT / "lib", PROJECT / "test",
            PROJECT / "mix.exs", PROJECT / ".formatter.exs",
            PROJECT / "README.md", PROJECT / "SPEC.md",
        ]
        if not args.ci:
            run("scan-sources", ["sonar", "analyze", "secrets", *scan_paths])
        report["local_secrets_scan"] = not args.ci
        actual_controls = {p.stem for p in (PROOFS / "reject").glob("*.agda")}
        if actual_controls != set(REJECTIONS):
            raise RuntimeError("The enumerated rejection files differ from the verifier's manifest")

        agda_version = run("agda-version", ["agda", "--version"]).strip()
        if agda_version != "Agda version 2.6.4.3":
            raise RuntimeError(f"Review diagnostics for this unpinned version: {agda_version}")
        run("elixir-version", ["elixir", "--version"])
        agda = [
            "agda", "--no-libraries", "--safe", "--without-K",
            "--double-check", "--ignore-interfaces", "-W", "error",
            "-i", PROOFS, "-i", upstream,
        ]
        run("core", [*agda, PROOFS / "Firmboot/All.agda"])
        for module in sorted((PROOFS / "Firmboot").rglob("*.agda")):
            if module not in {PROOFS / "Firmboot/All.agda", PROOFS / "Firmboot/ElixirAgreement.agda"}:
                module_label = module.relative_to(PROOFS / "Firmboot").with_suffix("").as_posix().replace("/", "-")
                run("module-" + module_label, [*agda, module])
        for name, (pattern, expression) in REJECTIONS.items():
            run(name, [*agda, "-i", PROOFS / "reject", PROOFS / f"reject/{name}.agda"],
                mismatch=pattern, expression=expression)

        run("format-runtime", ["mix", "format", "--check-formatted"])
        run("format-fixtures", ["mix", "format", "--check-formatted", PROOFS / "fixtures.exs"])
        run("compile-runtime", ["mix", "compile", "--warnings-as-errors"])
        test_output = run("runtime-tests", ["mix", "test", "--seed", "0"])
        test_summary = re.search(r"(\d+) tests?, (\d+) failures?", test_output)
        if test_summary is None or int(test_summary[1]) == 0 or int(test_summary[2]) != 0:
            raise RuntimeError("The runtime test output did not confirm a nonempty passing suite")
        report["runtime_tests_passed"] = int(test_summary[1])
        agreement = PROOFS / "Firmboot/ElixirAgreement.agda"
        run("generate-elixir-cases", ["mix", "run", PROOFS / "fixtures.exs", agreement])
        if not args.ci:
            run("scan-generated", ["sonar", "analyze", "secrets", agreement])
        names = re.findall(r"^(?:forward|return)[0-9]+(?= :)", agreement.read_text(), re.M)
        expected_names = {f"{schedule}{i}" for schedule in ("forward", "return") for i in range(32)}
        if len(names) != 64 or set(names) != expected_names:
            raise RuntimeError("Generated witnesses do not enumerate the promised 64 cases")
        run("elixir-agreement", [*agda, agreement])
        report["elixir_witnesses_checked"] = len(names)

        # Snapshot all local proof/verification sources, imported repository
        # sources and the observed runtime, without compiled interfaces.
        local = set(PROOFS.rglob("*.agda")) | {PROOFS / "verify.py", PROOFS / "fixtures.exs", PROOFS / "README.md"}
        local |= set((PROJECT / "lib").rglob("*.ex")) | set((PROJECT / "test").rglob("*.exs"))
        local |= {PROJECT / "mix.exs", PROJECT / ".formatter.exs", PROJECT / "README.md", PROJECT / "SPEC.md"}
        sources = [(p, Path("firmboot") / p.relative_to(PROJECT)) for p in local]
        sources += [(p, Path("epistemic-types/src") / p.relative_to(upstream)) for p in upstream.rglob("*.agda")]
        manifest = {}
        snapshot = report_dir / "snapshot"
        for source, relative in sorted(sources, key=lambda pair: str(pair[1])):
            if not args.ci:
                destination = snapshot / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
            manifest[str(relative)] = {
                "source": str(source),
                "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            }
        report["source_manifest"] = manifest
        report["success"] = True
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        report["error"] = str(error)
        print(str(error), flush=True)
    finally:
        report["finished_utc"] = datetime.now(timezone.utc).isoformat()
        destination = report_dir / "verification.json"
        destination.write_text(json.dumps(report, indent=2) + "\n")
        print(f"Report: {destination}", flush=True)
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
