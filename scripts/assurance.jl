#!/usr/bin/env julia
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
# SPDX-License-Identifier: MPL-2.0
# Check the CI evidence register and prove that planted bad evidence is rejected.
#
# Julia port of the former scripts/assurance.py (Python is banned estate-wide).
# Tooling only: this script is not an FFI or ABI layer.

const PROJECT = dirname(abspath(@__DIR__))

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

isint(x) = x isa Integer && !(x isa Bool)
isobj(x) = x isa JObj

function evaluate(documents)
    agda = isobj(jget(documents, "agda")) ? jget(documents, "agda") : JObj()
    recovery = isobj(jget(documents, "recovery")) ? jget(documents, "recovery") : JObj()
    checks = isobj(jget(recovery, "checks")) ? jget(recovery, "checks") : JObj()
    measured(k) = isint(jget(recovery, k)) && jget(recovery, k) > 0
    return JObj([
        "agda_contract" => jget(agda, "success") === true,
        "nonempty_runtime_suite" => isint(jget(agda, "runtime_tests_passed")) && jget(agda, "runtime_tests_passed") > 0,
        "all_elixir_witnesses" => jget(agda, "elixir_witnesses_checked") == 64,
        "recovery_experiment" => jget(recovery, "success") === true,
        "checkpoint_round_trip" => jget(checks, "checkpoint_round_trip") === true,
        "exact_replay" => jget(checks, "exact_replay") === true,
        "gap_control" => jget(checks, "gap_rejected") === true,
        "truncation_control" => jget(checks, "truncation_rejected") === true,
        "checkpoint_measured" => measured("checkpoint_bytes"),
        "replay_measured" => measured("replay_reductions"),
    ])
end

function negative_controls(documents)
    mutations = [
        ("failed-agda", d -> jset!(jget(d, "agda"), "success", false)),
        ("empty-runtime-suite", d -> jset!(jget(d, "agda"), "runtime_tests_passed", 0)),
        ("missing-elixir-witness", d -> jset!(jget(d, "agda"), "elixir_witnesses_checked", 63)),
        ("failed-recovery", d -> jset!(jget(d, "recovery"), "success", false)),
        ("unchecked-gap", d -> jset!(jget(jget(d, "recovery"), "checks"), "gap_rejected", false)),
        ("unmeasured-checkpoint", d -> jset!(jget(d, "recovery"), "checkpoint_bytes", 0)),
    ]
    controls = Any[]
    for (name, mutate) in mutations
        planted = deepcopy(documents)
        mutate(planted)
        push!(controls, JObj(["name" => name, "rejected" => !all(last, evaluate(planted))]))
    end
    return controls
end

function load_evidence(results_dir)
    docs = JObj()
    for (k, sub) in (("agda", "agda"), ("recovery", "recovery"))
        p = joinpath(results_dir, sub, "verification.json")
        isfile(p) || error("[Errno 2] No such file or directory: '$p'")
        jset!(docs, k, json_parse(read(p, String)))
    end
    return docs
end

const USAGE = "usage: assurance.jl [--ci] --output PATH [--results-dir PATH] check\n"

function main(args)
    ci = false
    output = nothing
    results_dir = joinpath(PROJECT, ".ci-results")
    positionals = String[]
    i = 1
    bad = nothing
    while i <= length(args)
        a = args[i]
        if a == "--ci"
            ci = true
        elseif a in ("--output", "--results-dir")
            if i == length(args)
                bad = "argument $a: expected one argument"
                break
            end
            v = args[i += 1]
            a == "--output" ? (output = v) : (results_dir = v)
        elseif startswith(a, "--output=")
            output = a[10:end]
        elseif startswith(a, "--results-dir=")
            results_dir = a[15:end]
        elseif startswith(a, "-") && a != "-"
            bad = "unrecognized arguments: $a"
            break
        else
            push!(positionals, a)
        end
        i += 1
    end
    if bad === nothing && (length(positionals) != 1 || positionals[1] != "check" || output === nothing)
        bad = "need the command `check` and --output PATH"
    end
    if bad !== nothing
        print(stderr, USAGE, "assurance.jl: error: ", bad, "\n")
        return 2
    end

    report = JObj(["ci" => ci, "requirements" => JObj(), "negative_controls" => Any[], "success" => false])
    try
        documents = load_evidence(abspath(results_dir))
        jset!(report, "requirements", evaluate(documents))
        all(last, jget(report, "requirements")) || error("one or more registered assurance requirements failed")
        jset!(report, "negative_controls", negative_controls(documents))
        all(c -> jget(c, "rejected") === true, jget(report, "negative_controls")) ||
            error("an assurance negative control was not rejected")
        jset!(report, "success", true)
    catch e
        jset!(report, "error", e isa ErrorException ? e.msg : sprint(showerror, e))
    end

    out = abspath(output)
    mkpath(dirname(out))
    write(out, json_dump(report; sort_keys = true) * "\n")

    if jget(report, "success") === true
        println("PASS: ", length(jget(report, "requirements")), " assurance requirements and ",
                length(jget(report, "negative_controls")), " negative controls")
        return 0
    end
    println("FAIL: ", jget(report, "error", "assurance register did not pass"))
    return 1
end

exit(main(ARGS))
