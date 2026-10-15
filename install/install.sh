#!/usr/bin/env bash
# Instala y activa en Claude Code los mods de la carpeta mods/ del repositorio.
# Ejecuta ./install.sh --help para ver las opciones.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODS_SRC="$(cd "$SCRIPT_DIR/../mods" && pwd)"

usage() {
  cat <<'EOF'
Usage: install.sh [options] [mod ...]

Installs and enables the given mods; with no names, every mod in the repository.

Options:
  --target TARGET   local (default): Claude on this system
                    windows: Claude on Windows (from WSL or Git Bash)
                    wsl:     Claude on WSL (from WSL or Git Bash)
                    both:    Windows and WSL at once
  --distro NAME     WSL distribution (from Git Bash; defaults to the default one)
  --list            lists the repository mods and their status
  --uninstall       disables and removes the given mods (with no names, every repository mod)
  -h, --help        shows this help
EOF
}

fail() { echo "Error: $*" >&2; exit 1; }

TARGET=local
DISTRO=
ACTION=install
NESTED=0
MODS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --target) [ $# -ge 2 ] || fail "--target needs a value"; TARGET="$2"; shift 2 ;;
    --distro) [ $# -ge 2 ] || fail "--distro needs a value"; DISTRO="$2"; shift 2 ;;
    --list) ACTION=list; shift ;;
    --uninstall) ACTION=uninstall; shift ;;
    --nested) NESTED=1; shift ;;  # uso interno: llamada desde install.ps1
    -h|--help) usage; exit 0 ;;
    -*) fail "unknown option: $1 (see --help)" ;;
    *) MODS+=("$1"); shift ;;
  esac
done
case "$TARGET" in local|windows|wsl|both) ;; *) fail "invalid target: $TARGET (local, windows, wsl or both)" ;; esac

case "$(uname -s)" in
  Linux) if grep -qi microsoft /proc/version 2>/dev/null; then SYSTEM=wsl; else SYSTEM=linux; fi ;;
  Darwin) SYSTEM=macos ;;
  MINGW*|MSYS*|CYGWIN*) SYSTEM=gitbash ;;
  *) SYSTEM=other ;;
esac

# Argumentos equivalentes para install.ps1
ps_args() {
  local args=(-Target "$1")
  [ -n "$DISTRO" ] && args+=(-Distro "$DISTRO")
  [ "$ACTION" = list ] && args+=(-List)
  [ "$ACTION" = uninstall ] && args+=(-Uninstall)
  printf '%s\0' "${args[@]}" ${MODS[@]+"${MODS[@]}"}
}

# Git Bash corre sobre Windows: todo el trabajo lo hace install.ps1
if [ "$SYSTEM" = gitbash ]; then
  command -v powershell.exe >/dev/null || fail "powershell.exe not found"
  mapfile -d '' ARGS < <(ps_args "$TARGET")
  exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$SCRIPT_DIR/install.ps1")" "${ARGS[@]}"
fi

# Destinos de esta ejecución
DO_LOCAL=0
DO_WINDOWS=0
case "$TARGET" in
  local) DO_LOCAL=1 ;;
  wsl) [ "$SYSTEM" = wsl ] || fail "--target wsl only works from WSL, Git Bash or PowerShell on Windows"; DO_LOCAL=1 ;;
  windows) [ "$SYSTEM" = wsl ] || fail "--target windows only works from WSL or Git Bash"; DO_WINDOWS=1 ;;
  both) [ "$SYSTEM" = wsl ] || fail "--target both only works from WSL, Git Bash or PowerShell on Windows"; DO_LOCAL=1; DO_WINDOWS=1 ;;
esac

