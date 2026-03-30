# Scripts de Migración de GitHub Organizations

Scripts de automatización en Bash para facilitar la migración de una organización de GitHub a otra organización ya existente en GitHub Enterprise Cloud.

## 📋 Descripción

Este repositorio contiene dos scripts:

- **`invite_users.sh`**: Comprueba e invita a los usuarios de la organización origen a la organización destino, y replica la estructura de teams con sus miembros.
- **`migrate_repos.sh`**: Migra los repositorios de la organización origen a la organización destino, transfiriendo únicamente los que no existan ya en el destino.

La transferencia de repositorios conserva issues, pull requests, wikis, releases, webhooks, secretos, deploy keys, historial de commits y objetos Git LFS.

---

## 🔧 Prerrequisitos

- [`curl`](https://curl.se/) instalado en el sistema
- [`jq`](https://stedolan.github.io/jq/) instalado en el sistema (`brew install jq` / `apt install jq`)
- Un **Personal Access Token (PAT)** de GitHub con los siguientes permisos:
  - `admin:org` — para listar miembros, invitar usuarios, gestionar teams y transferir repositorios entre organizaciones
  - `repo` — para acceder a los repositorios privados y realizar transferencias

---

## ⚙️ Configuración

Las variables de configuración se pueden establecer de dos formas:

**Opción 1 — Variables de entorno (recomendado):**
```bash
export SOURCE_ORG="org-origen"
export TARGET_ORG="org-destino"
export TOKEN="tu-PAT-aqui"
export DRY_RUN=true  # opcional
./invite_users.sh
```

**Opción 2 — Editar el script directamente:**
```bash
SOURCE_ORG="org-origen"   # Nombre de la organización origen
TARGET_ORG="org-destino"  # Nombre de la organización destino
TOKEN="tu-PAT-aqui"       # Personal Access Token con permisos admin:org y repo
DRY_RUN=false             # Cambia a true para simular sin ejecutar cambios reales
```

Los scripts validarán que `SOURCE_ORG`, `TARGET_ORG` y `TOKEN` estén definidos antes de ejecutarse.

---

## 🚀 Uso

### Script 1: Invitar usuarios y crear teams (`invite_users.sh`)

Este script:
1. Obtiene todos los miembros de la organización origen y destino.
2. Invita a la organización destino a los usuarios que aún no pertenecen a ella.
3. Obtiene todos los teams de la organización origen.
4. Crea en la organización destino los teams que no existan.
5. Asigna los miembros de cada team en la organización destino.

```bash
# Dar permisos de ejecución
chmod +x invite_users.sh

# Ejecutar
./invite_users.sh
```

### Script 2: Migrar repositorios (`migrate_repos.sh`)

Este script:
1. Obtiene todos los repositorios de la organización origen y destino.
2. Transfiere a la organización destino únicamente los repositorios que no existan en ella.

```bash
# Dar permisos de ejecución
chmod +x migrate_repos.sh

# Ejecutar
./migrate_repos.sh
```

---

## 🔍 Modo Dry-Run

Ambos scripts incluyen un **modo dry-run** que simula todas las acciones sin ejecutarlas realmente. Es muy recomendable utilizarlo antes de la ejecución en producción.

Para activarlo, cambia la variable al inicio del script:

```bash
DRY_RUN=true
```

En modo dry-run, el script mostrará exactamente qué usuarios se invitarían, qué teams se crearían y qué repositorios se transferirían, sin realizar ningún cambio.

---

## ⚠️ Advertencias importantes

- **Prueba primero con un caso real pero de bajo impacto**: ejecuta el script con un repositorio o usuario de prueba antes de lanzarlo sobre toda la organización.
- **Los packages de GitHub (ghcr.io)** no se transfieren automáticamente con el repositorio; deben migrarse manualmente.
- **Los GitHub Actions Artifacts** tienen retención limitada (90 días por defecto) y no se transfieren.
- **GitHub Pages**: los enlaces al repositorio se redirigen automáticamente, pero las propias GitHub Pages no se redirigen.
- La transferencia de repositorios es **asíncrona** (HTTP 202). Para repositorios con muchos objetos Git LFS, el proceso puede tardar unos minutos en completarse.
- Si la organización usa **SAML/SSO**, los usuarios invitados deberán autenticarse vía SSO antes de poder acceder. Este flujo no se puede automatizar completamente desde la API.
