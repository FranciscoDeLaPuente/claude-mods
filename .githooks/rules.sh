#!/bin/sh
# Reglas de ramas y commits del repositorio (ver CLAUDE.md). Las usan los hooks de .githooks/
# y el workflow .github/workflows/git-rules.yml.
#   rules.sh branch <rama>            comprueba el nombre de una rama
#   rules.sh message <archivo>        comprueba el mensaje que va a guardar git (hook commit-msg)
#   rules.sh message --raw <archivo>  comprueba un mensaje ya guardado, tal cual
#   rules.sh title <título>           comprueba el título de un PR: la primera línea del squash en main
#   rules.sh body <archivo>           comprueba la descripción de un PR
set -eu

TYPES='feat|fix|docs|refactor|test|chore|ci'
MAX_SUBJECT=72

fail() {
  echo "Error: $1" >&2
  shift
  for line in "$@"; do echo "  $line" >&2; done
  exit 1
}

usage() {
  fail "usage: rules.sh branch <name> | message [--raw] <file> | title <title> | body <file>"
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

# Formato y longitud de una primera línea, sin excepciones
check_subject() {
  printf '%s\n' "$1" | grep -Eq "^($TYPES)(\([a-z0-9]+(-[a-z0-9]+)*\))?!?: [^ ]" ||
    fail "the first line does not follow Conventional Commits: $1" \
      "expected: type(scope): description, in Spanish; the scope is optional" \
      "types: $(types_list)" \
      "e.g. feat(faf-usage-meter): muestra el modelo en uso"
  # Caracteres, no bytes: se descartan los bytes de continuación de UTF-8
  length=$(printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' ')
  [ "$length" -le "$MAX_SUBJECT" ] ||
    fail "the first line has $length characters; the limit is $MAX_SUBJECT" \
      "move the details to the body, after a blank line"
}

# Ni commits ni PR llevan firma de Claude: un trailer …-by: con Claude o anthropic.com, o una línea que
# empieza por "Generated with Claude Code" (con o sin 🤖 y enlace). Mencionarlo en una frase no es firmar.
check_unsigned() {
  signed=$(printf '%s\n' "$1" | grep -Ei '^[a-z-]+-by:.*(claude|anthropic\.com)|^[^a-z0-9]*generated with \[?claude code' | sed -n 1p)
  [ -z "$signed" ] ||
    fail "$2 is signed by Claude: $signed" \
      "remove the Co-Authored-By and Generated with Claude Code lines"
}

check_message() {
  [ -r "$2" ] || fail "cannot read the message file: $2"
  if [ "$1" = raw ]; then
    # Ya guardado: una línea que empieza por # es contenido, no un comentario
    msg=$(cat "$2")
    [ -n "$msg" ] || fail "the commit message is empty"
  else
    # Sin comentarios ni el diff de commit -v, como los quitará git al guardar el mensaje
    msg=$(sed '/^# -\{24\} >8 -\{24\}$/,$d' "$2" | git stripspace --strip-comments)
    # Vacío: git lo rechaza por su cuenta
    [ -n "$msg" ] || return 0
  fi
  check_unsigned "$msg" "the commit message"
  subject=$(printf '%s\n' "$msg" | sed -n 1p)
  case "$subject" in
    # Mensajes que genera el propio git
    'Merge '* | 'Revert "'* | 'fixup! '* | 'squash! '* | 'amend! '*) return 0 ;;
  esac

  check_subject "$subject"
  [ -z "$(printf '%s\n' "$msg" | sed -n 2p)" ] ||
    fail "leave a blank line between the first line and the body"
}

check_title() {
  [ -n "$1" ] || fail "the PR title is empty"
  check_subject "$1"
}

check_body() {
  [ -r "$1" ] || fail "cannot read the PR description file: $1"
  check_unsigned "$(cat "$1")" "the PR description"
}

case "${1:-}" in
  branch) [ $# -eq 2 ] || usage; check_branch "$2" ;;
  message)
    if [ $# -eq 3 ] && [ "$2" = --raw ]; then
      check_message raw "$3"
    elif [ $# -eq 2 ]; then
      check_message hook "$2"
    else
      usage
    fi
    ;;
  title) [ $# -eq 2 ] || usage; check_title "$2" ;;
  body) [ $# -eq 2 ] || usage; check_body "$2" ;;
  *) usage ;;
esac