# Mods disponibles: subcarpetas de mods/ con .claude-plugin/plugin.json
AVAILABLE=()
for d in "$MODS_SRC"/*/; do
  [ -f "$d.claude-plugin/plugin.json" ] && AVAILABLE+=("$(basename "$d")")
done
[ ${#AVAILABLE[@]} -gt 0 ] || fail "no mods found in $MODS_SRC"
if [ ${#MODS[@]} -eq 0 ]; then
  MODS=("${AVAILABLE[@]}")
else
  for m in "${MODS[@]}"; do
    [[ " ${AVAILABLE[*]} " == *" $m "* ]] || fail "mod '$m' not found in $MODS_SRC (available: ${AVAILABLE[*]})"
  done
fi

# Comprobaciones previas, para no dejar nada a medias
if [ $DO_LOCAL = 1 ]; then
  command -v python3 >/dev/null || fail "python3 is required to edit settings.json"
fi
if [ $DO_WINDOWS = 1 ]; then
  command -v powershell.exe >/dev/null || fail "powershell.exe not found; is Windows interop enabled in WSL?"
fi

# Lee y modifica settings.json. Acciones: add, remove, list.
settings_tool() {
  python3 -I - "$@" <<'EOF'
import json, os, sys

action, settings, claude_dir, use_tilde, mods_src, *names = sys.argv[1:]

def ref(name):
    return f'~/.claude/mods/{name}' if use_tilde == '1' else os.path.join(claude_dir, 'mods', name)

def norm(path):
    return os.path.normpath(os.path.abspath(os.path.expanduser(path)))

cfg = {}
if os.path.exists(settings):
    with open(settings, encoding='utf-8') as f:
        text = f.read().strip()
    if text:
        cfg = json.loads(text)
env = cfg.get('env') or {}
dirs = [d for d in str(env.get('CLAUDE_CODE_PLUGIN_DIRS', '')).split(':') if d]

if action == 'list':
    active = {norm(d) for d in dirs}
    for name in names:
        with open(os.path.join(mods_src, name, '.claude-plugin', 'plugin.json'), encoding='utf-8') as f:
            meta = json.load(f)
        installed = os.path.isdir(os.path.join(claude_dir, 'mods', name))
        if installed and norm(ref(name)) in active:
            state = 'installed, enabled'
        elif installed:
            state = 'installed, disabled'
        else:
            state = 'not installed'
        print(f"  {name:<20} {meta.get('version', '?'):<8} {state:<22} {meta.get('description', '')}")
    sys.exit()

targets = {norm(ref(name)) for name in names}
dirs = [d for d in dirs if norm(d) not in targets]
if action == 'add':
    dirs += [ref(name) for name in names]
if dirs:
    env['CLAUDE_CODE_PLUGIN_DIRS'] = ':'.join(dirs)
else:
    env.pop('CLAUDE_CODE_PLUGIN_DIRS', None)
if env:
    cfg['env'] = env
else:
    cfg.pop('env', None)

os.makedirs(os.path.dirname(settings), exist_ok=True)
with open(settings, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write('\n')
EOF
}

run_local() {
  local claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local use_tilde=1
  [ -n "${CLAUDE_CONFIG_DIR:-}" ] && use_tilde=0
  local settings="$claude_dir/settings.json"
  local label
  case "$SYSTEM" in
    wsl) label="WSL (${WSL_DISTRO_NAME:-?})" ;;
    macos) label=macOS ;;
    *) label=Linux ;;
  esac

  echo "== $label: $claude_dir"
  if [ "$ACTION" = list ]; then
    settings_tool list "$settings" "$claude_dir" "$use_tilde" "$MODS_SRC" "${MODS[@]}"
    return
  fi

  if [ -f "$settings" ]; then
    mkdir -p "$claude_dir/backups"
    local backup="$claude_dir/backups/settings.json.claude-mods.$(date +%Y%m%d-%H%M%S)"
    cp "$settings" "$backup"
    echo "  settings.json backed up to $backup"
  fi

  local m
  for m in "${MODS[@]}"; do
    local dest="$claude_dir/mods/$m"
    local keep=
    # Los tipos que genera Claude Code para desarrollar el mod se conservan al reinstalar
    if [ "$ACTION" = install ] && [ -d "$dest/.claude-plugin/types" ]; then
      keep="$(mktemp -d)"
      mv "$dest/.claude-plugin/types" "$keep/"
    fi
    rm -rf "$dest"
    if [ "$ACTION" = install ]; then
      mkdir -p "$claude_dir/mods"
      cp -R "$MODS_SRC/$m" "$dest"
      if [ -n "$keep" ]; then
        mv "$keep/types" "$dest/.claude-plugin/"
        rmdir "$keep"
      fi
      echo "  installed: $m"
    else
      echo "  uninstalled: $m"
    fi
  done
  if [ "$ACTION" = install ]; then
    settings_tool add "$settings" "$claude_dir" "$use_tilde" "$MODS_SRC" "${MODS[@]}"
  else
    settings_tool remove "$settings" "$claude_dir" "$use_tilde" "$MODS_SRC" "${MODS[@]}"
  fi
}

run_windows() {
  mapfile -d '' ARGS < <(ps_args local)
  ARGS+=(-Nested)
  # Desde /mnt/c para que Windows no arranque en una ruta UNC de WSL
  if ! (cd /mnt/c && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$SCRIPT_DIR/install.ps1")" "${ARGS[@]}") |
    tr -d '\r'; then
    fail "the operation on Windows failed"
  fi
}

if [ $DO_LOCAL = 1 ]; then run_local; fi
if [ $DO_WINDOWS = 1 ]; then run_windows; fi

if [ "$ACTION" != list ] && [ $NESTED = 0 ]; then
  echo
  echo "Restart Claude Code to apply the changes."
fi
