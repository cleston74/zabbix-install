# 🚀 Instalação Automatizada do Zabbix 8.0 (All-in-One)

## 📌 Visão Geral

![License](https://img.shields.io/badge/license-MIT-green)
![Status](https://img.shields.io/badge/status-lab%2Fstudy-blue)
![Zabbix](https://img.shields.io/badge/Zabbix-8.0-red)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-blue)
![TimescaleDB](https://img.shields.io/badge/TimescaleDB-2.29-orange)
![Grafana](https://img.shields.io/badge/Grafana-13.3-orange)

Este projeto tem como objetivo realizar a **instalação totalmente automatizada do Zabbix Server 8.0** em modo **All-in-One**, utilizando:

- Zabbix Server 8.x
- PostgreSQL 18
- TimescaleDB 2.29.x
- Nginx
- PHP-FPM
- Zabbix Agent 2
- Chrony (NTP.br) com timezone America/Sao_Paulo
- Grafana OSS 13.3 (opcional, script separado)
- HTTPS com certificado local do mkcert (opcional, script separado)

Todo o processo é executado a partir de uma **máquina virtual limpa**, através de scripts em **Shell Script**, de forma simples, reprodutível e rápida.

> 🔬 Projeto voltado para **estudos, testes e laboratórios**  
> ⚠️ **Não recomendado para ambientes de produção**

---

## 🧰 Pré-requisitos

### Sistema Operacional (RHEL-like 10.x)

- Uma instalação mínima já é o suficiente.

Compatível com:

- Red Hat Enterprise Linux 10
- Rocky Linux 10
- AlmaLinux 10
- Oracle Linux 10

### Hardware mínimo recomendado

- **4 vCPUs**
- **4 GB de RAM**
- **40 GB de disco**

### Requisitos adicionais

- Acesso **root**
- Conexão com a **internet**
- **Git** instalado

---

## ⚙️ Preparação do Ambiente

### Atualize o sistema operacional

```bash
dnf update -y && dnf upgrade -y
```

### Instale o Git

```bash
dnf -y install git
```

### Clone o repositório

```bash
git clone https://github.com/cleston74/zabbix7-install.git
```

### Acesse o diretório do projeto

```bash
cd zabbix7-install/scripts
```

### Torne os scripts executáveis

```bash
chmod +x install_zabbix.sh install_grafana.sh install_certificate.sh remove_grafana.sh
```

---

## ▶️ Modo de Uso

O script pode ser executado **sem parâmetros**, utilizando valores padrão, ou com **parâmetros personalizados**.

### 🔧 Parâmetros aceitos

| Parâmetro | Descrição |
|----------|----------|
| --host | Hostname do Zabbix Server |
| --db | Nome do banco de dados |
| --user | Usuário do banco |
| --password | Senha do usuário |
| -h, --help | Exibe a ajuda |

> Caso algum parâmetro seja omitido, o script utilizará **valores padrão**, definidos internamente.

---

## 📌 Exemplos de Execução

### Instalação com valores padrão

```bash
./install_zabbix.sh
```

### Instalação personalizada

```bash
./install_zabbix.sh --host spappzbx01 --password s3nh4f0Rt3
```

---

## ✅ Final da Instalação

Ao final da execução, serão exibidos:

- URL de acesso ao Zabbix
- Credenciais padrão
- Hostname configurado
- IP local do servidor

---

## 🌐 Primeiro Acesso

Acesse via navegador:

![Opções de Instalação](<images/zbx-03.png>)

```
http://IP_DO_SERVIDOR/
ou
http://HOSTNAME/
```

Credenciais padrão:

- **Usuário:** Admin
- **Senha:** zabbix

![Opções de Instalação](<images/zbx-04.png>)

![Opções de Instalação](<images/zbx-05.png>)

---

## 🖥️ Configuração Automática do Host

O script realiza automaticamente:

- Atualização do hostname no banco do Zabbix
- Atualização do IP local
- Ajuste do host padrão **Zabbix server**

![Opções de Instalação](<images/zbx-06.png>)

---

## 🐘 Monitoramento do PostgreSQL

Para monitorar o PostgreSQL local:

1. Edite o host no Zabbix
2. Associe o **template PostgreSQL**
3. Configure a **macro de senha** com a senha utilizada na instalação

![Opções de Instalação](<images/zbx-07.png>)

![Opções de Instalação](<images/zbx-08.png>)

---

## 📊 Visualização das Métricas

Acesse:

Monitoring → Latest data

![Opções de Instalação](<images/zbx-09.png>)

---

# 📈 Instalação Automatizada do Grafana

## 📌 Visão Geral

Depois do Zabbix, o script `install_grafana.sh` instala o **Grafana OSS** no mesmo servidor e deixa tudo integrado ao Zabbix, sem nenhum passo manual:

- Grafana OSS **13.3.0** (versão travada com `dnf versionlock`)
- Banco do Grafana no **PostgreSQL 18** já instalado pelo Zabbix
- Plugin **Zabbix** 6.10.2 (a partir da 6.10 é compatível com o Zabbix 8.0)
- Plugin **Business Charts** (`volkovlabs-echarts-panel`) 7.3.0
- Plugins **Bar chart** e **PostgreSQL** (nativos do Grafana)
- **Datasource Zabbix** criado automaticamente, autenticado por **token de API**
- **Dashboards** do Zabbix Server e do PostgreSQL feitos com Business Charts
- **Monitoramento do Nginx** (frontend do Zabbix) pelo template *Nginx by Zabbix agent*

> 🌐 Acesso por **HTTP** na porta **3000**, sem certificado digital.

---

## 🧰 Pré-requisitos

- `install_zabbix.sh` executado com sucesso **no mesmo servidor**
- PostgreSQL ativo (o script confere e para se não estiver)
- Frontend do Zabbix respondendo, com o usuário **Admin** e a senha padrão **zabbix** (o script usa a API do Zabbix)
- Acesso **root** e conexão com a **internet**

> ⚠️ Se a senha do Admin do Zabbix já foi trocada, ajuste a variável `zbxApiPassword` no início do script antes de executar.

---

## ▶️ Modo de Uso

O script não recebe parâmetros. Os valores ficam nas variáveis do início do arquivo.

```bash
./install_grafana.sh
```

### 🔧 Principais variáveis

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| grafanaVersion | 13.3.0 | Versão do Grafana OSS |
| zabbixPluginVersion | 6.10.2 | Versão do plugin Zabbix |
| businessChartsVersion | 7.3.0 | Versão do plugin Business Charts |
| grafanaPort | 3000 | Porta HTTP do Grafana |
| pgDatabase | db_grafana | Banco do Grafana no PostgreSQL |
| pgUser | usr_userpanel | Usuário do banco do Grafana |
| pgPassword | (definida no script) | Senha do usuário do banco |
| zbxApiUser / zbxApiPassword | Admin / zabbix | Usuário usado na API do Zabbix |
| zbxTokenName | grafana | Nome do token de API criado no Zabbix |
| nginxStubPort | 8088 | Porta do `stub_status` do Nginx |

---

## ⚙️ O que o script faz

1. Confere se está rodando como root e se o PostgreSQL está ativo
2. Instala os pacotes necessários (`curl`, `wget`, `tar`, `jq`)
3. Libera a porta **3000/tcp** no firewall
4. Configura o repositório oficial do Grafana (excluindo o `grafana-enterprise`)
5. Instala o Grafana **13.3.0** e trava a versão
6. Cria o banco `db_grafana` e o usuário `usr_userpanel` no PostgreSQL, com acesso `scram-sha-256` no `pg_hba.conf`
7. Configura o `grafana.ini`: HTTP e backend PostgreSQL
8. Instala os plugins Zabbix e Business Charts e habilita o app do Zabbix
9. Habilita o `stub_status` do Nginx em `127.0.0.1:8088/basic_status`, vincula o template **Nginx by Zabbix agent** ao host do Zabbix server e ajusta as macros
10. Cria (ou recria) o token de API **grafana** no Zabbix
11. Provisiona o datasource **Zabbix** (uid `zabbix`) e os dashboards na pasta **Zabbix**
12. Ajusta permissões, inicia o serviço e aguarda o Grafana ficar saudável
13. Valida plugins, datasource e dashboards pela API do Grafana

---

## ✅ Final da Instalação

Ao final da execução, serão exibidos:

- Versão de cada plugin instalado
- Status do datasource Zabbix
- Dashboards provisionados
- URL de acesso e credenciais padrão

---

## 🌐 Primeiro Acesso

Acesse via navegador:

```
http://IP_DO_SERVIDOR:3000/
```

Credenciais padrão:

- **Usuário:** admin
- **Senha:** admin

> 🔐 O Grafana pede a troca da senha no primeiro login.

---

## 📊 Dashboards

Os dashboards ficam em **Dashboards → Zabbix** e já apontam para o host do Zabbix server:

- **Zabbix Server — Saúde**
- **PostgreSQL — Saúde**

> ℹ️ Os gráficos do Nginx começam a ter dados alguns minutos depois da instalação, quando o Zabbix termina a primeira coleta do template.

---

## 🗑️ Remoção do Grafana

Para desinstalar o Grafana:

```bash
./remove_grafana.sh
```

Por padrão, o banco `db_grafana` e o usuário `usr_userpanel` são **preservados**. Para removê-los também:

```bash
./remove_grafana.sh --remove-database
```

> ⚠️ A remoção não desfaz o `stub_status` do Nginx, o template vinculado nem o token de API criado no Zabbix.

---

# 🔐 HTTPS com Certificado Local (mkcert)

## 📌 Visão Geral

O script `install_certificate.sh` passa o Zabbix e o Grafana para **HTTPS** usando um certificado de uma **CA local** criada pelo [mkcert](https://github.com/FiloSottile/mkcert):

- mkcert **v1.4.4** (binário oficial do GitHub; não existe nos repositórios do EL10)
- CA local em `/etc/pki/mkcert`, confiada pelo próprio servidor
- Certificado em `/etc/pki/acme/` válido para:
  - `monitor.acme.local.lab` (Zabbix)
  - `panel.acme.local.lab` (Grafana)
  - IP da instância, `<hostname>.acme.local.lab`, `localhost` e `127.0.0.1`
- Nomes registrados no `/etc/hosts` do servidor

| Serviço | Endereço |
|---------|----------|
| Zabbix | `https://monitor.acme.local.lab/` |
| Grafana | `https://panel.acme.local.lab:3000/` |

> 🔬 Certificado de laboratório: só é confiável nas máquinas que importarem a CA do mkcert.

---

## 🧰 Pré-requisitos

- `install_zabbix.sh` executado com sucesso
- `install_grafana.sh` executado (opcional; se o Grafana não estiver instalado, essa parte é pulada)
- Acesso **root** e conexão com a **internet** (download do mkcert)

> ℹ️ Também funciona antes do Grafana: se o certificado já existir, o `install_grafana.sh` instala o Grafana direto em HTTPS.

---

## ▶️ Modo de Uso

Ordem recomendada:

```bash
./install_zabbix.sh
./install_grafana.sh
./install_certificate.sh
```

O script não recebe parâmetros. Os nomes, os caminhos e a versão do mkcert ficam nas variáveis do início do arquivo.

### 🔧 Principais variáveis

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| mkcertVersion | v1.4.4 | Versão do mkcert |
| caRoot | /etc/pki/mkcert | Diretório da CA local (`rootCA.pem`) |
| tlsCert / tlsKey | /etc/pki/acme/acme.local.lab.crt / .key | Certificado e chave |
| monitorFqdn | monitor.acme.local.lab | Nome do Zabbix |
| panelFqdn | panel.acme.local.lab | Nome do Grafana |
| zbxApiUser / zbxApiPassword | Admin / zabbix | Usuário usado para gravar a URL do frontend no Zabbix |

---

## ⚙️ O que o script faz

1. Instala os pacotes necessários (`curl`, `jq`, `openssl`, `ca-certificates`)
2. Baixa o mkcert para `/usr/local/bin/mkcert`
3. Cria a CA local (ou reaproveita a existente) e a adiciona às CAs confiáveis do servidor
4. Gera o certificado (sempre de novo, para acompanhar uma troca de IP)
5. Registra `IP monitor.acme.local.lab panel.acme.local.lab` no `/etc/hosts`
6. Configura o nginx do Zabbix em **443 com TLS**; a porta **80 só redireciona** para HTTPS
7. Grava `https://monitor.acme.local.lab/` como URL do frontend no Zabbix
8. Configura o Grafana em **HTTPS na porta 3000** e aponta o datasource Zabbix para a API em HTTPS
9. Valida os endereços, o redirecionamento e o datasource

> 💾 Antes de alterar, o script guarda `zabbix.conf.bkp_http`, `grafana.ini.bkp_http` e `/etc/hosts.bkp`. Se o `nginx -t` falhar, a configuração anterior do nginx é restaurada.

---

## 💻 Configuração das Estações

Para acessar pelos nomes, sem aviso de certificado, cada estação precisa de dois ajustes.

### 1. Arquivo hosts

Linux / macOS (`/etc/hosts`) ou Windows (`C:\Windows\System32\drivers\etc\hosts`):

```
IP_DO_SERVIDOR    monitor.acme.local.lab    panel.acme.local.lab
```

> ⚠️ Não pode existir **outra linha** com `monitor.acme.local.lab` ou `panel.acme.local.lab` apontando para outro IP. O sistema usa a primeira que encontrar, e no macOS um nome repetido arrasta os outros nomes da mesma linha para o IP antigo.

Para conferir no macOS:

```bash
grep -n 'acme.local.lab' /etc/hosts
dscacheutil -q host -a name monitor.acme.local.lab
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

### 2. Confiar na CA do mkcert

Copie a CA do servidor:

```bash
scp root@IP_DO_SERVIDOR:/etc/pki/mkcert/rootCA.pem .
```

macOS:

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain rootCA.pem
```

Windows (PowerShell como administrador):

```powershell
Import-Certificate -FilePath .\rootCA.pem -CertStoreLocation Cert:\LocalMachine\Root
```

Linux (RHEL-like):

```bash
cp rootCA.pem /etc/pki/ca-trust/source/anchors/mkcert-acme.pem && update-ca-trust
```

> ℹ️ O Firefox usa um repositório próprio: importe o `rootCA.pem` em **Configurações → Privacidade e Segurança → Certificados → Autoridades**.

> 🔒 O `rootCA-key.pem` **nunca** deve sair do servidor: quem tiver essa chave consegue emitir certificados aceitos pelas suas estações.

---

## ✅ Final da Instalação

Ao final da execução, serão exibidos:

- Código HTTP do Zabbix pelo nome e pelo IP
- Redirecionamento da porta 80 para HTTPS
- Código HTTP do Grafana e status do datasource Zabbix
- Endereços de acesso e os ajustes necessários nas estações

---

## ⚠️ Aviso Importante

Este projeto foi desenvolvido **exclusivamente para fins educacionais**.

- ❌ Não utilizar em produção
- ✔️ Pode ser modificado e redistribuído
- 🤝 Contribuições são bem-vindas via **Pull Request**

---

## 👨‍💻 Autor

Cleiton Maia  
📧 cleiton.maia@pm.me  
🐙 GitHub: https://github.com/cleston74
