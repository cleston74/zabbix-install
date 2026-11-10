#!/usr/bin/env bash
#######################################################################################################################################
# Programa .....: install_grafana.sh
# Data Criação .: 09/01/2026
# Descrição ....: Realiza a instalação automática do Grafana OSS com backend PostgreSQL e plugin Zabbix (compatível com Zabbix 8.0)
#                 em sistemas RHEL-like (Rocky Linux / Alma Linux / Oracle Linux). Acesso via HTTP, ou HTTPS se o install_certificate.sh já rodou.
#                 Também habilita o stub_status do nginx e vincula o template "Nginx by Zabbix agent" ao Zabbix server.
# Autor ........: Cleiton Maia
#######################################################################################################################################

#-----[ Environment Variables ]-------------------------------------------------------------------------------------------------------#
grafanaVersion="13.3.0"
zabbixPluginVersion="6.10.2"        # >= 6.10.0 é obrigatório para Zabbix 8.0 (trend.get com sortfield)
businessChartsVersion="7.3.0"       # Business Charts (volkovlabs-echarts-panel), exige Grafana >= 12.3
grafanaConfig="/etc/grafana/grafana.ini"
grafanaDashboards="/var/lib/grafana/dashboards/zabbix"
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dashboardsSrc="${scriptDir}/grafana/dashboards"
# Zabbix API (mesmo host); o usuário precisa poder criar token de API
zbxApiUrl="http://127.0.0.1/api_jsonrpc.php"
zbxApiUser="Admin"
zbxApiPassword="zabbix"
zbxTokenName="grafana"
zbxHostname="$(hostname -s)"        # nome do host do Zabbix server no Zabbix (definido pelo install_zabbix.sh)
# Monitoramento do nginx (frontend do Zabbix) pelo template "Nginx by Zabbix agent"
nginxTemplate="Nginx by Zabbix agent"
nginxStubHost="127.0.0.1"
nginxStubPort="8088"
nginxStubPath="basic_status"
nginxStubConf="/etc/nginx/conf.d/status.conf"
grafanaProvisioning="/etc/grafana/provisioning"
ipLocal=$(ip -br a | awk '$1!="lo" && $3 ~ /^[0-9]/ {print $3; exit}' | cut -d/ -f1)
grafanaPort="3000"
# HTTPS: se o install_certificate.sh já gerou o certificado, o Grafana sobe em HTTPS e a API do Zabbix é chamada por HTTPS
tlsCert="/etc/pki/acme/acme.local.lab.crt"
tlsKey="/etc/pki/acme/acme.local.lab.key"
monitorFqdn="monitor.acme.local.lab"
panelFqdn="panel.acme.local.lab"
if [[ -f "${tlsCert}" && -f "${tlsKey}" ]]; then
  grafanaProtocol="https"
  grafanaUrlHost="${panelFqdn}"
  zbxApiUrl="https://${monitorFqdn}/api_jsonrpc.php"
else
  grafanaProtocol="http"
  grafanaUrlHost="${ipLocal}"
fi
grafanaBaseUrl="${grafanaProtocol}://${grafanaUrlHost}:${grafanaPort}"
pgHost="$ipLocal"
pgPort="5432"
pgData="/storage/postgres/data"
pgDatabase="db_grafana"
pgUser="usr_userpanel"
pgPassword="EbDH16j7hYeebbTJBQj0ezdHCU6vCB"

#-----[ System Function ]-------------------------------------------------------------------------------------------------------------#
strVisualLen() {
    local str="$1"
    printf '%s' "$str" | wc -m
}

functionBanner() {
    local boxWidth=120
    local border="╔$(printf '═%.0s' $(seq 1 $boxWidth))╗"
    local empty="║$(printf ' %.0s' $(seq 1 $boxWidth))║"
    local close="╚$(printf '═%.0s' $(seq 1 $boxWidth))╝"
    echo ""
    echo "$border"
    echo "$empty"
    for line in "$@"; do
        local visLen
        visLen=$(strVisualLen "$line")
        local padRight=$(( boxWidth - 1 - visLen ))
        [[ "$padRight" -lt 0 ]] && padRight=0
        printf "║$(tput bold) %s%*s$(tput sgr0)║\n" "$line" "$padRight" ""
    done
    echo "$empty"
    echo "$close"
    echo ""
}

