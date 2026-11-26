# zsh-completion

Generate, update, and audit native zsh completions (`_command`) for CLI tools.

The skill teaches an agent to pick a source (an existing completion, the tool's
own generator, `--help`, man, or source), build the `#compdef` body with
`_arguments`/`_values`/`_describe`, and verify it in three levels: syntax and
lint, `compinit` registration and dispatch, and a real TAB through `zpty`.

Native zsh only — no `bashcompinit`, no `COMP_WORDS`, no interpreter calls from
inside the completion.

## Install

```sh
npm install @egorlem/zsh-completion
```

The package lands in `node_modules/@egorlem/zsh-completion`. Point the agent at
`SKILL.md` (the contract) and the `references/` and `scripts/` next to it.

## Layout

| Path | Role |
| --- | --- |
| `SKILL.md` | agent contract: rules, decisions, workflow, verification |
| `references/` | templates, help parsing, zsh patterns, anti-patterns |
| `scripts/preflight.zsh` | collect facts before generating |
| `scripts/collect/` | `fpath`, shadowing, safe help probing |
| `scripts/verify/` | lint, harness gate, real-TAB harness |
| `scripts/self-check.zsh` | maintainer check on the `_demo` fixture |
| `tests/fixtures/_demo` | fixture completion for lint and TAB checks |

## License

WTFPL, full text in `LICENSE`.
