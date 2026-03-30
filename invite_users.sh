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

# ─── FUNCIÓN: obtener todos los miembros de una org (con paginación) ──────────
get_members() {
  local ORG=$1
  local PAGE=1
  local MEMBERS=()

  while true; do
    HTTP_CODE=$(curl -s -o /tmp/members_response.json -w "%{http_code}" "${HEADERS[@]}" \
      "$API/orgs/$ORG/members?per_page=100&page=$PAGE")

    if [[ "$HTTP_CODE" != "200" ]]; then
      MSG=$(jq -r '.message // "Error desconocido"' /tmp/members_response.json 2>/dev/null)
      echo "❌ Error al obtener miembros de '$ORG' (HTTP $HTTP_CODE): $MSG" >&2
      break
    fi

    NAMES=$(jq -r '.[].login' /tmp/members_response.json 2>/dev/null)
    [[ -z "$NAMES" ]] && break

    while IFS= read -r name; do
      MEMBERS+=("$name")
    done <<< "$NAMES"

    ((PAGE++))
  done

  echo "${MEMBERS[@]}"
}

# ─── FUNCIÓN: obtener todos los teams de una org (con paginación) ─────────────
get_teams() {
  local ORG=$1
  local PAGE=1

  while true; do
    HTTP_CODE=$(curl -s -o /tmp/teams_response.json -w "%{http_code}" "${HEADERS[@]}" \
      "$API/orgs/$ORG/teams?per_page=100&page=$PAGE")

    if [[ "$HTTP_CODE" != "200" ]]; then
      MSG=$(jq -r '.message // "Error desconocido"' /tmp/teams_response.json 2>/dev/null)
      echo "❌ Error al obtener teams de '$ORG' (HTTP $HTTP_CODE): $MSG" >&2
      break
    fi

    COUNT=$(jq 'length' /tmp/teams_response.json 2>/dev/null)
    [[ "$COUNT" == "0" || -z "$COUNT" ]] && break

    jq -r '.[] | "\(.slug)|\(.name)"' /tmp/teams_response.json

    ((PAGE++))
  done
}

# ─── FUNCIÓN: obtener miembros de un team (con paginación) ────────────────────
get_team_members() {
  local ORG=$1
  local TEAM_SLUG=$2
  local PAGE=1

  while true; do
    HTTP_CODE=$(curl -s -o /tmp/team_members_response.json -w "%{http_code}" "${HEADERS[@]}" \
      "$API/orgs/$ORG/teams/$TEAM_SLUG/members?per_page=100&page=$PAGE")

    if [[ "$HTTP_CODE" != "200" ]]; then
      MSG=$(jq -r '.message // "Error desconocido"' /tmp/team_members_response.json 2>/dev/null)
      echo "❌ Error al obtener miembros del team '$TEAM_SLUG' en '$ORG' (HTTP $HTTP_CODE): $MSG" >&2
      break
    fi

    COUNT=$(jq 'length' /tmp/team_members_response.json 2>/dev/null)
    [[ "$COUNT" == "0" || -z "$COUNT" ]] && break

    jq -r '.[].login' /tmp/team_members_response.json

    ((PAGE++))
  done
}

# ─── FUNCIÓN: comprobar si un team existe en el destino ───────────────────────
team_exists_in_target() {
  local TEAM_SLUG=$1
  local STATUS

  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${HEADERS[@]}" \
    "$API/orgs/$TARGET_ORG/teams/$TEAM_SLUG")

  [[ "$STATUS" == "200" ]]
}

# ─── INICIO ───────────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
  echo "🔍 Modo DRY-RUN activado. No se ejecutarán cambios reales."
fi

echo ""
echo "📋 Obteniendo miembros de $SOURCE_ORG..."
SOURCE_MEMBERS_STR=$(get_members "$SOURCE_ORG")
read -ra SOURCE_MEMBERS <<< "$SOURCE_MEMBERS_STR"

echo "📋 Obteniendo miembros de $TARGET_ORG..."
TARGET_MEMBERS_STR=$(get_members "$TARGET_ORG")
read -ra TARGET_MEMBERS <<< "$TARGET_MEMBERS_STR"

echo "✅ Miembros en origen: ${#SOURCE_MEMBERS[@]}"
echo "✅ Miembros en destino: ${#TARGET_MEMBERS[@]}"

# ─── INVITAR USUARIOS QUE NO ESTÁN EN DESTINO ────────────────────────────────
INVITED=0
SKIPPED_USERS=0

echo ""
echo "👥 Procesando usuarios..."

