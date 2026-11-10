#!/usr/bin/env bash
#######################################################################################################################################
# Programa .....: install_certificate.sh
# Data Criação .: 10/11/2026
# Descrição ....: Instala o mkcert em RHEL-like 10 (Rocky Linux / Alma Linux), cria uma CA local e um certificado para o IP da
#                 instância, monitor.acme.local.lab (Zabbix) e panel.acme.local.lab (Grafana), registra os nomes no /etc/hosts
#                 e passa o frontend do Zabbix (nginx) e o Grafana para HTTPS.
# Autor ........: Cleiton Maia
# Modo de Uso...: rode depois do install_zabbix.sh (e do install_grafana.sh, se o Grafana for usado)
#######################################################################################################################################

#-----[ Environment Variables ]-------------------------------------------------------------------------------------------------------#
mkcertVersion="v1.4.4"
mkcertBin="/usr/local/bin/mkcert"
caRoot="/etc/pki/mkcert"                                  # CA local do mkcert (rootCA.pem vai para as estações)
tlsDir="/etc/pki/acme"
tlsCert="${tlsDir}/acme.local.lab.crt"
tlsKey="${tlsDir}/acme.local.lab.key"
monitorFqdn="monitor.acme.local.lab"                      # Zabbix (nginx, porta 443)
panelFqdn="panel.acme.local.lab"                          # Grafana (porta 3000)
ipLocal=$(ip -br a | awk '$1!="lo" && $3 ~ /^[0-9]/ {print $3; exit}' | cut -d/ -f1)
# Zabbix
zbxNginxConf="/etc/nginx/conf.d/zabbix.conf"
zbxRedirectConf="/etc/nginx/conf.d/zabbix_http_redirect.conf"
zbxApiUser="Admin"
zbxApiPassword="zabbix"
# Grafana
grafanaConfig="/etc/grafana/grafana.ini"
grafanaDatasource="/etc/grafana/provisioning/datasources/zabbix.yaml"
grafanaPort="3000"

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

# Altera "chave = valor" somente dentro de uma seção do grafana.ini (aceita a linha comentada com ';')
functionSetIni() {
  local section="$1" key="$2" value="$3"
  sed -i "/^\[${section}\]/,/^\[/ s|^[;#]*[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "${grafanaConfig}"
}

# Chamada JSON-RPC à API do Zabbix; usa o Bearer de zbxAuth quando definido
functionZbxApi() {
  local method="$1" params="$2"
  curl -s -X POST "https://${monitorFqdn}/api_jsonrpc.php" -H 'Content-Type: application/json-rpc' \
    ${zbxAuth:+-H "Authorization: Bearer ${zbxAuth}"} \
    -d "$(jq -nc --arg m "${method}" --argjson p "${params}" '{jsonrpc:"2.0",method:$m,params:$p,id:1}')"
}

#-----[ Validation's ]----------------------------------------------------------------------------------------------------------------#
if [[ $EUID -ne 0 ]]; then
  echo "❌ Execute como root."
  exit 1
fi

if [[ -z "${ipLocal}" ]]; then
  echo "❌ Não foi possível descobrir o IP da instância."
  exit 1
fi

if [[ ! -f "${zbxNginxConf}" ]] || ! grep -Eq 'listen[[:space:]]+(\[::\]:)?(80|443)' "${zbxNginxConf}"; then
  echo "❌ ${zbxNginxConf} não encontrado ou sem listen configurado. Rode antes o install_zabbix.sh."
  exit 1
fi

case "$(uname -m)" in
  x86_64)  mkcertArch="amd64" ;;
  aarch64) mkcertArch="arm64" ;;
  *) echo "❌ Arquitetura $(uname -m) não suportada."; exit 1 ;;
esac

#-----[ Main Procedure ]--------------------------------------------------------------------------------------------------------------#
functionBanner "Automated HTTPS with mkcert ${mkcertVersion}" \
               "Zabbix ..: https://${monitorFqdn}/" \
               "Grafana .: https://${panelFqdn}:${grafanaPort}/" \
               "" \
               "Created: Cleiton Maia"
  sleep 3

functionBanner "Checking Required Packages"
  dnf -y install curl jq openssl ca-certificates
  echo "      Packages required installed."

