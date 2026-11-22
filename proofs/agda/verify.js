#!/usr/bin/env bun
// Recheck the contract, semantic rejection controls and observed Elixir cases.
//
// Bun port of the former proofs/agda/verify.py (Python is banned estate-wide).
// Same steps, same order, same report fields and exit codes.

import { createHash } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, writeFileSync, copyFileSync, statSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { parseArgs } from "node:util";

const PROJECT = path.resolve(import.meta.dir, "..", "..");
const PROOFS = path.join(PROJECT, "proofs/agda");
const DEFAULT_SOURCE = path.join(PROJECT, ".ci-deps/epistemic-types/src");

// Pin the reason as well as the failing expression: import, syntax, environment
// and unrelated type errors must never count as successful negative controls.
const REJECTIONS = {
  DroppedCancellationSample: ["3 != 2 of type Nat", "refl"],
  DuplicateAuthority: ["false != true of type Bool", "refl"],
  DuplicateReport: ["1 != 2 of type Nat", "refl"],
  ForgedFlag: ["false != true of type Bool", "refl"],
  ForgedWindow: ["false != true of type Bool", "refl"],
  InsufficientHistory: ["false != true of type Bool", "refl"],
  InventedHistory: ["true != false of type Bool", "refl"],
  MissingAuthority: ["false != true of type Bool", "refl"],
  StaleAdmission: ["3 != 4 of type Nat", "goodAccepted"],
  StaleRead: ["Read.initial initial !=[\\s\\S]+of type Read.Store Boundary", "currentRead"],
  WrongRepresentation: ["false != true of type Bool", "refl"],
};

class VerifyError extends Error {}

const usage = `usage: verify.js [-h] [--epistemic-src PATH] [--ci] [--report-dir PATH]

Recheck the contract, semantic rejection controls and observed Elixir cases.

options:
  -h, --help            show this help message and exit
  --epistemic-src PATH  default: ${DEFAULT_SOURCE}
  --ci                  Run proof/runtime checks without local Sonar scanning or
                        source archiving; CI requires a separate secret-scanning job
  --report-dir PATH     default: ${path.join(PROJECT, ".ci-results/agda")}
`;

/** All files under dir whose name ends in ext, as absolute paths. */
function rglob(dir, ext) {
  const found = [];
  for (const e of readdirSync(dir, { withFileTypes: true, recursive: true })) {
    if (e.name.endsWith(ext)) found.push(path.join(e.parentPath ?? e.path, e.name));
  }
  return found;
}

/** Order paths component by component, as a path object ordering would. */
function byParts(a, b) {
  const x = a.split(path.sep), y = b.split(path.sep);
  for (let i = 0; i < Math.min(x.length, y.length); i++) {
    if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1;
  }
  return x.length - y.length;
}

const pyIso = () => new Date().toISOString().replace("Z", "+00:00");
const posix = (p) => p.split(path.sep).join("/");

