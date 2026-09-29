#!/usr/bin/env bash
# Ejecuta la suite de Neovim en un entorno aislado: HOME y XDG_* temporales,
# así las pruebas nunca tocan proyectos, tema ni sesiones reales de agentes.
#
#   tests/run.sh                      toda la suite
#   tests/run.sh tests/spec/git_spec.lua   un solo archivo
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugins="${NVIM_TEST_PLUGINS:-$HOME/.local/share/nvim/lazy}"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

export NVIM_TEST_PLUGINS="$plugins"
export HOME="$sandbox/home"
export XDG_CONFIG_HOME="$sandbox/config"
export XDG_DATA_HOME="$sandbox/data"
export XDG_STATE_HOME="$sandbox/state"
export XDG_CACHE_HOME="$sandbox/cache"
export GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@example.com"
export GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

target="${1:-$repo/tests/spec}"
cd "$repo"
nvim --headless -u "$repo/tests/minimal_init.lua" \
  -c "PlenaryBustedDirectory $target { minimal_init = '$repo/tests/minimal_init.lua', sequential = true, timeout = 120000 }"
