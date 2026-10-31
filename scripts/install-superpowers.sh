#!/usr/bin/env bash
# Instala as skills do Superpowers (https://github.com/obra/superpowers, licença MIT).
#
# Modos:
#   plugin  (padrão)  mostra os comandos para instalar como plugin no Claude Code
#                     (use em um terminal com o CLI; o comando /plugin não existe em
#                     todos os ambientes, por exemplo na sessão web).
#   skills            copia as skills para uma pasta de skills (sem o hook de início de
#                     sessão, que só o plugin instala).
#
# Uso:
#   scripts/install-superpowers.sh plugin
#   scripts/install-superpowers.sh skills                 # em .claude/skills do projeto
#   scripts/install-superpowers.sh skills --user          # em ~/.claude/skills
#   scripts/install-superpowers.sh skills --target DIR    # em outra pasta
#   opções: --ref TAG|COMMIT (padrão v7.0.1)  --force  --dry-run
set -euo pipefail

REPO_URL="https://github.com/obra/superpowers.git"
REF="v7.0.1"
MODE="${1:-plugin}"
[ $# -gt 0 ] && shift
TARGET=""
FORCE=0
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --user)    TARGET="$HOME/.claude/skills" ;;
    --target)  TARGET="${2:?--target exige um diretório}"; shift ;;
    --ref)     REF="${2:?--ref exige uma tag ou commit}"; shift ;;
    --force)   FORCE=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "Opção desconhecida: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$MODE" = "plugin" ]; then
  cat <<'EOF'
Dentro do Claude Code (CLI ou app desktop), execute:

  /plugin marketplace add obra/superpowers
  /plugin install superpowers@superpowers-dev

Depois reinicie a sessão. O plugin instala as skills e o hook de início de sessão.
EOF
  exit 0
fi

[ "$MODE" = "skills" ] || { echo "Modo inválido: $MODE (use plugin ou skills)" >&2; exit 2; }

if [ -z "$TARGET" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  TARGET="$ROOT/.claude/skills"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Baixando obra/superpowers @ $REF ..."
git clone --quiet "$REPO_URL" "$WORK/repo"
git -C "$WORK/repo" checkout --quiet "$REF"
COMMIT="$(git -C "$WORK/repo" rev-parse --short HEAD)"

SRC="$WORK/repo/skills"
[ -d "$SRC" ] || { echo "Pasta skills/ não encontrada em $REF" >&2; exit 1; }

echo "Destino: $TARGET"
[ "$DRY" -eq 1 ] || mkdir -p "$TARGET"

installed=0; skipped=0
for dir in "$SRC"/*/; do
  name="$(basename "$dir")"
  [ -f "$dir/SKILL.md" ] || continue
  dest="$TARGET/$name"
  if [ -e "$dest" ] && [ "$FORCE" -ne 1 ]; then
    echo "  pulou  $name (já existe; use --force para substituir)"
    skipped=$((skipped + 1))
    continue
  fi
  if [ "$DRY" -eq 1 ]; then
    echo "  instalaria  $name"
  else
    rm -rf "$dest"
    cp -R "$dir" "$dest"
    echo "  ok     $name"
  fi
  installed=$((installed + 1))
done

if [ "$DRY" -ne 1 ]; then
  cp "$WORK/repo/LICENSE" "$TARGET/SUPERPOWERS-LICENSE" 2>/dev/null || true
  printf 'obra/superpowers %s (%s)\n' "$REF" "$COMMIT" > "$TARGET/SUPERPOWERS-VERSION"
fi

echo "Concluído: $installed instalada(s), $skipped ignorada(s). Reinicie a sessão para carregar."
