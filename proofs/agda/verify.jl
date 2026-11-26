#!/usr/bin/env julia
# Recheck the contract, semantic rejection controls and observed Elixir cases.
#
# Julia port of the former proofs/agda/verify.py (Python is banned estate-wide).
# Same steps, same order, same report fields and exit codes.
# Tooling only: this script is not an FFI or ABI layer.

using Dates
using SHA

const PROJECT = dirname(dirname(abspath(@__DIR__)))
const PROOFS = joinpath(PROJECT, "proofs", "agda")
const DEFAULT_SOURCE = joinpath(PROJECT, ".ci-deps", "epistemic-types", "src")
const DEFAULT_REPORT = joinpath(PROJECT, ".ci-results", "agda")

# --- minimal JSON reader/writer (Julia's stdlib has no JSON) -----------------
# Objects are ordered Vector{Pair{String,Any}} so output keeps insertion order,
# as the former Python dicts did.
const JObj = Vector{Pair{String,Any}}

function jset!(o::JObj, k::AbstractString, v)
    for (idx, p) in pairs(o)
        if p.first == k
            o[idx] = String(k) => v
            return o
        end
    end
    push!(o, String(k) => v)
    return o
end
jget(o, k, default = nothing) = (o isa JObj && (for (a, b) in o; a == k && return b; end); default)

function json_parse(s::AbstractString)
    i = firstindex(s)
    n = lastindex(s)
    skip() = (while i <= n && isspace(s[i]); i = nextind(s, i); end)
    function str()
        s[i] == '"' || error("expected string in JSON")
        i = nextind(s, i)
        io = IOBuffer()
        while s[i] != '"'
            if s[i] == '\\'
                i = nextind(s, i)
                e = s[i]
                if e == 'u'
                    print(io, Char(parse(UInt16, SubString(s, i + 1, i + 4), base = 16)))
                    i += 4
                else
                    print(io, get(Dict('n' => '\n', 't' => '\t', 'r' => '\r', 'b' => '\b', 'f' => '\f'), e, e))
                end
            else
                print(io, s[i])
            end
            i = nextind(s, i)
        end
        i = nextind(s, i)
        return String(take!(io))
    end
    function value()
        skip()
        i > n && error("unexpected end of JSON")
        c = s[i]
        if c == '{'
            i = nextind(s, i); obj = JObj(); skip()
            if s[i] == '}'; i = nextind(s, i); return obj; end
            while true
                skip(); k = str(); skip()
                s[i] == ':' || error("expected ':' in JSON object")
                i = nextind(s, i)
                jset!(obj, k, value()); skip()
                if s[i] == ','; i = nextind(s, i)
                elseif s[i] == '}'; i = nextind(s, i); return obj
                else error("bad JSON object"); end
            end
        elseif c == '['
            i = nextind(s, i); arr = Any[]; skip()
            if s[i] == ']'; i = nextind(s, i); return arr; end
            while true
                push!(arr, value()); skip()
                if s[i] == ','; i = nextind(s, i)
                elseif s[i] == ']'; i = nextind(s, i); return arr
                else error("bad JSON array"); end
            end
        elseif c == '"'
            return str()
        elseif startswith(SubString(s, i), "true");  i += 4; return true
        elseif startswith(SubString(s, i), "false"); i += 5; return false
        elseif startswith(SubString(s, i), "null");  i += 4; return nothing
        else
            j = i
            while j <= n && (isdigit(s[j]) || s[j] in "+-.eE"); j = nextind(s, j); end
            j == i && error("bad JSON value at byte $i")
            t = SubString(s, i, prevind(s, j)); i = j
            return all(isdigit, lstrip(t, '-')) ? parse(Int, t) : parse(Float64, t)
        end
    end
    v = value(); skip()
    i > n || error("trailing data after JSON value")
    return v
end

# Python json.dumps default string form (ASCII only).
function json_str(x::AbstractString)
    io = IOBuffer()
    print(io, '"')
    for c in x
        if c == '"'; print(io, "\\\"")
        elseif c == '\\'; print(io, "\\\\")
        elseif c == '\n'; print(io, "\\n")
        elseif c == '\r'; print(io, "\\r")
        elseif c == '\t'; print(io, "\\t")
        elseif c == '\b'; print(io, "\\b")
        elseif c == '\f'; print(io, "\\f")
        elseif c < ' ' || c > '~' && c != '\x7f'
            u = UInt32(c)
            if u > 0xFFFF
                u -= 0x10000
                print(io, "\\u", string(0xD800 + (u >> 10), base = 16, pad = 4),
                      "\\u", string(0xDC00 + (u & 0x3FF), base = 16, pad = 4))
            else
                print(io, "\\u", string(u, base = 16, pad = 4))
            end
        else
            print(io, c)
        end
    end
    print(io, '"')
    return String(take!(io))