for USER in "${SOURCE_MEMBERS[@]}"; do
  if [[ " ${TARGET_MEMBERS[*]} " =~ " $USER " ]]; then
    echo "⏭️  Saltando '$USER' (ya está en $TARGET_ORG)"
    ((SKIPPED_USERS++))
  else
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "🔍 [DRY-RUN] Invitaría a '$USER' a $TARGET_ORG"
      ((INVITED++))
    else
      echo "🚀 Invitando a '$USER' a $TARGET_ORG..."
      HTTP_CODE=$(curl -s -o /tmp/invite_response.json -w "%{http_code}" "${HEADERS[@]}" \
        -X POST "$API/orgs/$TARGET_ORG/invitations" \
        -d "{\"login\":\"$USER\",\"role\":\"direct_member\"}")

      if [[ "$HTTP_CODE" == "201" ]]; then
        echo "   ✅ '$USER' invitado correctamente"
        ((INVITED++))
      else
        MSG=$(jq -r '.message // "Error desconocido"' /tmp/invite_response.json 2>/dev/null)
        echo "   ❌ Error invitando a '$USER' (HTTP $HTTP_CODE): $MSG"
      fi
    fi
  fi
done

# ─── GESTIÓN DE TEAMS ────────────────────────────────────────────────────────
TEAMS_CREATED=0
TEAMS_SKIPPED=0
MEMBERS_ASSIGNED=0

echo ""
echo "📋 Obteniendo teams de $SOURCE_ORG..."

TEAMS_DATA=$(get_teams "$SOURCE_ORG")

if [[ -z "$TEAMS_DATA" ]]; then
  echo "⏭️  No se encontraron teams en $SOURCE_ORG"
else
  while IFS='|' read -r TEAM_SLUG TEAM_NAME; do
    [[ -z "$TEAM_SLUG" ]] && continue

    echo ""
    echo "🔧 Procesando team: $TEAM_NAME ($TEAM_SLUG)"

    if team_exists_in_target "$TEAM_SLUG"; then
      echo "   ⏭️  El team '$TEAM_SLUG' ya existe en $TARGET_ORG"
      ((TEAMS_SKIPPED++))
    else
      if [[ "$DRY_RUN" == "true" ]]; then
        echo "   🔍 [DRY-RUN] Crearía el team '$TEAM_NAME' en $TARGET_ORG"
        ((TEAMS_CREATED++))
      else
        echo "   🚀 Creando team '$TEAM_NAME' en $TARGET_ORG..."
        HTTP_CODE=$(curl -s -o /tmp/team_response.json -w "%{http_code}" "${HEADERS[@]}" \
          -X POST "$API/orgs/$TARGET_ORG/teams" \
          -d "{\"name\":\"$TEAM_NAME\",\"privacy\":\"closed\"}")

        if [[ "$HTTP_CODE" == "201" ]]; then
          echo "   ✅ Team '$TEAM_NAME' creado correctamente"
          ((TEAMS_CREATED++))
        else
          MSG=$(jq -r '.message // "Error desconocido"' /tmp/team_response.json 2>/dev/null)
          echo "   ❌ Error creando team '$TEAM_NAME' (HTTP $HTTP_CODE): $MSG"
          continue
        fi
      fi
    fi

    # Obtener miembros del team en origen y asignarlos en destino
    echo "   📋 Obteniendo miembros del team '$TEAM_SLUG' en $SOURCE_ORG..."
    TEAM_MEMBERS=$(get_team_members "$SOURCE_ORG" "$TEAM_SLUG")

    if [[ -z "$TEAM_MEMBERS" ]]; then
      echo "   ⏭️  El team '$TEAM_SLUG' no tiene miembros en $SOURCE_ORG"
      continue
    fi

    while IFS= read -r MEMBER; do
      [[ -z "$MEMBER" ]] && continue

      if [[ "$DRY_RUN" == "true" ]]; then
        echo "   🔍 [DRY-RUN] Añadiría a '$MEMBER' al team '$TEAM_SLUG' en $TARGET_ORG"
        ((MEMBERS_ASSIGNED++))
      else
        echo "   🚀 Añadiendo '$MEMBER' al team '$TEAM_SLUG' en $TARGET_ORG..."
        HTTP_CODE=$(curl -s -o /tmp/member_response.json -w "%{http_code}" "${HEADERS[@]}" \
          -X PUT "$API/orgs/$TARGET_ORG/teams/$TEAM_SLUG/memberships/$MEMBER" \
          -d "{\"role\":\"member\"}")

        if [[ "$HTTP_CODE" == "200" ]]; then
          echo "      ✅ '$MEMBER' añadido al team '$TEAM_SLUG'"
          ((MEMBERS_ASSIGNED++))
        else
          MSG=$(jq -r '.message // "Error desconocido"' /tmp/member_response.json 2>/dev/null)
          echo "      ❌ Error añadiendo '$MEMBER' al team '$TEAM_SLUG' (HTTP $HTTP_CODE): $MSG"
        fi
      fi
    done <<< "$TEAM_MEMBERS"

  done <<< "$TEAMS_DATA"
fi

# ─── RESUMEN ─────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "📊 RESUMEN FINAL:"
echo "   🚀 Usuarios invitados:    $INVITED"
echo "   ⏭️  Usuarios saltados:     $SKIPPED_USERS"
echo "   🔧 Teams creados:         $TEAMS_CREATED"
echo "   ⏭️  Teams ya existentes:   $TEAMS_SKIPPED"
echo "   👤 Miembros asignados:    $MEMBERS_ASSIGNED"
echo "─────────────────────────────────────────"
