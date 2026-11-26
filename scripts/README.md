# Scripts

Repository-level tooling, not part of any skill.

| Path | Role |
| --- | --- |
| `publish.zsh` | build an npm package from a skill and publish it |

## Publishing

A skill is not published from the repository root. Each skill owns its npm
metadata in `skills/<skill>/package.json`; `publish.zsh` copies the directory to
a clean build location and publishes it as-is (no generated `package.json`):

```sh
./scripts/publish.zsh --no-publish   # build only, print tarball contents
./scripts/publish.zsh --dry-run      # full npm publish --dry-run
./scripts/publish.zsh                # publish to npm
```

| Option | Default | Meaning |
| --- | --- | --- |
| `--skill <name>` | `zsh-completion` | directory under `skills/` |
| `--tag <tag>` | `latest` | dist-tag |
| `--access <level>` | `public` | `public` or `restricted` |
| `--no-publish` | | build and list contents only |
| `--dry-run` | | `npm publish --dry-run`, no upload, no auth |
| `--force` | | publish even if the version already exists |

What lands in the tarball is decided by the `files` field of the skill's
`package.json`. `.DS_Store`, `._*`, and `.git/` are stripped from the copy.

The build directory is `.tmp/npm/<skill>` (ignored by git) and is recreated on
every run. If a skill has no `README.md`, a minimal package README is generated
from the `description` in its `package.json`.

Before publishing, the script checks that the version is not already in the
registry and that npm is logged in (`npm login`). Version bumps are not part of
the script: bump `version` in `skills/<skill>/package.json`, keep
`metadata.version` in `SKILL.md` in sync (a mismatch is reported as a warning),
then publish.