end

# Python json.dumps(x, indent=2[, sort_keys=true]).
function json_dump(x; sort_keys = false, level = 0)
    pad = "  " ^ (level + 1)
    close = "  " ^ level
    x === nothing && return "null"
    x isa Bool && return x ? "true" : "false"
    x isa Integer && return string(x)
    x isa AbstractFloat && return string(x)
    x isa AbstractString && return json_str(x)
    if x isa JObj
        isempty(x) && return "{}"
        items = sort_keys ? sort(x, by = p -> p.first) : x
        return "{\n" * join((pad * json_str(k) * ": " * json_dump(v; sort_keys, level = level + 1) for (k, v) in items), ",\n") * "\n" * close * "}"
    end
    isempty(x) && return "[]"
    return "[\n" * join((pad * json_dump(v; sort_keys, level = level + 1) for v in x), ",\n") * "\n" * close * "]"
end

# Pin the reason as well as the failing expression: import, syntax, environment
# and unrelated type errors must never count as successful negative controls.
const REJECTIONS = [
    "DroppedCancellationSample" => ("3 != 2 of type Nat", "refl"),
    "DuplicateAuthority" => ("false != true of type Bool", "refl"),
    "DuplicateReport" => ("1 != 2 of type Nat", "refl"),
    "ForgedFlag" => ("false != true of type Bool", "refl"),
    "ForgedWindow" => ("false != true of type Bool", "refl"),
    "InsufficientHistory" => ("false != true of type Bool", "refl"),
    "InventedHistory" => ("true != false of type Bool", "refl"),
    "MissingAuthority" => ("false != true of type Bool", "refl"),
    "StaleAdmission" => ("3 != 4 of type Nat", "goodAccepted"),
    "StaleRead" => ("Read.initial initial !=[\\s\\S]+of type Read.Store Boundary", "currentRead"),
    "WrongRepresentation" => ("false != true of type Bool", "refl"),
]

struct VerifyError <: Exception
    msg::String
end

const USAGE = """
usage: verify.jl [-h] [--epistemic-src PATH] [--ci] [--report-dir PATH]

Recheck the contract, semantic rejection controls and observed Elixir cases.

options:
  -h, --help            show this help message and exit
  --epistemic-src PATH  default: $(DEFAULT_SOURCE)
  --ci                  Run proof/runtime checks without local Sonar scanning or
                        source archiving; CI requires a separate secret-scanning job
  --report-dir PATH     default: $(DEFAULT_REPORT)
"""

"All files under dir whose name ends in ext, as absolute paths."
function rglob(dir, ext)
    found = String[]
    for (root, _, files) in walkdir(dir)
        for f in files
            endswith(f, ext) && push!(found, joinpath(root, f))
        end
    end
    return found
end

"Order paths component by component, as a path object ordering would."
by_parts(p) = splitpath(p)

relpath_posix(p, base) = join(splitpath(relpath(p, base)), "/")
iso_now() = Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH:MM:SS.sss") * "000+00:00"

"Run argv in PROJECT. Returns (exit code, stdout * stderr). Throws VerifyError on timeout."
function spawn(argv::Vector{String}, timeout)
    out, err = IOBuffer(), IOBuffer()
    cmd = Cmd(Cmd(argv); dir = PROJECT, ignorestatus = true)
    local proc
    try
        proc = run(pipeline(cmd; stdout = out, stderr = err); wait = false)
    catch e
        e isa Base.IOError || rethrow()
        throw(VerifyError("[Errno 2] No such file or directory: '$(argv[1])'"))
    end
    timed_out = Ref(false)
    timer = Timer(timeout) do _
        timed_out[] = true
        kill(proc)
    end
    wait(proc)
    close(timer)
    timed_out[] && throw(VerifyError("Command '$(join(argv, " "))' timed out after $(timeout) seconds"))
    return proc.exitcode, String(take!(out)) * String(take!(err))
