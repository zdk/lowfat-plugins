# The lf-filter DSL

A `filter.lf` file is a list of macros and rules. lowfat runs the first rule
whose fields all hold, top to bottom. Needs lowfat 0.9.0 or newer.

This page covers what the plugins in this repo use. The full reference is in
lowfat's [PLUGINS.md](https://github.com/zdk/lowfat/blob/main/docs/PLUGINS.md).

## A complete file

```
# A macro is a named list of ops.
define strip-progress:
    drop /^Downloading /
    drop /^Compiling /

# A failed command keeps its full error output.
rule failed:
    exit: failed
    do: raw

# Machine-readable output goes to a parser, so leave it alone.
rule build-json:
    sub: build|check
    flag: --json
    do: raw

rule build:
    sub: build|check
    do:
        match level:
            ultra:
                strip-progress
                keep /(error|warning)/
                head 30
                or "mytool build: ok"
            lite:  head 200
            else:
                strip-progress
                head 80

rule other:
    do: head 40
```

## Rules

A rule has a unique name, match fields, and a `do:` body.

| Field   | Value                              | Omitted means  |
| ------- | ---------------------------------- | -------------- |
| `sub`   | subcommand pattern                 | any subcommand |
| `level` | `ultra`, `full` or `lite`          | any level      |
| `exit`  | `ok` or `failed`                   | any exit code  |
| `flag`  | a flag check; the field may repeat | any args       |

Every field must hold. If one does not, lowfat skips the rule and tries the
next one. Put specific rules first and the catch-all last.

**Subcommand patterns**

| Pattern        | Matches                   |
| -------------- | ------------------------- |
| `build`        | one subcommand            |
| `build\|check` | either subcommand         |
| `apply*`       | any subcommand it prefixes |

**Flag checks**

| Form                | True when                                       |
| ------------------- | ----------------------------------------------- |
| `--stat`            | the flag is present, bare or as `--stat=value`  |
| `-o yaml`           | the flag has that value: `-o yaml`, `-o=yaml`, `-oyaml` |
| `-o\|--output json` | either spelling has that value                  |

## Ops

Ops run top to bottom. Each one gets the output of the one before it.

| Op                  | What it does                                             |
| ------------------- | -------------------------------------------------------- |
| `drop /regex/`      | Remove lines that match                                  |
| `keep /regex/`      | Remove lines that do not match                           |
| `head N` / `tail N` | Keep the first or last N lines                           |
| `raw`               | Pass the output through unchanged                        |
| `or "text"`         | Print `text` if nothing is left                          |
| `or-shell: cmd`     | Run `cmd` if nothing is left (`$sub`, `$level` are set)  |
| `shell:` / `python:`| Escape hatch for what the ops above cannot do            |

## Levels

Use `match level:` when a subcommand needs a different pipeline per level.
`else:` covers the levels you did not name.

```
rule list:
    sub: list|ls
    do:
        match level:
            ultra: head 30
            lite:  head 200
            else:  head 80
```

A tool with no subcommands reads better as one rule per level:

```
rule ultra:
    level: ultra
    do:
        keep /(passed|failed)/
        head 40

rule default:
    do: head 150
```

## Branching inside a rule

A `do:` body can hold an `if` / `elif` / `else` cascade. Guards are
`exit ok|failed`, `level <name>`, or a flag check, joined with `and`.

```
rule diff:
    sub: diff
    do:
        if --stat:  head 40
        else:       head 200
```

Prefer a separate rule when you can. A cascade with no matching arm passes
the output through. A rule that does not match lets the next rule try.

## Macros and include

`define` names a list of ops so several rules can share it. A macro holds
plain ops only. It cannot hold `match` or `if`, so write one macro per level
when levels differ.

`include` pulls macros from another file. The path is relative to the file
that includes it.

```
# lib/json.lf provides truncate-json
include ../../lib/json.lf

rule json:
    flag: -o|--output json
    do: truncate-json
```

## The failure rule

Start every file with a rule that has `exit: failed`. An agent needs the full
error when a command breaks, so the usual body is `raw`.

If one subcommand has a better failure view, give it its own rule first:

```
rule test-failed:
    sub: test
    exit: failed
    do:
        keep /(FAILED|panicked|test result:)/
        head 250

rule failed:
    exit: failed
    do: raw
```

## JSON output

lowfat checks every result against the raw output, so a filter cannot hand
the agent broken JSON. If line ops cut a JSON document, lowfat rebuilds it
from the raw data. When the command is piped to another program, JSON passes
through untouched.

For JSON the agent reads directly, use `truncate-json` from `lib/json.lf`. It
prunes long arrays and objects and always emits valid JSON.

## Test as you go

```sh
mytool build > samples/build-full.txt

# Run one sample through the filter. --explain names the rule that ran.
cat samples/build-full.txt | lowfat filter filter.lf --sub=build --explain

# Check the failure rule and a flag rule
cat samples/build-full.txt | lowfat filter filter.lf --sub=build --exit=1
cat samples/build-full.txt | lowfat filter filter.lf --sub=build --args="--json"

# Measure savings over every sample
lowfat plugin bench mytool-compact
```

## Older syntax

Files written as `selector:` rules with a leading `if exit failed:` still
work, and both styles can share a file. New plugins should use named rules.
