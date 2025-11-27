#!/bin/bash

set -euo pipefail

# ===========================================================
# SIMPLE LAMP WIZARD - CLEAN & MODULAR (FINAL v16)
# ===========================================================

# globais
WEB_ROOT="/var/www/html"
BACKUP_DIR="/opt/backup"

# ======================
# HELPER FUNCTIONS
# ======================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "erro: rode como root (sudo -i)"
        exit 1
    fi
}

msg() {
    echo ""
    echo ">>> $1"
    echo "--------------------------------------------------"
}

get_input() {
    local prompt="$1"
    local var_ref="$2"
    local default="${3:-}"

    if [ -z "${!var_ref:-}" ]; then
        if [ -n "$default" ]; then
            read -p "$prompt [$default]: " temp_val
            printf -v "$var_ref" "%s" "${temp_val:-$default}"
        else
            read -p "$prompt: " temp_val
            printf -v "$var_ref" "%s" "$temp_val"
        fi
    fi
}

# mostra como acessar o site baseado no que ja foi configurado
show_access_info() {
    local ip=$(hostname -I | awk '{print $1}')
    local public_ip=$(curl -s -4 ifconfig.me || echo "detectando...")
    
    echo ""
    echo "=============== COMO ACESSAR ==============="
    echo "Local/Privado:  http://$ip"
    echo "Publico (IP):   http://$public_ip"
    
    if [ -n "${SITE_DOMAIN:-}" ]; then
        echo "Dominio:        http://$SITE_DOMAIN"
        # verifica se tem certificado ssl ativo
        if [ -d "/etc/letsencrypt/live/$SITE_DOMAIN" ]; then
            echo "Seguro (SSL):   https://$SITE_DOMAIN"
        fi
    fi
    echo "============================================"
}

# ======================
# 1. SYSTEM BASE
# ======================
step_base_updates() {
    msg "atualizando sistema e instalando base"
    dnf update -y
    dnf install -y epel-release dnf-utils git wget curl tree chrony dnf-automatic firewalld policycoreutils-python-utils
    dnf config-manager --set-enabled crb || true
    systemctl enable --now chronyd
    sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf || true
    systemctl enable --now dnf-automatic.timer
}

# ======================
# 2. NETWORK
# ======================
step_static_ip() {
    msg "configuracao de ip estatico"
    echo "interfaces disponiveis:"
    ip a
    
    get_input "interface (ex: ens33)" NET_IFACE
    get_input "ip/cidr (ex: 192.168.1.100/24)" NET_IP
    get_input "gateway (ex: 192.168.1.1)" NET_GW
    get_input "dns (ex: 1.1.1.1)" NET_DNS

    read -p "aplicar config? pode derrubar ssh (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        nmcli con mod "$NET_IFACE" ipv4.addresses "$NET_IP" ipv4.gateway "$NET_GW" ipv4.dns "$NET_DNS" ipv4.method manual
        nmcli con down "$NET_IFACE" && nmcli con up "$NET_IFACE"
        echo "ip aplicado."
    fi
    show_access_info
}

# ======================
# 3. LAMP STACK
# ======================
step_install_lamp() {
    msg "instalando apache, mariadb e php"
    dnf install -y httpd mod_ssl mod_security
    systemctl enable --now httpd
    sed -i 's/SecRuleEngine On/SecRuleEngine DetectionOnly/' /etc/httpd/conf.d/mod_security.conf 2>/dev/null || true
    dnf install -y mariadb-server
    systemctl enable --now mariadb
    dnf install -y php php-fpm php-mysqlnd php-pdo php-gd php-mbstring php-xml php-zip php-intl
    systemctl enable --now php-fpm
    systemctl restart httpd
}

# ======================
# 4. SECURITY
# ======================
step_security_basic() {
    msg "aplicando seguranca basica"
    systemctl enable --now firewalld
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --permanent --add-port=22/tcp
    firewall-cmd --reload
    dnf install -y fail2ban
    systemctl enable --now fail2ban
    setsebool -P httpd_can_network_connect 1 || true
    setsebool -P httpd_can_network_connect_db 1 || true
    setsebool -P httpd_read_user_content 1 || true
}

