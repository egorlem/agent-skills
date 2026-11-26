#!/usr/bin/env zsh
# Собрать npm-пакет из скилла и опубликовать его.
#
# Использование:
#   scripts/publish.zsh [options]
#
# Метаданные не генерируются: пакет описывается файлом `package.json` внутри
# самого скилла (`skills/<skill>/package.json`). Скрипт делает три шага:
#   1. копирует каталог скилла в чистый build-каталог;
#   2. проверяет package.json (имя, версия, files) и сверяет версию с
#      `metadata.version` в SKILL.md;
#   3. публикует каталог в npm (или только собирает и печатает содержимое).
#
# Каталог сборки лежит в .tmp/npm/<skill> и пересоздаётся при каждом запуске.
#
# Опции:
#   --skill <name>     скилл из skills/ (по умолчанию zsh-completion)
#   --tag <tag>        dist-tag (по умолчанию latest)
#   --access <level>   public | restricted (по умолчанию public)
#   --no-publish       только собрать и показать содержимое
#   --dry-run          npm publish --dry-run: без загрузки и без авторизации
#   --force            публиковать, даже если версия уже есть в реестре
#   -h, --help         эта справка
#
# Коды возврата:
#   0  успех
#   2  ошибка использования или валидации
#   3  npm завершился с ошибкой
#
# Требует zsh, node/npm и доступ в сеть для публикации. Скрипт не делает git
# commit и не меняет версию в package.json — это остаётся за релизным процессом.

emulate -L zsh
setopt pipe_fail

typeset -g SCRIPT_NAME=${0:t}
typeset -g PROJECT_ROOT=${0:A:h:h}

# ---------------------------------------------------------------------------
# Настройка
# ---------------------------------------------------------------------------

typeset -g SKILL=zsh-completion
typeset -g PACKAGE=''
typeset -g VERSION=''
typeset -g TAG=latest
typeset -g ACCESS=public
typeset -gi DO_PUBLISH=1
typeset -gi DRY_RUN=0
typeset -gi FORCE=0
typeset -g OUT_DIR=''

__usage() {
  print -r -- "usage: $SCRIPT_NAME [--skill <name>] [--tag <tag>]"
  print -r -- "       [--access public|restricted] [--no-publish] [--dry-run] [--force]"
}

__die() {
  print -u2 "FAIL: $*"
  return 2
}

__parse_args() {
  while (( $# )); do
    case $1 in
      --skill)  (( $# >= 2 )) || { __usage >&2; return 2 }; SKILL=$2; shift 2 ;;
      --tag)    (( $# >= 2 )) || { __usage >&2; return 2 }; TAG=$2; shift 2 ;;
      --access) (( $# >= 2 )) || { __usage >&2; return 2 }; ACCESS=$2; shift 2 ;;
      --no-publish) DO_PUBLISH=0; shift ;;
      --dry-run)    DRY_RUN=1; shift ;;
      --force)      FORCE=1; shift ;;
      -h|--help)    __usage; return 76 ;;
      *)
        print -u2 "unknown option: $1"
        __usage >&2
        return 2
        ;;
    esac
  done
  return 0
}

# ---------------------------------------------------------------------------
# Вспомогательные функции
# ---------------------------------------------------------------------------

__metadata_version() {
  # Версия из SKILL.md: metadata: version: "x.y.z".
  local file=$1
  sed -n 's/^[[:space:]]\{1,\}version:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' \
    "$file" | head -1
}

__pkg_field() {
  # __pkg_field <dir> <field> — значение поля package.json; пусто, если нет.
  local dir=$1 field=$2 value
  value=$( cd "$dir" && node -p "const v=require('./package.json').$field; v === undefined ? '' : String(v)" 2>/dev/null ) || return 1
  print -r -- "$value"
}

__is_semver() {
  [[ $1 =~ '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$' ]]
}

# ---------------------------------------------------------------------------
# Сборка
# ---------------------------------------------------------------------------

