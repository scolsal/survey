#!/bin/bash

# ─── CONFIGURACIÓN ────────────────────────────────────────────────────────────
# Estas variables pueden sobreescribirse mediante variables de entorno:
#   export SOURCE_ORG="org-origen" TARGET_ORG="org-destino" TOKEN="tu-PAT"
SOURCE_ORG="${SOURCE_ORG:-org-origen}"
TARGET_ORG="${TARGET_ORG:-org-destino}"
TOKEN="${TOKEN:-}"
DRY_RUN="${DRY_RUN:-false}"

# Validar que las variables obligatorias estén definidas
if [[ -z "$SOURCE_ORG" || "$SOURCE_ORG" == "org-origen" ]]; then
  echo "❌ ERROR: Define la variable SOURCE_ORG con el nombre de la organización origen."
  exit 1
fi
if [[ -z "$TARGET_ORG" || "$TARGET_ORG" == "org-destino" ]]; then
  echo "❌ ERROR: Define la variable TARGET_ORG con el nombre de la organización destino."
  exit 1
fi
if [[ -z "$TOKEN" ]]; then
  echo "❌ ERROR: Define la variable TOKEN con tu Personal Access Token de GitHub."
  exit 1
fi

API="https://api.github.com"
HEADERS=(
  -H "Accept: application/vnd.github+json"
  -H "Authorization: Bearer $TOKEN"
  -H "X-GitHub-Api-Version: 2022-11-28"
)

# ─── FUNCIÓN: obtener todos los repos de una org (con paginación) ─────────────
get_repos() {
  local ORG=$1
  local PAGE=1
  local REPOS=()

  while true; do
    HTTP_CODE=$(curl -s -o /tmp/repos_response.json -w "%{http_code}" "${HEADERS[@]}" \
      "$API/orgs/$ORG/repos?per_page=100&page=$PAGE")

    if [[ "$HTTP_CODE" != "200" ]]; then
      MSG=$(jq -r '.message // "Error desconocido"' /tmp/repos_response.json 2>/dev/null)
      echo "❌ Error al obtener repositorios de '$ORG' (HTTP $HTTP_CODE): $MSG" >&2
      break
    fi

    NAMES=$(jq -r '.[].name' /tmp/repos_response.json 2>/dev/null)
    [[ -z "$NAMES" ]] && break

    while IFS= read -r name; do
      REPOS+=("$name")
    done <<< "$NAMES"

    ((PAGE++))
  done

  echo "${REPOS[@]}"
}

# ─── INICIO ───────────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
  echo "🔍 Modo DRY-RUN activado. No se ejecutarán cambios reales."
fi

echo ""
echo "📋 Obteniendo repositorios de $SOURCE_ORG..."
SOURCE_REPOS_STR=$(get_repos "$SOURCE_ORG")
read -ra SOURCE_REPOS <<< "$SOURCE_REPOS_STR"

echo "📋 Obteniendo repositorios de $TARGET_ORG..."
TARGET_REPOS_STR=$(get_repos "$TARGET_ORG")
read -ra TARGET_REPOS <<< "$TARGET_REPOS_STR"

echo "✅ Repositorios en origen:  ${#SOURCE_REPOS[@]}"
echo "✅ Repositorios en destino: ${#TARGET_REPOS[@]}"

# ─── MIGRAR REPOS QUE NO EXISTAN EN DESTINO ──────────────────────────────────
MIGRATED=0
SKIPPED=0
ERRORS=0

echo ""
echo "🚀 Procesando repositorios..."

for REPO in "${SOURCE_REPOS[@]}"; do
  if [[ " ${TARGET_REPOS[*]} " =~ " $REPO " ]]; then
    echo "⏭️  Saltando '$REPO' (ya existe en $TARGET_ORG)"
    ((SKIPPED++))
  else
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "🔍 [DRY-RUN] Transferiría '$REPO' de $SOURCE_ORG a $TARGET_ORG"
      ((MIGRATED++))
    else
      echo "🚀 Transfiriendo '$REPO' de $SOURCE_ORG a $TARGET_ORG..."
      HTTP_CODE=$(curl -s -o /tmp/transfer_response.json -w "%{http_code}" "${HEADERS[@]}" \
        -X POST "$API/repos/$SOURCE_ORG/$REPO/transfers" \
        -d "{\"new_owner\":\"$TARGET_ORG\"}")

      if [[ "$HTTP_CODE" == "202" ]]; then
        echo "   ✅ '$REPO' transferido correctamente (en proceso)"
        ((MIGRATED++))
      else
        MSG=$(jq -r '.message // "Error desconocido"' /tmp/transfer_response.json 2>/dev/null)
        echo "   ❌ Error transfiriendo '$REPO' (HTTP $HTTP_CODE): $MSG"
        ((ERRORS++))
      fi
    fi
  fi
done

# ─── RESUMEN ─────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "📊 RESUMEN FINAL:"
echo "   🚀 Migrados:              $MIGRATED"
echo "   ⏭️  Saltados:              $SKIPPED"
echo "   ❌ Errores:               $ERRORS"
echo "   📁 Total origen:          ${#SOURCE_REPOS[@]}"
echo "─────────────────────────────────────────"