end

function parse_args(args)
    opts = Dict{String,Any}("epistemic-src" => DEFAULT_SOURCE, "ci" => false, "report-dir" => DEFAULT_REPORT, "help" => false)
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "-h" || a == "--help"
            opts["help"] = true
        elseif a == "--ci"
            opts["ci"] = true
        elseif a == "--epistemic-src" || a == "--report-dir"
            i == length(args) && error("argument $a: expected one argument")
            opts[a[3:end]] = args[i += 1]
        elseif startswith(a, "--epistemic-src=") || startswith(a, "--report-dir=")
            k, v = split(a[3:end], "="; limit = 2)
            opts[k] = v
        else
            error("unrecognized arguments: $a")
        end
        i += 1
    end
    return opts
end

function main(args)
    local opts
    try
        opts = parse_args(args)
    catch e
        print(stderr, USAGE, "verify.jl: error: ", sprint(showerror, e) |> s -> replace(s, r"^ErrorException\(\"|\"\)$" => ""), "\n")
        return 2
    end
    if opts["help"]
        print(USAGE)
        return 0
    end

    ci = opts["ci"]
    upstream = rstrip(abspath(opts["epistemic-src"]), '/')
    report_dir = rstrip(abspath(opts["report-dir"]), '/')
    mkpath(report_dir)
    logs = joinpath(report_dir, "logs")
    mkpath(logs)
    report = JObj()
    jset!(report, "started_utc", iso_now())
    jset!(report, "project", PROJECT)
    jset!(report, "epistemic_src", upstream)
    jset!(report, "scope", JObj([
        "core" => "arbitrary finite executions of the Agda transition model",
        "rejections" => sort!([p.first for p in REJECTIONS]),
        "elixir" => "all 32 binary lists of length 5 under 2 fixed activation schedules",
        "comparison_fields" => ["normalized detector", "history", "frames", "events"],
        "general_implementation_refinement" => false,
        "physical_continuity" => false,
    ]))
    steps = Any[]
    jset!(report, "steps", steps)
    jset!(report, "success", false)

    function step(name, command; mismatch = nothing, expression = nothing, timeout = 120)
        argv = String.(command)
        code, output = spawn(argv, timeout)
        log = joinpath(logs, "$name.log")
        write(log, output)
        if mismatch === nothing
            passed = code == 0
            startswith(name, "scan-") && (passed = passed && occursin("No issues found", output))
        else
            passed = code == 42 &&
                     occursin(Regex(mismatch), output) &&
                     occursin("when checking that the expression $expression has type", output) &&
                     occursin("/$name.agda:14,", output)
        end
        push!(steps, JObj([
            "name" => name, "argv" => argv, "exit_code" => code, "passed" => passed,
            "expected_mismatch" => mismatch, "log" => relpath_posix(log, report_dir),
        ]))
        println(passed ? "PASS" : "FAIL", " ", name)
        flush(stdout)
        if !passed
            # Sonar output could contain a value; retain the diagnostic locally
            # and name the failed scan without echoing it into the conversation.
            detail = startswith(name, "scan-") ? log : output
            throw(VerifyError("$name did not meet its expected result: $detail"))
        end
        return output
    end

    try
        isdir(upstream) || throw(VerifyError("Missing canonical epistemic source: $upstream"))
        scan_paths = [PROOFS, upstream, joinpath(PROJECT, "lib"), joinpath(PROJECT, "test"),
                      joinpath(PROJECT, "mix.exs"), joinpath(PROJECT, ".formatter.exs"),
                      joinpath(PROJECT, "README.md"), joinpath(PROJECT, "SPEC.md")]
        ci || step("scan-sources", ["sonar", "analyze", "secrets", scan_paths...])
        jset!(report, "local_secrets_scan", !ci)
        actual = Set(f[1:end-5] for f in readdir(joinpath(PROOFS, "reject")) if endswith(f, ".agda"))
        manifest = Set(p.first for p in REJECTIONS)
        actual == manifest || throw(VerifyError("The enumerated rejection files differ from the verifier's manifest"))

        agda_version = strip(step("agda-version", ["agda", "--version"]))
        agda_version == "Agda version 2.6.4.3" ||
            throw(VerifyError("Review diagnostics for this unpinned version: $agda_version"))
        step("elixir-version", ["elixir", "--version"])
        agda = ["agda", "--no-libraries", "--safe", "--without-K",
                "--double-check", "--ignore-interfaces", "-W", "error",
                "-i", PROOFS, "-i", upstream]
        all_agda = joinpath(PROOFS, "Firmboot", "All.agda")
        agreement = joinpath(PROOFS, "Firmboot", "ElixirAgreement.agda")
        step("core", [agda; all_agda])
        for mod in sort!(rglob(joinpath(PROOFS, "Firmboot"), ".agda"); by = by_parts)
            if mod != all_agda && mod != agreement
                label = replace(replace(relpath_posix(mod, joinpath(PROOFS, "Firmboot")), r"\.agda$" => ""), "/" => "-")
                step("module-" * label, [agda; mod])
            end
        end
        for (name, (pattern, expression)) in REJECTIONS
            step(name, [agda; "-i"; joinpath(PROOFS, "reject"); joinpath(PROOFS, "reject", "$name.agda")];
                 mismatch = pattern, expression = expression)
        end

        step("format-runtime", ["mix", "format", "--check-formatted"])
        step("format-fixtures", ["mix", "format", "--check-formatted", joinpath(PROOFS, "fixtures.exs")])
        step("compile-runtime", ["mix", "compile", "--warnings-as-errors"])
        test_output = step("runtime-tests", ["mix", "test", "--seed", "0"])
        summary = match(r"(\d+) tests?, (\d+) failures?", test_output)
        if summary === nothing || parse(Int, summary[1]) == 0 || parse(Int, summary[2]) != 0
            throw(VerifyError("The runtime test output did not confirm a nonempty passing suite"))
        end
        jset!(report, "runtime_tests_passed", parse(Int, summary[1]))
        step("generate-elixir-cases", ["mix", "run", joinpath(PROOFS, "fixtures.exs"), agreement])
        ci || step("scan-generated", ["sonar", "analyze", "secrets", agreement])
        names = [m.match for m in eachmatch(r"^(?:forward|return)[0-9]+(?= :)"m, read(agreement, String))]
        expected = Set(string(s, i) for s in ("forward", "return") for i in 0:31)
        if length(names) != 64 || length(Set(names)) != length(expected) || !all(n -> n in expected, names)
            throw(VerifyError("Generated witnesses do not enumerate the promised 64 cases"))
        end
        step("elixir-agreement", [agda; agreement])
        jset!(report, "elixir_witnesses_checked", length(names))

        # Snapshot all local proof/verification sources, imported repository
        # sources and the observed runtime, without compiled interfaces.
        local_files = Set(rglob(PROOFS, ".agda"))
        for f in ("verify.jl", "fixtures.exs", "README.md")
            push!(local_files, joinpath(PROOFS, f))
        end
        union!(local_files, rglob(joinpath(PROJECT, "lib"), ".ex"))
        union!(local_files, rglob(joinpath(PROJECT, "test"), ".exs"))
        for f in ("mix.exs", ".formatter.exs", "README.md", "SPEC.md")
            push!(local_files, joinpath(PROJECT, f))
        end
        sources = [(p, "firmboot/" * relpath_posix(p, PROJECT)) for p in local_files]
        for p in rglob(upstream, ".agda")
            push!(sources, (p, "epistemic-types/src/" * relpath_posix(p, upstream)))
        end
        files = JObj()
        snapshot = joinpath(report_dir, "snapshot")
        sort!(sources; by = last)
        for (source, relative) in sources
            if !ci
                destination = joinpath(snapshot, split(relative, "/")...)
                mkpath(dirname(destination))
                cp(source, destination; force = true)
            end
            jset!(files, relative, JObj(["source" => source, "sha256" => bytes2hex(open(sha256, source))]))
        end
        jset!(report, "source_manifest", files)
        jset!(report, "success", true)
    catch error
        msg = error isa VerifyError ? error.msg :
              error isa SystemError ? "[Errno $(error.errnum)] $(error.prefix)" : sprint(showerror, error)
        jset!(report, "error", msg)
        println(msg)
        flush(stdout)
    finally
        jset!(report, "finished_utc", iso_now())
        destination = joinpath(report_dir, "verification.json")
        write(destination, json_dump(report) * "\n")
        println("Report: ", destination)
    end
    return jget(report, "success") === true ? 0 : 1
end

exit(main(ARGS))
