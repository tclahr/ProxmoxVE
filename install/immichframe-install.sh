#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tclahr
# License: MIT | https://github.com/tclahr/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/immichFrame/ImmichFrame

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# =============================================================================
# DEPENDENCIES - Only add app-specific dependencies here!
# Don't add: ca-certificates, curl, gnupg, git, build-essential (handled by build.func)
# =============================================================================

msg_info "Installing Dependencies"
$STD apk add --no-cache \
  bash \
  curl \
  git \
  icu-libs \
  krb5-libs \
  libgcc \
  libssl3 \
  libstdc++ \
  nodejs \
  npm \
  zlib
msg_ok "Installed Dependencies"

msg_info "Installing .NET SDK & ASP.NET Core Runtime"
# .NET 9 está disponível nos repositórios do Alpine 3.21
$STD apk add --no-cache \
  dotnet9-sdk \
  aspnetcore9-runtime
msg_ok ".NET SDK & ASP.NET Core Runtime Installed"

msg_info "Fetching Latest ImmichFrame Release"
RELEASE=$(curl -s https://api.github.com/repos/immichFrame/ImmichFrame/releases/latest \
  | grep "tag_name" | awk -F'"' '{print $4}')
msg_ok "Latest release: ${RELEASE}"

msg_info "Downloading ImmichFrame Source (${RELEASE})"
curl -fsSL "https://github.com/immichFrame/ImmichFrame/archive/refs/tags/${RELEASE}.tar.gz" \
  -o /tmp/immichframe.tar.gz
$STD tar -xzf /tmp/immichframe.tar.gz -C /tmp/
SRCDIR=$(ls -d /tmp/ImmichFrame-*)
msg_ok "Source Downloaded"

msg_info "Building ImmichFrame Backend (ASP.NET Core)"
mkdir -p /opt/immichframe/app/backend
cd "${SRCDIR}" || exit
$STD dotnet publish ImmichFrame.WebApi/ImmichFrame.WebApi.csproj \
  --configuration Release \
  --runtime linux-musl-x64 \
  --self-contained false \
  --output /opt/immichframe/app/backend
msg_ok "Backend Built"

msg_info "Building ImmichFrame Frontend (SvelteKit)"
cd "${SRCDIR}/immichFrame.Web" || exit
$STD npm ci
$STD npm run build
cp -r build /opt/immichframe/app/backend/wwwroot
msg_ok "Frontend Built"

msg_info "Creating Configuration Directory"
mkdir -p /opt/immichframe/config

# Cria Settings.yml com comentários explicativos
cat <<'EOF' > /opt/immichframe/config/Settings.yml
# =====================================================================
# ImmichFrame Configuration
# Docs: https://immichframe.dev/docs/getting-started/configuration
# =====================================================================

# ---------------------------------------------------------------------
# REQUIRED — Sem esses campos o ImmichFrame não funciona
# ---------------------------------------------------------------------

# URL do servidor Immich (ex: http://192.168.1.100:2283)
ImmichServerUrl: ""

# API Key do Immich
# Obtenha em: Immich > Account Settings > API Keys > New API Key
ApiKey: ""

# ---------------------------------------------------------------------
# Slideshow
# ---------------------------------------------------------------------

# Intervalo entre fotos em segundos (padrão: 10)
Interval: "10"

# Duração da transição em segundos (padrão: 2)
TransitionDuration: "2"

# Efeito de zoom na imagem (padrão: true)
ImageZoom: "true"

# Efeito de panorâmica (padrão: false)
ImagePan: "false"

# Preencher a tela (pode cortar bordas) (padrão: false)
ImageFill: "false"

# Layout: "fullscreen" ou "splitview"
Layout: "fullscreen"

# Renovar pool de imagens a cada N minutos (padrão: 30)
RenewImagesDuration: "30"

# ---------------------------------------------------------------------
# Filtros de Imagens
# ---------------------------------------------------------------------

