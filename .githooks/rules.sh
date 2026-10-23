#!/bin/sh
# Reglas de ramas y commits del repositorio (ver CLAUDE.md). Las usan los hooks de .githooks/
# y el workflow .github/workflows/git-rules.yml.
#   rules.sh branch <rama>      comprueba el nombre de una rama
#   rules.sh message <archivo>  comprueba un mensaje de commit
set -eu

TYPES='feat|fix|docs|refactor|test|chore|ci'
MAX_SUBJECT=72

fail() {
  echo "Error: $1" >&2
  shift
  for line in "$@"; do echo "  $line" >&2; done
  exit 1
}

types_list() {
  echo "$TYPES" | sed 's/|/, /g'
}

check_branch() {
  [ "$1" != main ] ||
    fail "do not commit on main: create a branch first" \
      "git switch -c feat/short-description"
  printf '%s\n' "$1" | grep -Eq "^($TYPES)/[a-z0-9]+(-[a-z0-9]+)*\$" ||
    fail "branch '$1' does not follow type/description" \
      "types: $(types_list)" \
      "description in kebab-case, e.g. feat/faf-usage-meter-model" \
      "rename it with: git branch -m <new-name>"
}

check_message() {
  # Sin comentarios ni el diff de commit -v, como los quitará git al guardar el mensaje
  msg=$(sed '/^# -\{24\} >8 -\{24\}$/,$d' "$1" | git stripspace --strip-comments)
  # Vacío: git lo rechaza por su cuenta
  [ -n "$msg" ] || return 0
  subject=$(printf '%s\n' "$msg" | sed -n 1p)
  case "$subject" in
    # Mensajes que genera el propio git
    'Merge '* | 'Revert "'* | 'fixup! '* | 'squash! '* | 'amend! '*) return 0 ;;
  esac

  printf '%s\n' "$subject" | grep -Eq "^($TYPES)(\([a-z0-9]+(-[a-z0-9]+)*\))?!?: [^ ]" ||
    fail "the first line does not follow Conventional Commits: $subject" \
      "expected: type(scope): description, in Spanish; the scope is optional" \
      "types: $(types_list)" \
      "e.g. feat(faf-usage-meter): muestra el modelo en uso"
  # Caracteres, no bytes: se descartan los bytes de continuación de UTF-8
  length=$(printf '%s' "$subject" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' ')
  [ "$length" -le "$MAX_SUBJECT" ] ||
    fail "the first line has $length characters; the limit is $MAX_SUBJECT" \
      "move the details to the body, after a blank line"
  [ -z "$(printf '%s\n' "$msg" | sed -n 2p)" ] ||
    fail "leave a blank line between the first line and the body"
}

case "${1:-}" in
  branch) [ $# -eq 2 ] || fail "usage: rules.sh branch <name>"; check_branch "$2" ;;
  message) [ $# -eq 2 ] || fail "usage: rules.sh message <file>"; check_message "$2" ;;
  *) fail "usage: rules.sh branch <name> | rules.sh message <file>" ;;
esac