step_harden_ssh() {
    msg "hardening ssh"
    get_input "nova porta ssh" SSH_NEW_PORT "2222"
    get_input "desativar login root? (yes/no)" SSH_NO_ROOT "yes"
    semanage port -a -t ssh_port_t -p tcp "$SSH_NEW_PORT" 2>/dev/null || true
    sed -i '/^Port /d' /etc/ssh/sshd_config
    echo "Port $SSH_NEW_PORT" >> /etc/ssh/sshd_config
    if [ "$SSH_NO_ROOT" == "yes" ]; then
        sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    fi
    firewall-cmd --permanent --add-port="${SSH_NEW_PORT}/tcp"
    firewall-cmd --permanent --remove-port=22/tcp
    firewall-cmd --reload
    systemctl restart sshd
}

# ======================
# 5. SITE DEPLOYMENT
# ======================
step_deploy_site() {
    msg "configuracao do site"
    get_input "dominio principal (sem www)" SITE_DOMAIN
    get_input "url repo github (vazio = teste)" GIT_REPO

    mkdir -p "$WEB_ROOT"
    if [ -n "$GIT_REPO" ]; then
        echo "clonando repositorio..."
        if [ "$(ls -A $WEB_ROOT)" ]; then mv "$WEB_ROOT" "${WEB_ROOT}_bkp_$(date +%s)"; fi
        dnf install -y git
        git clone "$GIT_REPO" "$WEB_ROOT"
        chown -R apache:apache "$WEB_ROOT"
        restorecon -R "$WEB_ROOT"
    else
        echo "<?php phpinfo(); ?>" > "$WEB_ROOT/index.php"
    fi

    cat > "/etc/httpd/conf.d/${SITE_DOMAIN}.conf" <<EOF
<VirtualHost *:80>
    ServerName ${SITE_DOMAIN}
    ServerAlias www.${SITE_DOMAIN}
    DocumentRoot ${WEB_ROOT}
    <Directory ${WEB_ROOT}>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
    systemctl restart httpd
    show_access_info
}

# ======================
# 6. DATABASE 
# ======================
step_setup_db() {
    msg "configuracao de banco de dados"
    read -p "criar ou atualizar banco de dados? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then return; fi

    get_input "nome do banco" DB_NAME
    get_input "usuario do banco" DB_USER
    get_input "senha do banco" DB_PASS

    mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
    mysql -u root -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -u root -e "ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
    mysql -u root -e "FLUSH PRIVILEGES;"

    local sql_file=$(find "$WEB_ROOT" -maxdepth 3 -name "*.sql" | head -n 1)
    if [ -n "$sql_file" ]; then
        echo "importando sql: $sql_file..."
        mysql -u root "$DB_NAME" < "$sql_file"
    fi

    TARGET_CONFIG=$(find "$WEB_ROOT" -maxdepth 3 -type f \( -name "*config*" -o -name "*db*" -o -name "*connect*" \) | grep ".php" | head -n 1)

    if [ -n "$TARGET_CONFIG" ]; then
        cp "$TARGET_CONFIG" "${TARGET_CONFIG}.bak" 2>/dev/null || true
        cat > "$TARGET_CONFIG" <<EOF
<?php
// config gerada automaticamente
\$servername = "localhost";
\$username = "${DB_USER}";
\$password = "${DB_PASS}";
\$dbname = "${DB_NAME}";
\$conn = mysqli_connect(\$servername, \$username, \$password, \$dbname);
if (!\$conn) { die("Connection failed: " . mysqli_connect_error()); }
?>
EOF
        chown apache:apache "$TARGET_CONFIG"
        echo "config atualizada em: $TARGET_CONFIG"
    fi
}

# ======================
# 7. EXTRAS & INFO
# ======================
step_ssl() {
    msg "configuracao ssl"
    if [ -z "${SITE_DOMAIN:-}" ]; then get_input "qual dominio?" SITE_DOMAIN; fi
    read -p "rodar certbot (portas 80/443 abertas)? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        dnf install -y certbot python3-certbot-apache
        get_input "email para notificacoes" CERT_EMAIL
        certbot --apache -d "$SITE_DOMAIN" --email "$CERT_EMAIL" --agree-tos --no-eff-email --redirect
    fi
    show_access_info
}

step_backup() {
    msg "configurando backup diario"
    mkdir -p "$BACKUP_DIR"
    cat > /usr/local/bin/simple_backup.sh <<'EOF'
#!/bin/bash
tar -czf /opt/backup/site_$(date +%F).tar.gz /var/www/html 2>/dev/null
find /opt/backup -name "*.tar.gz" -mtime +7 -delete
EOF
    chmod +x /usr/local/bin/simple_backup.sh
    echo "0 2 * * * root /usr/local/bin/simple_backup.sh" > /etc/cron.d/simple_backup
}