functionCheckPackages() {
  for pkg in "$@"; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
      return 1
    fi
  done
  return 0
}

# Altera "chave = valor" somente dentro de uma seção do grafana.ini (aceita a linha comentada com ';')
functionSetIni() {
  local section="$1" key="$2" value="$3"
  sed -i "/^\[${section}\]/,/^\[/ s|^[;#]*[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "${grafanaConfig}"
}

# Chamada JSON-RPC à API do Zabbix; usa o Bearer de zbxAuth quando definido
functionZbxApi() {
  local method="$1" params="$2"
  curl -s -X POST "${zbxApiUrl}" -H 'Content-Type: application/json-rpc' \
    ${zbxAuth:+-H "Authorization: Bearer ${zbxAuth}"} \
    -d "$(jq -nc --arg m "${method}" --argjson p "${params}" '{jsonrpc:"2.0",method:$m,params:$p,id:1}')"
}

# Mostra o erro devolvido pela API do Zabbix, se houver, e retorna 1
functionApiError() {
  local msg
  msg=$(jq -r '.error | select(.) | "\(.message) \(.data)"' <<< "$1")
  [[ -n "${msg}" ]] && { echo "❌ ${msg}"; return 1; }
  return 0
}

#-----[ Validation's ]----------------------------------------------------------------------------------------------------------------#
if [[ $EUID -ne 0 ]]; then
  echo "❌ Execute como root."
  exit 1
fi

if ! systemctl is-active --quiet 'postgresql-*'; then
  echo "❌ PostgreSQL não está ativo. Rode antes o install_zabbix.sh."
  exit 1
fi

#-----[ Main Procedure ]--------------------------------------------------------------------------------------------------------------#
functionBanner "Automated Installation of Grafana OSS ${grafanaVersion}" \
               "Backend: PostgreSQL | Plugin Zabbix ${zabbixPluginVersion} | ${grafanaProtocol^^}" \
               "Includes: Zabbix datasource, Business Charts dashboards and nginx monitoring" \
               "" \
               "Created: Cleiton Maia"
  sleep 3

functionBanner "Checking Required Packages"
  if ! functionCheckPackages curl wget tar jq; then
    dnf install -y curl wget tar jq
    if [[ $? -eq 0 ]]; then
      echo "      Packages required install successfully."
    fi
  fi

functionBanner "Configuring Firewall"
  firewall-cmd --add-port=${grafanaPort}/tcp --permanent \
    && firewall-cmd --reload \
    && echo "      Firewall configured successfully."

functionBanner "Installing Grafana Repository"
  cat <<EOF > /etc/yum.repos.d/grafana.repo
[grafana]
name=Grafana OSS
baseurl=https://rpm.grafana.com
gpgkey=https://rpm.grafana.com/gpg.key
repo_gpgcheck=1
enabled=1
gpgcheck=1
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
exclude=grafana-enterprise*
EOF
  if [[ $? -eq 0 ]]; then
    echo "      Grafana repository configured successfully."
  fi

functionBanner "Installing Grafana ${grafanaVersion}"
  if ! dnf -y install "grafana-${grafanaVersion}"; then
    echo "❌ Grafana installation failed"
    exit 1
  fi
  dnf -y install 'dnf-command(versionlock)'
  dnf versionlock add grafana
  echo "      Grafana installed and locked on version ${grafanaVersion}."

functionBanner "Configuring PostgreSQL Database for Grafana"
  sudo -u postgres psql -c "CREATE USER ${pgUser} WITH PASSWORD '${pgPassword}' ;" 2>/dev/null
  sudo -u postgres psql -c "CREATE DATABASE ${pgDatabase} WITH OWNER = ${pgUser} ENCODING 'UTF8' TEMPLATE template0;" 2>/dev/null
  grep -q "${pgDatabase}.*${pgUser}.*${ipLocal}" "${pgData}/pg_hba.conf" \
    || echo -e "host\t${pgDatabase}\t${pgUser}\t${ipLocal}/32\tscram-sha-256" >> "${pgData}/pg_hba.conf"
  sudo -u postgres psql -c "SELECT pg_reload_conf();" >/dev/null 2>&1
  if PGPASSWORD="${pgPassword}" psql -h "${pgHost}" -p "${pgPort}" -U "${pgUser}" -d "${pgDatabase}" -Atc "SELECT 1" >/dev/null 2>&1; then
    echo "      Connection to ${pgDatabase} as ${pgUser} OK."
  else
    echo "❌ Grafana user cannot connect to ${pgDatabase} (check pg_hba.conf)"
    exit 1
  fi