# Mostrar memórias (fotos do mesmo dia em anos anteriores)
ShowMemories: "false"

# Mostrar apenas favoritos
ShowFavorites: "false"

# Incluir fotos arquivadas
ShowArchived: "false"

# Fotos dos últimos N dias (ex: "30")
# ImagesFromDays: ""

# Fotos a partir de (ISO 8601: YYYY-MM-DD)
# ImagesFromDate: ""

# Fotos até (ISO 8601: YYYY-MM-DD)
# ImagesUntilDate: ""

# Filtro por avaliação mínima (1-5 estrelas)
# Rating: ""

# ---------------------------------------------------------------------
# Álbuns e Pessoas
# ---------------------------------------------------------------------

# IDs de álbuns separados por vírgula
# Obtenha o ID em: Immich > Albums > selecione o álbum > veja a URL
# Albums: "uuid-album-1,uuid-album-2"

# IDs de álbuns a excluir
# ExcludedAlbums: "uuid-album-excluido"

# IDs de pessoas a incluir
# People: "uuid-pessoa-1"

# ---------------------------------------------------------------------
# Sobreposições (Overlays)
# ---------------------------------------------------------------------

# Exibir relógio
ShowClock: "false"

# Tamanho da fonte do relógio em pixels
# ClockFontSize: "100"

# Posição do relógio: BottomLeft, BottomRight, TopLeft, TopRight
# ClockPosition: "BottomLeft"

# Exibir barra de progresso
ShowProgressBar: "true"

# Exibir informações da foto (localização, data, etc.)
ShowImageDesc: "false"

# Exibir nome do álbum
ShowImageLocation: "false"

# Exibir data da foto
ShowImageDate: "false"
EOF
msg_ok "Configuration File Created"

msg_info "Creating ImmichFrame Service (OpenRC)"
cat <<'EOF' > /etc/init.d/immichframe
#!/sbin/openrc-run

name="ImmichFrame"
description="ImmichFrame Digital Photo Frame"

command="/usr/bin/dotnet"
command_args="/opt/immichframe/app/backend/ImmichFrame.WebApi.dll"
command_background=true
command_user="immichframe"

pidfile="/run/immichframe.pid"
output_log="/var/log/immichframe/immichframe.log"
error_log="/var/log/immichframe/immichframe.err"

directory="/opt/immichframe/app/backend"

export ASPNETCORE_URLS="http://0.0.0.0:8080"
export ASPNETCORE_ENVIRONMENT="Production"
export ImmichFrame__ConfigPath="/opt/immichframe/config"

depend() {
  need net
  after firewall
}

start_pre() {
  checkpath --directory --owner immichframe:immichframe --mode 0750 /var/log/immichframe
  checkpath --directory --owner immichframe:immichframe --mode 0750 /opt/immichframe/config
}
EOF
chmod +x /etc/init.d/immichframe
msg_ok "Service Created"

msg_info "Creating Dedicated User"
addgroup -S immichframe 2>/dev/null || true
adduser -S -G immichframe -h /opt/immichframe -s /sbin/nologin immichframe 2>/dev/null || true
chown -R immichframe:immichframe /opt/immichframe
msg_ok "User 'immichframe' Created"

msg_info "Enabling and Starting ImmichFrame Service"
$STD rc-update add immichframe default
$STD rc-service immichframe start
msg_ok "ImmichFrame Service Started"

msg_info "Saving Version Info"
echo "${RELEASE}" > /opt/immichframe/version.txt
msg_ok "Version ${RELEASE} Saved"

msg_info "Cleaning Up Build Artifacts"
rm -rf /tmp/immichframe.tar.gz "${SRCDIR}"
# Remove .NET SDK após build (mantém apenas o runtime para economizar espaço)
$STD apk del dotnet9-sdk
$STD apk cache clean
msg_ok "Cleanup Complete"

motd_ssh
customize
cleanup_lxc