functionBanner "Installing mkcert ${mkcertVersion} (${mkcertArch})"
  # O mkcert não está nos repositórios do EL10: usa o binário oficial do GitHub
  if [[ -x "${mkcertBin}" ]] && "${mkcertBin}" -version 2>/dev/null | grep -q "${mkcertVersion}"; then
    echo "      mkcert ${mkcertVersion} already installed."
  else
    if ! curl -fsSL -o "${mkcertBin}" \
         "https://github.com/FiloSottile/mkcert/releases/download/${mkcertVersion}/mkcert-${mkcertVersion}-linux-${mkcertArch}"; then
      echo "❌ mkcert download failed"
      exit 1
    fi
    chmod 755 "${mkcertBin}"
    echo "      mkcert $("${mkcertBin}" -version) installed in ${mkcertBin}."
  fi

functionBanner "Creating local CA (CAROOT=${caRoot})"
  # Numa reexecução a CA existente é reaproveitada; recriá-la invalidaria o rootCA.pem já importado nas estações
  mkdir -p "${caRoot}"
  chmod 700 "${caRoot}"
  export CAROOT="${caRoot}"
  # Grava a CA em /etc/pki/ca-trust/source/anchors e roda update-ca-trust: curl, nginx e Grafana passam a confiar nela
  if ! "${mkcertBin}" -install; then
    echo "❌ mkcert -install failed"
    exit 1
  fi
  echo "      Root CA: ${caRoot}/rootCA.pem"

functionBanner "Generating certificate" \
               "${monitorFqdn} | ${panelFqdn} | ${ipLocal}"
  mkdir -p "${tlsDir}"
  chmod 755 "${tlsDir}"
  # Sempre regera: se o IP da instância mudou, o certificado novo já sai com ele
  if ! "${mkcertBin}" -cert-file "${tlsCert}" -key-file "${tlsKey}" \
         "${monitorFqdn}" "${panelFqdn}" "${ipLocal}" "$(hostname -s).acme.local.lab" localhost 127.0.0.1; then
    echo "❌ Certificate generation failed"
    exit 1
  fi
  chmod 644 "${tlsCert}"
  chmod 640 "${tlsKey}"
  # O nginx lê a chave como root; o Grafana roda como grafana e precisa do grupo
  getent group grafana >/dev/null && chgrp grafana "${tlsKey}"
  restorecon -R "${tlsDir}" 2>/dev/null
  openssl x509 -in "${tlsCert}" -noout -subject -enddate -ext subjectAltName | sed 's/^/      /'

functionBanner "Registering names in /etc/hosts"
  [[ -f /etc/hosts.bkp ]] || cp /etc/hosts /etc/hosts.bkp
  sed -i -E "/[[:space:]](${monitorFqdn}|${panelFqdn})([[:space:]]|$)/d" /etc/hosts
  echo -e "${ipLocal}\t${monitorFqdn}\t${panelFqdn}" >> /etc/hosts
  grep -E "${monitorFqdn}|${panelFqdn}" /etc/hosts | sed 's/^/      /'

functionBanner "Configuring NGINX (Zabbix) for HTTPS on port 443"
  [[ -f "${zbxNginxConf}.bkp_http" ]] || cp "${zbxNginxConf}" "${zbxNginxConf}.bkp_http"
  sed -i -E 's/listen[[:space:]]+80[[:space:]]+default_server;/listen 443 ssl default_server;/' "${zbxNginxConf}"
  sed -i -E 's/listen[[:space:]]+\[::\]:80[[:space:]]+default_server;/listen [::]:443 ssl default_server;/' "${zbxNginxConf}"
  sed -i -E "s/^([[:space:]]*)server_name[[:space:]].*;/\1server_name ${monitorFqdn} ${ipLocal};/" "${zbxNginxConf}"
  # Diretivas TLS marcadas com "# acme-tls" para a reexecução trocar sem duplicar
  sed -i '/# acme-tls$/d' "${zbxNginxConf}"
  sed -i -E "/^[[:space:]]*server_name[[:space:]]/a\\
        ssl_certificate     ${tlsCert}; # acme-tls\\
        ssl_certificate_key ${tlsKey}; # acme-tls\\
        ssl_protocols       TLSv1.2 TLSv1.3; # acme-tls\\
        http2               on; # acme-tls" "${zbxNginxConf}"
  # A porta 80 passa a só redirecionar para HTTPS
  cat <<EOF > "${zbxRedirectConf}"
# Redireciona HTTP para HTTPS (criado pelo install_certificate.sh)
server {
    listen      80 default_server;
    listen      [::]:80 default_server;
    server_name _;
    return 301 https://\$host\$request_uri;
}
EOF
  if nginx -t && systemctl reload nginx; then
    echo "      NGINX reloaded with HTTPS."
  else
    echo "❌ nginx configuration test failed; restoring ${zbxNginxConf}.bkp_http"
    cp "${zbxNginxConf}.bkp_http" "${zbxNginxConf}"
    rm -f "${zbxRedirectConf}"
    systemctl reload nginx
    exit 1
  fi