functionBanner "Configuring Grafana (${grafanaProtocol^^} + PostgreSQL backend)"
  [[ -f "${grafanaConfig}.bkp" ]] || cp "${grafanaConfig}" "${grafanaConfig}.bkp"
  # [server]
  functionSetIni server   protocol   "${grafanaProtocol}"
  functionSetIni server   http_port  "${grafanaPort}"
  functionSetIni server   domain     "${grafanaUrlHost}"
  functionSetIni server   root_url   "${grafanaBaseUrl}/"
  if [[ "${grafanaProtocol}" == "https" ]]; then
    functionSetIni server cert_file  "${tlsCert}"
    functionSetIni server cert_key   "${tlsKey}"
    chgrp grafana "${tlsKey}" && chmod 640 "${tlsKey}"
  fi
  # [database]
  functionSetIni database type       "postgres"
  functionSetIni database host       "${pgHost}:${pgPort}"
  functionSetIni database name       "${pgDatabase}"
  functionSetIni database user       "${pgUser}"
  functionSetIni database password   "\"\"\"${pgPassword}\"\"\""
  functionSetIni database ssl_mode   "disable"
  sed -n '/^\[server\]/,/^\[/p; /^\[database\]/,/^\[/p' "${grafanaConfig}" \
    | grep -E '^(protocol|http_port|domain|root_url|cert_file|cert_key|type|host|name|user|ssl_mode) ='

functionBanner "Plugins Installation" \
               "Zabbix ${zabbixPluginVersion} | Business Charts ${businessChartsVersion}" \
               "Bar chart e PostgreSQL já são nativos do Grafana (não precisam de instalação)"
  grafana cli plugins install alexanderzobnin-zabbix-app "${zabbixPluginVersion}"
  grafana cli plugins install volkovlabs-echarts-panel "${businessChartsVersion}"
  # Habilita o app do plugin Zabbix na organização principal (painéis não precisam ser habilitados)
  mkdir -p "${grafanaProvisioning}/plugins"
  cat <<EOF > "${grafanaProvisioning}/plugins/zabbix.yaml"
apiVersion: 1
apps:
  - type: alexanderzobnin-zabbix-app
    org_id: 1
    disabled: false
EOF

functionBanner "Zabbix API login (${zbxApiUser})"
  zbxAuth=""
  zbxAuth=$(functionZbxApi user.login "$(jq -nc --arg u "${zbxApiUser}" --arg p "${zbxApiPassword}" '{username:$u,password:$p}')" | jq -r '.result // empty')
  if [[ -z "${zbxAuth}" ]]; then
    echo "❌ Zabbix API login failed (${zbxApiUrl}, user ${zbxApiUser})"
    exit 1
  fi
  hostJson=$(functionZbxApi host.get "$(jq -nc --arg h "${zbxHostname}" '{output:["hostid"],filter:{host:[$h]},selectParentTemplates:["templateid"]}')")
  hostId=$(jq -r '.result[0].hostid // empty' <<< "${hostJson}")
  if [[ -z "${hostId}" ]]; then
    echo "❌ Host ${zbxHostname} not found in Zabbix (ajuste zbxHostname)"
    exit 1
  fi
  echo "      Logged in; host ${zbxHostname} = hostid ${hostId}."

functionBanner "Enabling nginx stub_status on ${nginxStubHost}:${nginxStubPort}/${nginxStubPath}"
  cat <<EOF > "${nginxStubConf}"
# stub_status para o template "${nginxTemplate}" (somente local)
server {
    listen      ${nginxStubHost}:${nginxStubPort};
    server_name ${nginxStubHost};
    access_log  off;

    location = /${nginxStubPath} {
        stub_status;
        allow 127.0.0.1;
        deny  all;
    }
}
EOF
  if nginx -t && systemctl reload nginx; then
    sleep 2
    curl -s "http://${nginxStubHost}:${nginxStubPort}/${nginxStubPath}" || echo "⚠️  stub_status not responding"
  else
    echo "⚠️  nginx configuration test failed; nginx monitoring will have no data"
  fi