__build() {
  local skill_dir=$PROJECT_ROOT/skills/$SKILL
  local out_dir=$PROJECT_ROOT/.tmp/npm/$SKILL

  if [[ ! -d $skill_dir ]]; then
    __die "skill not found: skills/$SKILL"
    return 2
  fi
  if [[ ! -f $skill_dir/SKILL.md ]]; then
    __die "missing SKILL.md in skills/$SKILL"
    return 2
  fi
  if [[ ! -f $skill_dir/package.json ]]; then
    __die "missing package.json in skills/$SKILL; metadata is not generated"
    return 2
  fi

  # Защита от rm -rf по неожиданному пути.
  if [[ $out_dir != "$PROJECT_ROOT/.tmp/npm/"* ]]; then
    __die "refusing to clean unexpected build dir: $out_dir"
    return 2
  fi
  rm -rf -- "$out_dir"
  mkdir -p -- "$out_dir"

  print -r -- "==> copying skills/$SKILL -> ${out_dir#$PROJECT_ROOT/}"
  cp -R "$skill_dir/." "$out_dir/"

  # Мусор macOS и git не должен попадать в tarball.
  find "$out_dir" -name '.DS_Store' -type f -delete
  find "$out_dir" -name '._*' -type f -delete
  rm -rf -- "$out_dir/.git"

  PACKAGE=$(__pkg_field "$out_dir" name) || {
    __die "cannot read name from skills/$SKILL/package.json"
    return 2
  }
  VERSION=$(__pkg_field "$out_dir" version) || {
    __die "cannot read version from skills/$SKILL/package.json"
    return 2
  }
  if [[ -z $PACKAGE ]]; then
    __die "package.json in skills/$SKILL has no name"
    return 2
  fi
  if [[ -z $VERSION ]]; then
    __die "package.json in skills/$SKILL has no version"
    return 2
  fi
  if ! __is_semver "$VERSION"; then
    __die "invalid semver in package.json: $VERSION"
    return 2
  fi

  local skill_version
  skill_version=$(__metadata_version "$skill_dir/SKILL.md")
  if [[ -n $skill_version && $skill_version != $VERSION ]]; then
    print -r -- "warn: package.json version $VERSION != SKILL.md metadata.version $skill_version"
  fi

  local files_field
  files_field=$(__pkg_field "$out_dir" files)
  if [[ -z $files_field ]]; then
    print -r -- "warn: no files field in package.json; tarball is not restricted"
  fi

  if [[ ! -s $out_dir/README.md ]]; then
    print -r -- "warn: README.md is empty, generating a package README"
    __write_readme "$out_dir"
  fi

  if [[ ! -f $out_dir/LICENSE ]]; then
    print -r -- "warn: no LICENSE in skills/$SKILL"
  fi

  OUT_DIR=$out_dir
}

__write_readme() {
  local dir=$1 desc
  desc=$(__pkg_field "$dir" description)
  [[ -n $desc ]] || desc=$PACKAGE
  {
    print -r -- "# $SKILL"
    print -r --
    print -r -- "$desc"
    print -r --
    print -r -- "## Install"
    print -r --
    print -r -- '```sh'
    print -r -- "npm install $PACKAGE"
    print -r -- '```'
    print -r --
    print -r -- "После установки скилл лежит в \`node_modules/$PACKAGE\`."
    print -r -- "Точка входа — \`SKILL.md\`, скрипты — в \`scripts/\`."
  } > "$dir/README.md"
}

# ---------------------------------------------------------------------------
# Публикация
# ---------------------------------------------------------------------------

__validate_registry() {
  local exists
  exists=$(npm view "$PACKAGE@$VERSION" version 2>/dev/null || true)
  if [[ -n $exists ]]; then
    if (( FORCE )); then
      print -r -- "warn: $PACKAGE@$VERSION already exists, continuing (--force)"
    else
      __die "$PACKAGE@$VERSION already published; bump the version or pass --force"
      return 2
    fi
  fi
}

__check_auth() {
  if npm whoami >/dev/null 2>&1; then
    return 0
  fi
  if (( DRY_RUN )); then
    print -r -- "warn: not logged in to npm; --dry-run does not upload"
    return 0
  fi
  __die "not logged in to npm; run: npm login"
  return 2
}

__publish() {
  local pack_out
  if ! pack_out=$( cd "$OUT_DIR" && npm pack --dry-run 2>&1 ); then
    print -u2 -- "$pack_out"
    __die "npm pack --dry-run failed"
    return 3
  fi
  print -r -- "==> package contents"
  print -r -- "$pack_out" | sed -n '/^npm notice [0-9]/p'

  if (( ! DO_PUBLISH )); then
    print -r -- "ok: built $PACKAGE@$VERSION (publish skipped)"
    return 0
  fi

  __validate_registry || return $?
  __check_auth || return $?

  local -a args=(publish --access "$ACCESS" --tag "$TAG")
  (( DRY_RUN )) && args+=(--dry-run)

  print -r -- "==> npm ${args[*]}"
  if ! ( cd "$OUT_DIR" && npm "${args[@]}" ); then
    __die "npm publish failed"
    return 3
  fi

  if (( DRY_RUN )); then
    print -r -- "ok: dry-run for $PACKAGE@$VERSION"
  else
    print -r -- "ok: published $PACKAGE@$VERSION (tag $TAG)"
  fi
}

# ---------------------------------------------------------------------------
# Точка входа
# ---------------------------------------------------------------------------

__main() {
  __parse_args "$@"
  local rc=$?
  (( rc == 76 )) && return 0
  (( rc == 0 )) || return 2

  if ! command -v npm >/dev/null 2>&1 || ! command -v node >/dev/null 2>&1; then
    __die "npm and node are required"
    return 2
  fi

  __build || return $?
  __publish || return $?
}

__main "$@"