functionBanner "Setting the Zabbix frontend URL (Administration → General → Other)"
  zbxAuth=""
  zbxAuth=$(functionZbxApi user.login "$(jq -nc --arg u "${zbxApiUser}" --arg p "${zbxApiPassword}" '{username:$u,password:$p}')" | jq -r '.result // empty')
  if [[ -n "${zbxAuth}" ]]; then
    resp=$(functionZbxApi settings.update "$(jq -nc --arg u "https://${monitorFqdn}/" '{url:$u}')")
    jq -e '.result' <<< "${resp}" >/dev/null && echo "      Frontend URL = https://${monitorFqdn}/" \
      || echo "⚠️  settings.update failed: $(jq -c '.error' <<< "${resp}")"
    functionZbxApi user.logout '[]' >/dev/null
  else
    echo "⚠️  Zabbix API login failed (${zbxApiUser}); frontend URL not changed"
  fi
  zbxAuth=""

if [[ -f "${grafanaConfig}" ]]; then
  functionBanner "Configuring Grafana for HTTPS on port ${grafanaPort}"
    [[ -f "${grafanaConfig}.bkp_http" ]] || cp "${grafanaConfig}" "${grafanaConfig}.bkp_http"
    functionSetIni server protocol  "https"
    functionSetIni server http_port "${grafanaPort}"
    functionSetIni server domain    "${panelFqdn}"
    functionSetIni server root_url  "https://${panelFqdn}:${grafanaPort}/"
    functionSetIni server cert_file "${tlsCert}"
    functionSetIni server cert_key  "${tlsKey}"
    sed -n '/^\[server\]/,/^\[/p' "${grafanaConfig}" | grep -E '^(protocol|http_port|domain|root_url|cert_file|cert_key) =' | sed 's/^/      /'
    # O datasource passa a chamar a API do Zabbix por HTTPS (a porta 80 agora só redireciona)
    if [[ -f "${grafanaDatasource}" ]]; then
      sed -i -E "s|^([[:space:]]*url:[[:space:]]*).*api_jsonrpc\.php|\1https://${monitorFqdn}/api_jsonrpc.php|" "${grafanaDatasource}"
      grep -E '^[[:space:]]*url:' "${grafanaDatasource}" | sed 's/^/      datasource /'
    fi
    # restart também faz o Grafana reler o bundle de CAs com a CA do mkcert
    systemctl restart grafana-server
    for i in $(seq 1 36); do
      if curl -s "https://${panelFqdn}:${grafanaPort}/api/health" | grep -q '"database": *"ok"'; then
        healthOk=1
        break
      fi
      sleep 5
    done
    if [[ -z "${healthOk}" ]]; then
      echo "❌ Grafana health-check failed over HTTPS; restore with: cp ${grafanaConfig}.bkp_http ${grafanaConfig} (journalctl -u grafana-server)"
      exit 1
    fi
    echo "      Grafana started with HTTPS."
else
  functionBanner "Grafana not installed" \
                 "Skipped; install_grafana.sh already uses HTTPS when ${tlsCert} exists"
fi

functionBanner "Validating HTTPS"
  echo "      Zabbix  https://${monitorFqdn}/ ......: $(curl -s -o /dev/null -w '%{http_code}' "https://${monitorFqdn}/")"
  echo "      Zabbix  https://${ipLocal}/ ......: $(curl -s -o /dev/null -w '%{http_code}' "https://${ipLocal}/")"
  echo "      Zabbix  http://${ipLocal}/ (redirect): $(curl -s -o /dev/null -w '%{http_code} -> %{redirect_url}' "http://${ipLocal}/")"
  if [[ -f "${grafanaConfig}" ]]; then
    echo "      Grafana https://${panelFqdn}:${grafanaPort}/ : $(curl -s -o /dev/null -w '%{http_code}' "https://${panelFqdn}:${grafanaPort}/login")"
    curl -s -u admin:admin "https://${panelFqdn}:${grafanaPort}/api/datasources/uid/zabbix/health" \
      | jq -r '"      Datasource Zabbix ....: \(.status // "n/a") - \(.message // "admin password changed?")"'
  fi

functionBanner "HTTPS Configuration Completed Successfully" \
               "" \
               "Zabbix ..: https://${monitorFqdn}/" \
               "Grafana .: https://${panelFqdn}:${grafanaPort}/" \
               "" \
               "On each workstation:" \
               " 1. import ${caRoot}/rootCA.pem as a trusted root CA" \
               " 2. add to the hosts file: ${ipLocal} ${monitorFqdn} ${panelFqdn}" \
               "" \
               "Thanks for using this script!"