functionBanner "Linking template \"${nginxTemplate}\" to host ${zbxHostname}"
  templateId=$(functionZbxApi template.get "$(jq -nc --arg t "${nginxTemplate}" '{output:["templateid"],filter:{host:[$t]}}')" | jq -r '.result[0].templateid // empty')
  if [[ -z "${templateId}" ]]; then
    echo "⚠️  Template ${nginxTemplate} not found; skipped"
  elif jq -e --arg t "${templateId}" '.result[0].parentTemplates[] | select(.templateid == $t)' <<< "${hostJson}" >/dev/null; then
    echo "      Template already linked."
  else
    resp=$(functionZbxApi host.massadd "$(jq -nc --arg h "${hostId}" --arg t "${templateId}" '{hosts:[{hostid:$h}],templates:[{templateid:$t}]}')")
    functionApiError "${resp}" && echo "      Template linked (templateid ${templateId})."
  fi
  # Macros do host: o padrão do template (localhost:80) cairia no frontend do Zabbix
  hostMacros=$(functionZbxApi usermacro.get "$(jq -nc --arg h "${hostId}" '{output:["hostmacroid","macro"],hostids:[$h]}')")
  for pair in "{\$NGINX.STUB_STATUS.HOST}=${nginxStubHost}" "{\$NGINX.STUB_STATUS.PORT}=${nginxStubPort}" "{\$NGINX.STUB_STATUS.PATH}=${nginxStubPath}"; do
    macro="${pair%%=*}"; value="${pair#*=}"
    macroId=$(jq -r --arg m "${macro}" '.result[] | select(.macro == $m) | .hostmacroid' <<< "${hostMacros}")
    if [[ -n "${macroId}" ]]; then
      resp=$(functionZbxApi usermacro.update "$(jq -nc --arg i "${macroId}" --arg v "${value}" '{hostmacroid:$i,value:$v}')")
    else
      resp=$(functionZbxApi usermacro.create "$(jq -nc --arg h "${hostId}" --arg m "${macro}" --arg v "${value}" '{hostid:$h,macro:$m,value:$v}')")
    fi
    functionApiError "${resp}" && echo "      ${macro} = ${value}"
  done
  # A descoberta de processos do nginx roda de hora em hora; força a primeira execução
  ruleId=$(functionZbxApi discoveryrule.get "$(jq -nc --arg h "${hostId}" '{output:["itemid"],hostids:[$h],filter:{key_:["nginx.proc.discovery"]}}')" | jq -r '.result[0].itemid // empty')
  if [[ -n "${ruleId}" ]]; then
    sleep 5
    resp=$(functionZbxApi task.create "$(jq -nc --arg i "${ruleId}" '[{type:6,request:{itemid:$i}}]')")
    functionApiError "${resp}" && echo "      Nginx process discovery scheduled."
  fi

functionBanner "Creating Zabbix API token (${zbxTokenName}) for user ${zbxApiUser}"
  zbxUserId=$(functionZbxApi user.get "$(jq -nc --arg u "${zbxApiUser}" '{output:["userid"],filter:{username:$u}}')" | jq -r '.result[0].userid')
  # O valor do token só é exibido na criação: se já existir um com o mesmo nome, recria
  oldTokenIds=$(functionZbxApi token.get "$(jq -nc --arg n "${zbxTokenName}" --arg u "${zbxUserId}" '{output:["tokenid"],filter:{name:$n,userid:$u}}')" | jq -c '[.result[].tokenid]')
  [[ "${oldTokenIds}" != "[]" ]] && functionZbxApi token.delete "${oldTokenIds}" >/dev/null
  tokenId=$(functionZbxApi token.create "$(jq -nc --arg n "${zbxTokenName}" --arg u "${zbxUserId}" '{name:$n,userid:$u,description:"Datasource Zabbix do Grafana"}')" | jq -r '.result.tokenids[0] // empty')
  zbxApiToken=$(functionZbxApi token.generate "[\"${tokenId}\"]" | jq -r '.result[0].token // empty')
  functionZbxApi user.logout '[]' >/dev/null
  if [[ -z "${zbxApiToken}" ]]; then
    echo "❌ Could not create the Zabbix API token"
    exit 1
  fi
  echo "      Token ${zbxTokenName} created (tokenid ${tokenId})."