step_duckdns() {
    msg "configuracao duckdns"
    get_input "subdominio (sem 'duckdns.org')" DUCK_SUB
    get_input "token" DUCK_TOKEN
    mkdir -p /opt/duckdns
    echo "echo url=\"https://www.duckdns.org/update?domains=${DUCK_SUB}&token=${DUCK_TOKEN}&ip=\" | curl -k -K -" > /opt/duckdns/duck.sh
    chmod +x /opt/duckdns/duck.sh
    echo "*/5 * * * * root /opt/duckdns/duck.sh >/dev/null 2>&1" > /etc/cron.d/duckdns
}

step_show_info() {
    clear
    echo "=============================================="
    echo "       RESUMO DO SERVIDOR E LOGS"
    echo "=============================================="
    
    # Rede
    local priv_ip=$(hostname -I | awk '{print $1}')
    local pub_ip=$(curl -s -4 ifconfig.me)
    echo "[REDE]"
    echo "IP Privado: $priv_ip"
    echo "IP Publico: $pub_ip"
    echo ""

    # Arquivos Importantes
    echo "[ARQUIVOS MODIFICADOS/CRIADOS]"
    echo "Web Root:   $WEB_ROOT"
    
    # Tenta achar o arquivo de config do banco para mostrar onde esta
    DB_CONF=$(find "$WEB_ROOT" -maxdepth 3 -type f \( -name "*config*" -o -name "*db*" -o -name "*connect*" \) | grep ".php" | head -n 1)
    if [ -n "$DB_CONF" ]; then
        echo "DB Config:  $DB_CONF"
        echo "--> (Use 'cat $DB_CONF' para ver a senha do banco)"
    else
        echo "DB Config:  Nao detectado automaticamente."
    fi
    
    # VirtualHost
    VHOST=$(ls /etc/httpd/conf.d/*.conf 2>/dev/null | grep -v "auto" | grep -v "welcome" | head -n 1)
    echo "Apache Vhost: ${VHOST:-Nenhum criado ainda}"
    echo ""

    # Lembrete Router
    echo "[ROUTER PORT FORWARDING]"
    echo "Lembre-se de abrir estas portas no seu roteador para o IP $priv_ip:"
    echo "  - 80 (HTTP)"
    echo "  - 443 (HTTPS)"
    echo "  - Porta SSH (Padrao 22 ou a que voce mudou)"
    echo ""
    show_access_info
    echo ""


    # Logs de Erro
    echo "[ULTIMOS 5 ERROS DO APACHE (LOG)]"
    if [ -f /var/log/httpd/error_log ]; then
        tail -n 5 /var/log/httpd/error_log
    else
        echo "Log nao encontrado ou vazio."
    fi
    echo "=============================================="
}

# ======================
# MAIN LOGIC
# ======================
full_install() {
    echo "=== INSTALACAO COMPLETA ==="
    step_base_updates
    step_install_lamp
    step_security_basic
    step_deploy_site
    step_setup_db
    step_backup
    step_ssl
    echo ">>> FIM. lembre de abrir as portas no roteador."
    show_access_info
}

show_menu() {
    echo ""
    echo "===== SERVER MANAGER ====="
    echo "1. FULL INSTALL"
    echo "--------------------------"
    echo "2. Configurar IP Estatico"
    echo "3. Instalar LAMP"
    echo "4. Deploy Site"
    echo "5. Setup Banco"
    echo "6. Configurar SSL"
    echo "7. Seguranca Basica"
    echo "8. Harden SSH"
    echo "9. DuckDNS"
    echo "--------------------------"
    echo "10. Backup"
    echo "11. INFO E LOGS"
    echo "--------------------------"
    echo "0. Sair"
    echo "=========================="
    echo ""
}

check_root
while true; do
    show_menu
    read -p "Opcao: " op
    case $op in
        1) full_install ;;
        2) step_static_ip ;;
        3) step_base_updates; step_install_lamp ;;
        4) step_deploy_site ;;
        5) step_setup_db ;;
        6) step_ssl ;;
        7) step_security_basic ;;
        8) step_harden_ssh ;;
        9) step_duckdns ;;
        10) step_backup ;;
        11) step_show_info ;;
        0) exit 0 ;;
        *) echo "invalido" ;;
    esac
done
