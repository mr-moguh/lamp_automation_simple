# lamp_automation_simple

---
tags:
  - linux
  - server
  - centos
  - automation
  - security
  - lamp-stack
status: concluído
authors:
  - José Hugo Machado Madruga Filho
  - Pedro Miguel Correia Mexa
  - Rui Miguel Feio Brito

disciplina: Servidor de Dados (5107)
data: Novembro 2025
---

# Alojamento de Website em Servidor Linux com Acesso Externo

> [!SUMMARY] Resumo do Projeto
> Implementação e otimização de um servidor **CentOS Stream 10** em ambiente virtualizado para hospedagem web. O projeto foca na estabilidade, segurança e automação, utilizando a stack **LAMP** (Linux, Apache, MariaDB, PHP), acessível externamente via IP público e DDNS.
> 
> **Destaque:** Desenvolvimento de um script proprietário em Bash para orquestração completa da infraestrutura (Infrastructure as Code).

---

## Stack Tecnológica

| Componente | Tecnologia / Versão | Função |
| :--- | :--- | :--- |
| **OS** | CentOS Stream 10 (No GUI) | Sistema Base |
| **Web Server** | Apache 2.4.63 | Servidor HTTP/HTTPS |
| **DB** | MariaDB 10.11 | Base de Dados |
| **Lang** | PHP 8.3.19 | Processamento Server-side |
| **Automação** | Bash Scripting | Provisão e Manutenção |
| **Segurança** | Firewalld, Fail2ban, ModSecurity | WAF e Proteção de Rede |
| **SSL** | Let's Encrypt (Certbot) | Criptografia HTTPS |
| **DNS** | DuckDNS | DNS Dinâmico |

---

## Automação e Scripting

Foi desenvolvido o script `lamp-full_simple.sh` para automatizar a instalação e configuração. O script é modular e interativo.

### Funcionalidades do Script
- [x] **System Update:** Instalação de EPEL, Git, Curl, Chrony.
- [x] **Rede:** Configuração interativa de IP Estático via `nmcli`.
- [x] **Stack LAMP:** Instalação e configuração automática de Apache, MariaDB e PHP.
- [x] **Deploy:** Clone de repositório Git diretamente para `/var/www/html`.
- [x] **Database:** Criação automática de DB, User e ficheiro `db_connect.php`.
- [x] **Segurança:** Configuração de Firewalld, SELinux e Hardening de SSH.
- [x] **SSL:** Obtenção automática de certificados via Certbot.
- [x] **Backup:** Criação de *cron jobs* para backups diários.
- [x] **DNS:** Configuração de script de atualização DuckDNS.

### Como Utilizar

1. **Download do Script:**
   Transfira o ficheiro `lamp-full_simple.sh` para o servidor.

2. **Permissões de Execução:**
   ```bash
   chmod +x lamp-full_simple.sh
   ```
3. **Execução:**

4. **Menu Interativo: O script apresentará o seguinte menu de gestão:**

### Medidas de Segurança Implementadas
[!WARNING] Portas e Acessos O acesso SSH padrão (22) foi desativado.

- Nova Porta SSH: 13063 (TCP)
- Portas Web: 80 (HTTP), 443 (HTTPS)

1. **SSH Hardening**

   
2. **Firewall & WAF**

3. **Políticas SELinux**
Booleanos ativados para permitir operações web:
```bash
setsebool -P httpd_can_network_connect 1
setsebool -P httpd_can_network_connect_db 1
setsebool -P httpd_read_user_content 1
```

### Estrutura de Diretórios Importantes
- Web Root: /var/www/html
- Backups: /opt/backup (ou /backups)
- Config DB: /var/www/html/config/db_connect.php
- Logs Apache: /var/log/httpd/error_log
- Logs ModSecurity: /var/log/httpd/modsec_audit.log
- Script Automação: /root/lamp-full_simple.sh (ou local de preferência)
- Script DuckDNS: /opt/duckdns/duck.sh

### Rotinas Automáticas (Cron Jobs)
  Frequência|Ação|Comando/Script
  ================================
|Diário (02:00)|Backup Web & DB|/usr/local/bin/simple_backup.sh|
|A cada 5 min|Update IP DuckDNS|/opt/duckdns/duck.sh|
|Automático|Updates Sistema|dnf-automatic.timer|
|Automático|Sincronização Hora|chronyd|

### Comandos de Validação
```bash
# Verificar status dos serviços
systemctl status httpd mariadb fail2ban firewalld

# Testar configuração Apache
apachectl configtest

# Verificar regras de Firewall ativas
firewall-cmd --list-all

# Verificar estado do Fail2ban
fail2ban-client status sshd

# Sincronização NTP
chronyc tracking
```