functionBanner "Provisioning Zabbix datasource (uid zabbix)"
  mkdir -p "${grafanaProvisioning}/datasources"
  cat <<EOF > "${grafanaProvisioning}/datasources/zabbix.yaml"
apiVersion: 1
datasources:
  - name: Zabbix
    uid: zabbix
    type: alexanderzobnin-zabbix-datasource
    access: proxy
    url: ${zbxApiUrl}
    isDefault: true
    editable: true
    jsonData:
      authType: token
      trends: true
      trendsFrom: 7d
      trendsRange: 4d
      cacheTTL: 1h
      timeout: 30
    secureJsonData:
      apiToken: ${zbxApiToken}
EOF

functionBanner "Provisioning Zabbix dashboards (Business Charts)"
  mkdir -p "${grafanaProvisioning}/dashboards" "${grafanaDashboards}"
  cat <<EOF > "${grafanaProvisioning}/dashboards/zabbix.yaml"
apiVersion: 1
providers:
  - name: zabbix
    folder: Zabbix
    type: file
    allowUiUpdates: true
    options:
      path: ${grafanaDashboards}
EOF
  if ls "${dashboardsSrc}"/*.json >/dev/null 2>&1; then
    for f in "${dashboardsSrc}"/*.json; do
      sed "s/__ZBX_HOST__/${zbxHostname}/g" "${f}" > "${grafanaDashboards}/$(basename "${f}")"
      echo "      $(basename "${f}") -> host ${zbxHostname}"
    done
  else
    echo "⚠️  No dashboards found in ${dashboardsSrc}"
  fi

functionBanner "Set Permissions"
  # O "grafana cli" roda como root; sem isso o plugin fica com dono root e o Grafana 13 falha ao gerenciá-lo
  chown -R grafana:grafana /var/lib/grafana
  chown -R root:grafana "${grafanaConfig}" "${grafanaProvisioning}"
  chmod 640 "${grafanaConfig}" "${grafanaProvisioning}/datasources/zabbix.yaml"
  echo "      Permissions set successfully."

functionBanner "Starting Grafana Service"
  systemctl daemon-reload
  systemctl enable grafana-server
  # restart (e não só --now): numa reexecução o serviço já está ativo e precisa recarregar plugins e provisioning
  systemctl restart grafana-server
  # Na primeira subida o Grafana cria o schema no PostgreSQL; pode levar mais de um minuto
  for i in $(seq 1 36); do
    if curl -s "${grafanaBaseUrl}/api/health" | grep -q '"database": *"ok"'; then
      healthOk=1
      break
    fi
    sleep 5
  done
  if [[ -z "${healthOk}" ]]; then
    echo "❌ Grafana health-check failed (journalctl -u grafana-server)"
    exit 1
  fi
  curl -s "${grafanaBaseUrl}/api/health"; echo
  echo "      Grafana service started successfully."

functionBanner "Validating plugins, datasource and dashboards"
  grafanaAuth="admin:admin"         # só vale enquanto a senha padrão não for trocada
  for p in alexanderzobnin-zabbix-app volkovlabs-echarts-panel barchart grafana-postgresql-datasource; do
    v=$(curl -s -u "${grafanaAuth}" "${grafanaBaseUrl}/api/plugins/${p}/settings" | jq -r 'if .id then (if (.info.version // "") == "" then "nativo" else .info.version end) else empty end')
    echo "      Plugin ${p} ........: ${v:-NOT FOUND}"
  done
  curl -s -u "${grafanaAuth}" "${grafanaBaseUrl}/api/datasources/uid/zabbix/health" | jq -r '"      Datasource Zabbix ....: \(.status) - \(.message)"'
  curl -s -u "${grafanaAuth}" "${grafanaBaseUrl}/api/search?type=dash-db&query=" | jq -r '.[] | "      Dashboard ............: \(.folderTitle // "General")/\(.title)"'

functionBanner "Grafana Installation Completed Successfully" \
               "" \
               "Access URL:" \
               "${grafanaBaseUrl}" \
               "" \
               "Default User.....: admin" \
               "Default Password.: admin" \
               "" \
               "Change the password on first login!" \
               "" \
               "Thanks for using this script!"
