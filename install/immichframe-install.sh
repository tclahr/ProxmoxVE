#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Thiago Canozzo Lahr (tclahr)
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
$STD apk add --no-cache \
  dotnet8-sdk \
  aspnetcore8-runtime
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
mkdir -p /app
cd "${SRCDIR}" || exit
$STD dotnet publish ImmichFrame.WebApi/ImmichFrame.WebApi.csproj \
  --configuration Release \
  --runtime linux-musl-x64 \
  --self-contained false \
  --output /app
msg_ok "Backend Built"

msg_info "Building ImmichFrame Frontend (SvelteKit)"
cd "${SRCDIR}/immichFrame.Web" || exit
$STD npm ci
$STD npm run build
cp -r build /app/wwwroot
msg_ok "Frontend Built"

msg_info "Creating Configuration Directory"
mkdir -p /app/Config

# Cria Settings.yml com comentários explicativos
cat <<'EOF' > /opt/immichframe/config/Settings.yml
# =====================================================================
# ImmichFrame Configuration
# Docs: https://immichframe.dev/docs/getting-started/configuration
# =====================================================================
General:
  AuthenticationSecret: null
  DownloadImages: false
  RenewImagesDuration: 30
  Webcalendars:
    - calendarurl
  RefreshAlbumPeopleInterval: 12
  PhotoDateFormat: dd/MM/yyyy
  ImageLocationFormat: 'City,State,Country'
  WeatherApiKey: ''
  UnitSystem: metric
  WeatherLatLong: '40.730610,-73.935242'
  Webhook: null
  Language: en
  Interval: 10
  TransitionDuration: 2
  ShowClock: true
  ClockFormat: 'hh:mm'
  ClockDateFormat: 'eee, MMM d'
  ShowProgressBar: true
  ShowPhotoDate: true
  ShowImageDesc: true
  ShowPeopleDesc: true
  ShowAlbumName: true
  ShowImageLocation: true
  PrimaryColor: '#93B1C9'
  SecondaryColor: '#000000'
  Style: none
  BaseFontSize: 16px
  ShowWeatherDescription: true
  WeatherIconUrl: 'https://openweathermap.org/img/wn/{IconId}.png'
  ImageZoom: true
  ImagePan: false
  ImageFill: false
  Layout: splitview
Accounts:
  - ImmichServerUrl: 'https://immich-server-address'
    ApiKey: 'ENTER YOUR API KEY HERE'
    ImagesFromDate: null
    ShowMemories: false
    ShowFavorites: false
    ShowArchived: false
    ImagesFromDays: null
    Rating: null
    Albums:
      - ALBUM1_UUID
      - ALBUM2_UUID
EOF
msg_ok "Configuration File Created"

msg_info "Creating ImmichFrame Service (OpenRC)"
cat <<'EOF' > /etc/init.d/immichframe
#!/sbin/openrc-run

name="ImmichFrame"
description="ImmichFrame Digital Photo Frame"

command="/usr/bin/dotnet"
command_args="/app/ImmichFrame.WebApi.dll"
command_background=true
command_user="immichframe"

pidfile="/run/immichframe.pid"
output_log="/var/log/immichframe/immichframe.log"
error_log="/var/log/immichframe/immichframe.err"

directory="/app"

export ASPNETCORE_URLS="http://0.0.0.0:8080"
export ASPNETCORE_ENVIRONMENT="Production"

depend() {
  need net
  after firewall
}

start_pre() {
  checkpath --directory --owner immichframe:immichframe --mode 0750 /var/log/immichframe
  checkpath --directory --owner immichframe:immichframe --mode 0750 /app/Config
}
EOF
chmod +x /etc/init.d/immichframe
msg_ok "Service Created"

msg_info "Creating Dedicated User"
addgroup -S immichframe 2>/dev/null || true
adduser -S -G immichframe -h /app -s /sbin/nologin immichframe 2>/dev/null || true
chown -R immichframe:immichframe /app
msg_ok "User 'immichframe' Created"

msg_info "Enabling and Starting ImmichFrame Service"
$STD rc-update add immichframe default
$STD rc-service immichframe start
msg_ok "ImmichFrame Service Started"

msg_info "Saving Version Info"
echo "${RELEASE}" > /app/version.txt
msg_ok "Version ${RELEASE} Saved"

msg_info "Cleaning Up Build Artifacts"
rm -rf /tmp/immichframe.tar.gz "${SRCDIR}"
# Remove .NET SDK após build (mantém apenas o runtime para economizar espaço)
$STD apk del dotnet8-sdk
$STD apk cache clean
msg_ok "Cleanup Complete"

motd_ssh
customize
cleanup_lxc

