#!/usr/bin/env bash
#######################################################################################################################################
# Programa .....: uninstall_grafana.sh
# Descrição ....: Remove Grafana instalado via install_grafana.sh
# Autor ........: Cleiton Maia
#######################################################################################################################################

#-----[ Environment Variables ]-------------------------------------------------------------------------------------------------------#
grafanaPort="3000"
grafanaConfig="/etc/grafana/grafana.ini"
grafanaRepo="/etc/yum.repos.d/grafana.repo"
sslPath="/usr/share/grafana/ssl"
pgDatabase="db_grafana"
pgUser="ugrafanadmin"
pgData="/storage/postgres/data"
removeDatabase=false

#-----[ System Function ]-------------------------------------------------------------------------------------------------------------#
functionBanner() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗"
  echo "║                                                                                                                        ║"
  printf "║$(tput bold) %-118s $(tput sgr0)║\n" "$@"
  echo "║                                                                                                                        ║"
  echo "╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝"
  echo ""
}

show_help() {
  echo
  echo "Uso:"
  echo "  $0 [opções]"
  echo
  echo "Opções:"
  echo "  --remove-database   Remove banco e usuário PostgreSQL do Grafana"
  echo "  --help              Exibe esta ajuda"
  echo
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove-database)
      removeDatabase=true
      shift
      ;;
    --help|-h)
      show_help
      ;;
    *)
      echo "❌ Parâmetro inválido: $1"
      echo "Use: $0 --help"
      exit 1
      ;;
  esac
done

#-----[ Main Procedure ]--------------------------------------------------------------------------------------------------------------#
functionBanner "Grafana Uninstall" \
               "Removing Grafana services, packages and configuration"

functionBanner "Stopping Grafana Service"
  systemctl stop grafana-server 2>/dev/null
  systemctl disable grafana-server 2>/dev/null
  systemctl daemon-reload

functionBanner "Removing Grafana Package"
  dnf -y remove grafana

functionBanner "Removing Grafana Repository"
  rm -f "${grafanaRepo}"
  dnf clean all

functionBanner "Removing Firewall Rule"
  firewall-cmd --remove-port=${grafanaPort}/tcp --permanent 2>/dev/null
  firewall-cmd --reload 2>/dev/null

functionBanner "Removing Grafana Configuration and Data"
  rm -rf /etc/grafana
  rm -rf /var/lib/grafana
  rm -rf /var/log/grafana
  rm -rf /var/run/grafana
  rm -rf "${sslPath}"

functionBanner "Removing Grafana PostgreSQL pg_hba.conf Entry"
  if [[ -f "${pgData}/pg_hba.conf" ]]; then
    cp "${pgData}/pg_hba.conf" "${pgData}/pg_hba.conf.bkp_uninstall_grafana_$(date +%Y%m%d-%H%M%S)"
    sed -i "/${pgDatabase}.*${pgUser}/d" "${pgData}/pg_hba.conf"
    sudo -u postgres psql -c "SELECT pg_reload_conf();" 2>/dev/null
  fi

if [[ "${removeDatabase}" == true ]]; then
  functionBanner "Removing Grafana PostgreSQL Database and User"
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${pgDatabase};" 2>/dev/null
    sudo -u postgres psql -c "DROP USER IF EXISTS ${pgUser};" 2>/dev/null
else
  functionBanner "PostgreSQL Database Preserved" \
                 "Database ${pgDatabase} and user ${pgUser} were not removed." \
                 "Use --remove-database if you want to remove them."
fi

functionBanner "Grafana Uninstall Completed"