function main() {
  let values;
  try {
    ({ values } = parseArgs({
      options: {
        "epistemic-src": { type: "string", default: DEFAULT_SOURCE },
        ci: { type: "boolean", default: false },
        "report-dir": { type: "string", default: path.join(PROJECT, ".ci-results/agda") },
        help: { type: "boolean", short: "h", default: false },
      },
      strict: true,
    }));
  } catch (e) {
    process.stderr.write(usage + `verify.js: error: ${e.message}\n`);
    return 2;
  }
  if (values.help) { process.stdout.write(usage); return 0; }

  const ci = values.ci;
  const upstream = path.resolve(values["epistemic-src"]);
  const reportDir = path.resolve(values["report-dir"]);
  mkdirSync(reportDir, { recursive: true });
  const logs = path.join(reportDir, "logs");
  mkdirSync(logs, { recursive: true });
  const report = {
    started_utc: pyIso(),
    project: PROJECT,
    epistemic_src: upstream,
    scope: {
      core: "arbitrary finite executions of the Agda transition model",
      rejections: Object.keys(REJECTIONS).sort(),
      elixir: "all 32 binary lists of length 5 under 2 fixed activation schedules",
      comparison_fields: ["normalized detector", "history", "frames", "events"],
      general_implementation_refinement: false,
      physical_continuity: false,
    },
    steps: [],
    success: false,
  };

  function run(name, command, { mismatch = null, expression = null, timeout = 120 } = {}) {
    const argv = command.map(String);
    const result = spawnSync(argv[0], argv.slice(1), {
      cwd: PROJECT, encoding: "utf8", timeout: timeout * 1000, maxBuffer: 1 << 30,
    });
    if (result.error) {
      if (result.error.code === "ETIMEDOUT") throw new VerifyError(`Command '${argv.join(" ")}' timed out after ${timeout} seconds`);
      throw result.error; // e.g. ENOENT: the tool is not installed
    }
    const status = result.status ?? -1;
    const output = result.stdout + result.stderr;
    const log = path.join(logs, `${name}.log`);
    writeFileSync(log, output);
    let passed;
    if (mismatch === null) {
      passed = status === 0;
      if (name.startsWith("scan-")) passed = passed && output.includes("No issues found");
    } else {
      passed =
        status === 42 &&
        new RegExp(mismatch).test(output) &&
        output.includes(`when checking that the expression ${expression} has type`) &&
        output.includes(`/${name}.agda:14,`);
    }
    report.steps.push({
      name, argv, exit_code: status, passed,
      expected_mismatch: mismatch, log: posix(path.relative(reportDir, log)),
    });
    console.log(`${passed ? "PASS" : "FAIL"} ${name}`);
    if (!passed) {
      // Sonar output could contain a value; retain the diagnostic locally
      // and name the failed scan without echoing it into the conversation.
      const detail = name.startsWith("scan-") ? log : output;
      throw new VerifyError(`${name} did not meet its expected result: ${detail}`);
    }
    return output;
  }

  try {
    if (!statSync(upstream, { throwIfNoEntry: false })?.isDirectory()) {
      throw new VerifyError(`Missing canonical epistemic source: ${upstream}`);
    }
    const scanPaths = [
      PROOFS, upstream, path.join(PROJECT, "lib"), path.join(PROJECT, "test"),
      path.join(PROJECT, "mix.exs"), path.join(PROJECT, ".formatter.exs"),
      path.join(PROJECT, "README.md"), path.join(PROJECT, "SPEC.md"),
    ];
    if (!ci) run("scan-sources", ["sonar", "analyze", "secrets", ...scanPaths]);
    report.local_secrets_scan = !ci;
    const actual = new Set(
      readdirSync(path.join(PROOFS, "reject")).filter((n) => n.endsWith(".agda")).map((n) => n.slice(0, -5)),
    );
    const manifest = Object.keys(REJECTIONS);
    if (actual.size !== manifest.length || !manifest.every((n) => actual.has(n))) {
      throw new VerifyError("The enumerated rejection files differ from the verifier's manifest");
    }

    const agdaVersion = run("agda-version", ["agda", "--version"]).trim();
    if (agdaVersion !== "Agda version 2.6.4.3") {
      throw new VerifyError(`Review diagnostics for this unpinned version: ${agdaVersion}`);
    }
    run("elixir-version", ["elixir", "--version"]);
    const agda = [
      "agda", "--no-libraries", "--safe", "--without-K",
      "--double-check", "--ignore-interfaces", "-W", "error",
      "-i", PROOFS, "-i", upstream,
    ];
    const all = path.join(PROOFS, "Firmboot/All.agda");
    const agreement = path.join(PROOFS, "Firmboot/ElixirAgreement.agda");
    run("core", [...agda, all]);
    for (const module of rglob(path.join(PROOFS, "Firmboot"), ".agda").sort(byParts)) {
      if (module !== all && module !== agreement) {
        const label = posix(path.relative(path.join(PROOFS, "Firmboot"), module)).replace(/\.agda$/, "").replaceAll("/", "-");
        run("module-" + label, [...agda, module]);
      }
    }
    for (const [name, [pattern, expression]] of Object.entries(REJECTIONS)) {
      run(name, [...agda, "-i", path.join(PROOFS, "reject"), path.join(PROOFS, `reject/${name}.agda`)],
        { mismatch: pattern, expression });
    }

    run("format-runtime", ["mix", "format", "--check-formatted"]);
    run("format-fixtures", ["mix", "format", "--check-formatted", path.join(PROOFS, "fixtures.exs")]);
    run("compile-runtime", ["mix", "compile", "--warnings-as-errors"]);
    const testOutput = run("runtime-tests", ["mix", "test", "--seed", "0"]);
    const summary = /(\d+) tests?, (\d+) failures?/.exec(testOutput);
    if (summary === null || Number(summary[1]) === 0 || Number(summary[2]) !== 0) {
      throw new VerifyError("The runtime test output did not confirm a nonempty passing suite");
    }
    report.runtime_tests_passed = Number(summary[1]);
    run("generate-elixir-cases", ["mix", "run", path.join(PROOFS, "fixtures.exs"), agreement]);
    if (!ci) run("scan-generated", ["sonar", "analyze", "secrets", agreement]);
    const names = readFileSync(agreement, "utf8").match(/^(?:forward|return)[0-9]+(?= :)/gm) ?? [];
    const expectedNames = new Set(["forward", "return"].flatMap((s) => Array.from({ length: 32 }, (_, i) => `${s}${i}`)));
    if (names.length !== 64 || new Set(names).size !== expectedNames.size || !names.every((n) => expectedNames.has(n))) {
      throw new VerifyError("Generated witnesses do not enumerate the promised 64 cases");
    }
    run("elixir-agreement", [...agda, agreement]);
    report.elixir_witnesses_checked = names.length;

    // Snapshot all local proof/verification sources, imported repository
    // sources and the observed runtime, without compiled interfaces.
    const local = new Set(rglob(PROOFS, ".agda"));
    for (const f of ["verify.js", "fixtures.exs", "README.md"]) local.add(path.join(PROOFS, f));
    for (const f of rglob(path.join(PROJECT, "lib"), ".ex")) local.add(f);
    for (const f of rglob(path.join(PROJECT, "test"), ".exs")) local.add(f);
    for (const f of ["mix.exs", ".formatter.exs", "README.md", "SPEC.md"]) local.add(path.join(PROJECT, f));
    const sources = [...local].map((p) => [p, posix(path.join("firmboot", path.relative(PROJECT, p)))]);
    for (const p of rglob(upstream, ".agda")) sources.push([p, posix(path.join("epistemic-types/src", path.relative(upstream, p)))]);
    const files = {};
    const snapshot = path.join(reportDir, "snapshot");
    sources.sort((a, b) => (a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0));
    for (const [source, relative] of sources) {
      if (!ci) {
        const destination = path.join(snapshot, relative);
        mkdirSync(path.dirname(destination), { recursive: true });
        copyFileSync(source, destination);
      }
      files[relative] = { source, sha256: createHash("sha256").update(readFileSync(source)).digest("hex") };
    }
    report.source_manifest = files;
    report.success = true;
  } catch (error) {
    report.error = String(error instanceof Error ? error.message : error);
    console.log(report.error);
  } finally {
    report.finished_utc = pyIso();
    const destination = path.join(reportDir, "verification.json");
    writeFileSync(destination, JSON.stringify(report, null, 2) + "\n");
    console.log(`Report: ${destination}`);
  }
  return report.success ? 0 : 1;
}

process.exit(main());
