#!/bin/bash
# ============================================================
# COMANDOS WP ENGINE - MULTI-SITE INSTALLER v2.7.0
# Поддержка нескольких сайтов на одном сервере
# ============================================================

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DEFAULT_CERT_RESOLVER="mytlschallenge"
BASE_DIR="$HOME/comandos"
SNAPSHOT_TAR="wordpress_data.tar.gz"
SNAPSHOT_DB="wordpress_db.sql.gz"
SNAPSHOT_URL="${COMANDOS_SNAPSHOT_URL:-}"
SNAPSHOT_DB_URL="${COMANDOS_SNAPSHOT_DB_URL:-}"
RESTORE_SNAPSHOT="${COMANDOS_RESTORE_SNAPSHOT:-false}"

print_logo() {
    echo -e "${BLUE}"
    cat << "EOF"
 ██████╗ ██████╗ ███╗   ███╗ █████╗ ███╗   ██╗██████╗  ██████╗ ███████╗   █████╗ ██╗
██╔════╝██╔═══██╗████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔═══██╗██╔════╝  ██╔══██╗██║
██║     ██║   ██║██╔████╔██║███████║██╔██╗ ██║██║  ██║██║   ██║███████╗  ███████║██║
██║     ██║   ██║██║╚██╔╝██║██╔══██║██║╚██╗██║██║  ██║██║   ██║╚════██║  ██╔══██║██║
╚██████╗╚██████╔╝██║ ╚═╝ ██║██║  ██║██║ ╚████║██████╔╝╚██████╔╝███████║  ██║  ██║██║
 ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝  ╚═════╝ ╚══════╝  ╚═╝  ╚═╝╚═╝
EOF
    echo -e "${NC}"
    echo -e "${YELLOW}                 POWERED BY COMANDOS AI — MULTI-SITE v2.7.0${NC}"
    echo
}

print_header() { echo -e "${BLUE}================================================${NC}\n${BLUE}  $1${NC}\n${BLUE}================================================${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ $1${NC}"; }

ask_user() {
    local prompt=$1 var_name=$2 extra_opt=$3
    if [ -c /dev/tty ]; then
        read $extra_opt -p "$prompt" "$var_name" < /dev/tty
    else
        read $extra_opt -p "$prompt" "$var_name"
    fi
}

clean_url() { echo "$1" | sed -e 's|^[^/]*//||' -e 's|/.*$||'; }
make_slug() {
    # LC_ALL=C обязателен чтобы tr не ломал многобайтовые UTF-8 символы
    local input="$1"
    # 1. Убираем все не-ASCII символы (кириллица, спецсимволы)
    local ascii
    ascii=$(echo "$input" | LC_ALL=C sed 's/[^[:print:]]//g' | sed 's/[^ -~]//g')
    # 2. Заменяем точки на дефисы, приводим к нижнему регистру
    echo "$ascii" | LC_ALL=C tr '[:upper:]' '[:lower:]' | tr '.' '-' \
        | sed 's/[^a-z0-9-]/-/g' \
        | sed 's/--*/-/g' \
        | sed 's/^-//;s/-$//'
}

mkdir -p "$BASE_DIR"
print_logo

# ──────────────────────────────────────────────────────────
# Проверка Docker
if ! command -v docker &> /dev/null; then
    print_warning "Docker не найден. Устанавливаю..."
    curl -fsSL https://get.docker.com | sh
fi

# ──────────────────────────────────────────────────────────
# Собираем список уже установленных сайтов
declare -a INSTALLED_SLUGS
declare -a INSTALLED_DOMAINS

for dir in "$BASE_DIR"/*/; do
    slug=$(basename "$dir")
    envfile="$dir.env"
    if [ -f "$envfile" ] && grep -q "WP_DOMAIN" "$envfile"; then
        domain=$(grep WP_DOMAIN "$envfile" | cut -d= -f2)
        INSTALLED_SLUGS+=("$slug")
        INSTALLED_DOMAINS+=("$domain")
    fi
done

# ──────────────────────────────────────────────────────────
# ГЛАВНОЕ МЕНЮ
print_header "ЧТО ХОТИТЕ СДЕЛАТЬ?"
echo -e "  ${GREEN}1)${NC} Установить новый сайт на новом поддомене"
echo -e "  ${YELLOW}2)${NC} Обновить существующий сайт (сохранить базу данных)"
echo -e "  ${RED}3)${NC} Переустановить существующий сайт (СТЕРЕТЬ ВСЁ)"
echo -e "  ${BLUE}4)${NC} Завершить настройку wordpress (тема, плагины и т.д.),если установка была прервана после входа в админку"
echo
ask_user "Выберите вариант (1/2/3/4): " MAIN_CHOICE

case "$MAIN_CHOICE" in
    1) ACTION="NEW" ;;
    2) ACTION="UPDATE" ;;
    3) ACTION="REINSTALL" ;;
    4) ACTION="FINISH" ;;
    *) print_error "Неверный выбор."; exit 1 ;;
esac

# ──────────────────────────────────────────────────────────
# Выбор существующего сайта (для UPDATE / REINSTALL)
if [ "$ACTION" == "UPDATE" ] || [ "$ACTION" == "REINSTALL" ] || [ "$ACTION" == "FINISH" ]; then
    if [ ${#INSTALLED_SLUGS[@]} -eq 0 ]; then
        print_error "Нет установленных сайтов Comandos в $BASE_DIR"
        exit 1
    fi

    echo
    print_header "ВЫБЕРИТЕ САЙТ"
    for i in "${!INSTALLED_SLUGS[@]}"; do
        num=$((i+1))
        status="⚫"
        if docker ps --format "{{.Names}}" | grep -q "comandos-wp-${INSTALLED_SLUGS[$i]}"; then
            status="${GREEN}●${NC} (запущен)"
        else
            status="${RED}●${NC} (остановлен)"
        fi
        echo -e "  ${YELLOW}$num)${NC} ${INSTALLED_DOMAINS[$i]} ${status}"
    done
    echo
    ask_user "Введите номер сайта: " SITE_NUM

    IDX=$((SITE_NUM-1))
    if [ -z "${INSTALLED_SLUGS[$IDX]}" ]; then
        print_error "Неверный номер."; exit 1
    fi

    SITE_SLUG="${INSTALLED_SLUGS[$IDX]}"
    PRODUCT_DIR="$BASE_DIR/$SITE_SLUG"
    source "$PRODUCT_DIR/.env"
    # WP_DOMAIN, SSL_EMAIL, DB_PASSWORD, CONTAINER_WP, CONTAINER_DB загружены из .env

    # ── Подтверждение выбранного сайта ─────────────────────
    echo
    print_warning "Выбран сайт: ${WP_DOMAIN}"
    ask_user "Всё верно? Продолжить? (y/n): " confirm_site
    if [[ ! $confirm_site =~ ^[Yy]$ ]]; then
        print_info "Отмена."; exit 0
    fi

    if [ "$ACTION" == "REINSTALL" ]; then
        print_error "ВНИМАНИЕ: Все данные сайта $WP_DOMAIN будут УДАЛЕНЫ!"
        ask_user "Вы уверены? (y/n): " confirm_reinstall
        if [[ ! $confirm_reinstall =~ ^[Yy]$ ]]; then
            print_info "Отмена."; exit 0
        fi
        MODE="INSTALL"
    elif [ "$ACTION" == "FINISH" ]; then
        MODE="FINISH"
        print_success "Режим ЗАВЕРШЕНИЯ НАСТРОЙКИ: $WP_DOMAIN"
    else
        MODE="UPDATE"
        print_success "Режим ОБНОВЛЕНИЯ: $WP_DOMAIN (данные сохранятся)"
    fi
fi

# ──────────────────────────────────────────────────────────
# Новый сайт — ввод домена
if [ "$ACTION" == "NEW" ]; then
    echo
    print_header "НОВЫЙ САЙТ"

    # Показываем занятые домены
    if [ ${#INSTALLED_DOMAINS[@]} -gt 0 ]; then
        print_info "Уже установлены:"
        for d in "${INSTALLED_DOMAINS[@]}"; do echo -e "   • $d"; done
        echo
    fi

    ask_user "Домен нового сайта (blog2.site.com): " RAW_WP
    WP_DOMAIN=$(clean_url "$RAW_WP")

    # Проверяем, не занят ли уже этот домен
    for d in "${INSTALLED_DOMAINS[@]}"; do
        if [ "$d" == "$WP_DOMAIN" ]; then
            print_error "Домен $WP_DOMAIN уже используется! Выберите пункт 2 или 3 для управления существующим сайтом."
            exit 1
        fi
    done

    SITE_SLUG=$(make_slug "$WP_DOMAIN")
    PRODUCT_DIR="$BASE_DIR/$SITE_SLUG"
    MODE="INSTALL"
    print_success "Новый сайт: $WP_DOMAIN"
    print_info "Директория: $PRODUCT_DIR"
fi

# ──────────────────────────────────────────────────────────
# Уникальные имена контейнеров для этого сайта (если не загружены из .env)
CONTAINER_WP="${CONTAINER_WP:-comandos-wp-${SITE_SLUG}}"
CONTAINER_DB="${CONTAINER_DB:-comandos-db-${SITE_SLUG}}"
VOLUME_DB="${SITE_SLUG}_comandos-db-data"
SNAPSHOT_DIR="$PRODUCT_DIR/snapshot"

mkdir -p "$PRODUCT_DIR"
cd "$PRODUCT_DIR" || exit 1

# ──────────────────────────────────────────────────────────
# SSL email (только при новой установке)
if [ "$MODE" == "INSTALL" ]; then
    ask_user "SSL Email: " SSL_EMAIL
    DB_PASSWORD=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')
fi

# ──────────────────────────────────────────────────────────
# FINISH — завершение прерванной установки (пропускаем все шаги деплоя)
if [ "$MODE" == "FINISH" ]; then
    print_header "ЗАВЕРШЕНИЕ НАСТРОЙКИ WORDPRESS: $WP_DOMAIN"

    ensure_wp_cli() {
        docker exec -u 0 "$CONTAINER_WP" bash -c '
          if [ ! -f /usr/local/bin/wp ]; then
            curl -sSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp
            chmod +x /usr/local/bin/wp
          fi
        '
    }

    ensure_wp_cli

    # Проверяем, установлен ли WordPress
    if docker exec "$CONTAINER_WP" bash -c "wp core is-installed --allow-root" > /dev/null 2>&1; then
        print_success "WordPress уже установлен через веб-интерфейс. Продолжаю настройку..."
    else
        print_warning "WordPress ещё не установлен через веб-интерфейс."
        echo -e "\n${BLUE}==============================================${NC}"
        echo -e "${YELLOW}ШАГ 1:${NC} Перейдите: ${GREEN}https://$WP_DOMAIN/wp-admin/install.php${NC}"
        echo -e "${YELLOW}ШАГ 2:${NC} Завершите установку WordPress (создайте администратора)."
        echo -e "${YELLOW}ШАГ 3:${NC} Вернитесь сюда и нажмите ${BLUE}[ENTER]${NC}."
        echo -e "${BLUE}==============================================${NC}"
        ask_user "Нажмите [ENTER] после завершения установки в браузере..." dummy
    fi

    THEME_NAME="comandos-ai-blog"
    THEME_DIR="/var/www/html/wp-content/themes/$THEME_NAME"

    # Копируем файлы темы из папки сайта в контейнер (если тема ещё не установлена)
    print_info "Копирование файлов темы в контейнер..."
    docker exec "$CONTAINER_WP" mkdir -p "$THEME_DIR"
    # Копируем только файлы темы (php, css, js, assets), исключая docker-compose и т.д.
    for f in style.css index.php functions.php header.php footer.php archive.php single.php search.php \
              commands-wp.css comandos-wp.css critical-desktop.css critical-mobile.css; do
        [ -f "$PRODUCT_DIR/$f" ] && docker cp "$PRODUCT_DIR/$f" "${CONTAINER_WP}:${THEME_DIR}/"
    done
    for d in js assets inc template-parts; do
        [ -d "$PRODUCT_DIR/$d" ] && docker cp "$PRODUCT_DIR/$d" "${CONTAINER_WP}:${THEME_DIR}/"
    done

    print_info "Активация темы $THEME_NAME..."
    if ! docker exec "$CONTAINER_WP" bash -c "wp theme activate $THEME_NAME --allow-root"; then
        print_warning "Пробую через SQL..."
        docker exec "$CONTAINER_DB" mysql -uwordpress -p"$DB_PASSWORD" wordpress -e \
            "UPDATE wp_options SET option_value = '$THEME_NAME' WHERE option_name IN ('template', 'stylesheet');"
    fi

    print_info "Установка и активация плагинов..."
    docker exec "$CONTAINER_WP" bash -c "wp plugin install wordpress-seo wp-graphql indexnow --activate --allow-root" || true
    docker exec "$CONTAINER_WP" bash -c "wp plugin install https://github.com/ashhitch/wp-graphql-yoast-seo/archive/refs/tags/v5.0.0.zip --activate --allow-root" || true

    print_info "Очистка дефолтного контента..."
    docker exec "$CONTAINER_WP" bash -c 'IDS=$(wp post list --post_type=post,page --format=ids --allow-root); [ -n "$IDS" ] && wp post delete $IDS --force --allow-root'
    docker exec "$CONTAINER_WP" bash -c 'CIDS=$(wp comment list --format=ids --allow-root); [ -n "$CIDS" ] && wp comment delete $CIDS --force --allow-root'
    docker exec "$CONTAINER_WP" bash -c 'wp plugin delete akismet hello --allow-root > /dev/null 2>&1 || true'
    docker exec "$CONTAINER_WP" bash -c "wp theme list --field=name --allow-root | grep -v \"^${THEME_NAME}$\" | xargs -r wp theme delete --allow-root" || true

    echo -e "\n"
    print_header "НАСТРОЙКА ЗАВЕРШЕНА!"
    print_info "WordPress:   https://$WP_DOMAIN/"
    print_info "Админка:     https://$WP_DOMAIN/wp-admin"
    print_info "Тема:        $THEME_NAME активирована"
    print_warning "Если дизайн не обновился — Ctrl+F5"
    echo -e "${BLUE}================================================${NC}"
    exit 0
fi


# ──────────────────────────────────────────────────────────
# Snapshot detection
if [ "$RESTORE_SNAPSHOT" == "true" ]; then
    if [ -f "$SNAPSHOT_DIR/$SNAPSHOT_TAR" ] && [ -f "$SNAPSHOT_DIR/$SNAPSHOT_DB" ]; then
        print_success "Найден локальный snapshot."
    elif [ -n "$SNAPSHOT_URL" ] && [ -n "$SNAPSHOT_DB_URL" ]; then
        print_info "Скачивание snapshot..."
        mkdir -p "$SNAPSHOT_DIR"
        curl -fsSL "$SNAPSHOT_URL" -o "$SNAPSHOT_DIR/$SNAPSHOT_TAR"
        curl -fsSL "$SNAPSHOT_DB_URL" -o "$SNAPSHOT_DIR/$SNAPSHOT_DB"
        if [ ! -s "$SNAPSHOT_DIR/$SNAPSHOT_TAR" ]; then
            print_warning "Snapshot не найден. Чистая установка."
            RESTORE_SNAPSHOT="false"
        fi
    else
        print_warning "RESTORE_SNAPSHOT=true, но snapshot не найден."
        RESTORE_SNAPSHOT="false"
    fi
fi

# ──────────────────────────────────────────────────────────
# Скачивание компонентов
print_header "ЗАГРУЗКА КОМПОНЕНТОВ..."
GITHUB_BASE="https://raw.githubusercontent.com/Comandosai/comandos-deploy-hub/main/wp-stack"

download_if_missing() {
    local file=$1
    local dir=$(dirname "$file")
    [ "$dir" != "." ] && mkdir -p "$dir"
    print_info "Загрузка $file..."
    curl -sL "$GITHUB_BASE/$file" -o "$file"
    if [ ! -s "$file" ]; then
        print_error "Не удалось скачать: $file"
        exit 1
    fi
}

FILES=(
    "docker-compose.yml.j2" "comandos-wp.css" "user-guide.md.j2" ".htaccess"
    "functions.php" "header.php" "footer.php" "index.php" "single.php"
    "style.css" "critical-desktop.css" "critical-mobile.css" "archive.php" "search.php"
    "inc/critical-css.php" "inc/customizer.php" "inc/enqueue.php"
    "inc/optimization.php" "inc/performance.php" "inc/setup.php"
    "template-parts/header/branding.php" "template-parts/header/navigation.php"
    "template-parts/header/search.php"
    "assets/fonts/unbounded-900.woff2" "assets/fonts/inter-400-subset.woff2"
    "assets/fonts/inter-700-subset.woff2" "assets/fonts/inter-800-subset.woff2"
    "assets/fonts/inter-900-subset.woff2" "js/customize-preview.js"
)

for file in "${FILES[@]}"; do
    download_if_missing "$file"
done

# ──────────────────────────────────────────────────────────
# Генерация .env и docker-compose
if [ "$MODE" == "INSTALL" ]; then
    print_header "ГЕНЕРАЦИЯ КОНФИГУРАЦИИ..."
    cat << EOF_ENV > .env
WP_DOMAIN=$WP_DOMAIN
SSL_EMAIL=$SSL_EMAIL
DB_PASSWORD=$DB_PASSWORD
SITE_SLUG=$SITE_SLUG
CONTAINER_WP=$CONTAINER_WP
CONTAINER_DB=$CONTAINER_DB
EOF_ENV
fi

escape_sed() { printf '%s' "$1" | sed -e 's/[|&]/\\&/g'; }
WP_DOMAIN_ESC=$(escape_sed "$WP_DOMAIN")
SSL_EMAIL_ESC=$(escape_sed "$SSL_EMAIL")
DB_PASSWORD_ESC=$(escape_sed "$DB_PASSWORD")
CONTAINER_WP_ESC=$(escape_sed "$CONTAINER_WP")
CONTAINER_DB_ESC=$(escape_sed "$CONTAINER_DB")

# Глобальная замена: сначала db, потом wp (порядок важен)
# Заменяет ВСЕ вхождения: service names, container_name, depends_on, traefik labels, DB_HOST и т.д.
sed -e "s|{{WP_DOMAIN}}|$WP_DOMAIN_ESC|g" \
    -e "s|{{SSL_EMAIL}}|$SSL_EMAIL_ESC|g" \
    -e "s|{{DB_PASSWORD}}|$DB_PASSWORD_ESC|g" \
    -e "s|comandos-db|$CONTAINER_DB_ESC|g" \
    -e "s|comandos-wp|$CONTAINER_WP_ESC|g" \
    docker-compose.yml.j2 > docker-compose.yml

sed -e "s|{{WP_DOMAIN}}|$WP_DOMAIN_ESC|g" user-guide.md.j2 > user-guide.md

# ──────────────────────────────────────────────────────────
# Очистка (только при переустановке)
if [ "$MODE" == "INSTALL" ] && [ "$ACTION" == "REINSTALL" ]; then
    print_warning "Удаление контейнеров и данных сайта $WP_DOMAIN..."
    docker rm -f "$CONTAINER_DB" "$CONTAINER_WP" 2>/dev/null || true
    docker volume ls -q | grep -Fx "$VOLUME_DB" > /dev/null 2>&1 && \
        docker volume rm "$VOLUME_DB" > /dev/null 2>&1 || true
elif [ "$MODE" == "INSTALL" ] && [ "$ACTION" == "NEW" ]; then
    # На случай мусора от предыдущей неудачной установки
    docker rm -f "$CONTAINER_DB" "$CONTAINER_WP" 2>/dev/null || true
fi

# ──────────────────────────────────────────────────────────
# Сеть
print_info "Проверка сети comandos-network..."
if ! docker network inspect comandos-network > /dev/null 2>&1; then
    docker network create comandos-network > /dev/null
fi

# ──────────────────────────────────────────────────────────
# Обновление образов и запуск
print_info "Обновление образов..."
docker compose pull > /dev/null 2>&1 || true
print_success "Запуск контейнеров..."
docker compose up -d

# ──────────────────────────────────────────────────────────
# WP-CLI helper
wait_for_db() {
    local tries=30
    while ! docker exec "$CONTAINER_DB" mysqladmin ping -uwordpress -p"$DB_PASSWORD" --silent > /dev/null 2>&1; do
        tries=$((tries-1))
        [ $tries -le 0 ] && { print_warning "DB не отвечает, продолжаю."; return 1; }
        sleep 2
    done
}

ensure_wp_cli() {
    docker exec -u 0 "$CONTAINER_WP" bash -c '
      if [ ! -f /usr/local/bin/wp ]; then
        curl -sSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp
        chmod +x /usr/local/bin/wp
      fi
    '
}

# ──────────────────────────────────────────────────────────
# Восстановление из snapshot
if [ "$MODE" == "INSTALL" ] && [ "$RESTORE_SNAPSHOT" == "true" ]; then
    print_header "ВОССТАНОВЛЕНИЕ ИЗ SNAPSHOT..."
    wait_for_db
    docker exec "$CONTAINER_WP" bash -c "rm -rf /var/www/html/* /var/www/html/.[!.]* /var/www/html/..?*"
    docker cp "$SNAPSHOT_DIR/$SNAPSHOT_TAR" "$CONTAINER_WP":/tmp/wordpress_data.tar.gz
    docker exec "$CONTAINER_WP" bash -c "tar -xzf /tmp/wordpress_data.tar.gz -C /var/www/html && rm -f /tmp/wordpress_data.tar.gz"
    docker exec -u 0 "$CONTAINER_WP" chown -R www-data:www-data /var/www/html
    docker exec "$CONTAINER_DB" mysql -uroot -p"$DB_PASSWORD" -e \
        "DROP DATABASE IF EXISTS wordpress; CREATE DATABASE wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; GRANT ALL ON wordpress.* TO 'wordpress'@'%'; FLUSH PRIVILEGES;"
    docker cp "$SNAPSHOT_DIR/$SNAPSHOT_DB" "$CONTAINER_DB":/tmp/wordpress_db.sql.gz
    docker exec "$CONTAINER_DB" bash -c "gunzip -c /tmp/wordpress_db.sql.gz | mysql -uwordpress -p\"$DB_PASSWORD\" wordpress"
    docker exec "$CONTAINER_DB" rm -f /tmp/wordpress_db.sql.gz
    ensure_wp_cli
    OLD_URL=$(docker exec "$CONTAINER_WP" bash -c "wp option get home --allow-root" || true)
    if [ -n "$OLD_URL" ]; then
        print_info "Обновление домена: $OLD_URL → https://$WP_DOMAIN"
        docker exec "$CONTAINER_WP" bash -c "wp search-replace \"$OLD_URL\" \"https://$WP_DOMAIN\" --all-tables --skip-columns=guid --allow-root"
        docker exec "$CONTAINER_WP" bash -c "wp option update home \"https://$WP_DOMAIN\" --allow-root"
        docker exec "$CONTAINER_WP" bash -c "wp option update siteurl \"https://$WP_DOMAIN\" --allow-root"
        docker exec "$CONTAINER_WP" bash -c "wp rewrite flush --hard --allow-root"
    fi
fi

# ──────────────────────────────────────────────────────────
# Оптимизация Lighthouse
if [ "$RESTORE_SNAPSHOT" != "true" ]; then
print_header "ОПТИМИЗАЦИЯ ПРОИЗВОДИТЕЛЬНОСТИ (Lighthouse 98+)..."
docker exec "$CONTAINER_WP" bash -c 'cat <<EOF > .htaccess
# Comandos Optimization: Browser Caching (v4.1 Immutable)
<IfModule mod_expires.c>
  ExpiresActive On
  ExpiresDefault "access plus 1 year"
  ExpiresByType image/jpg "access plus 1 year"
  ExpiresByType image/jpeg "access plus 1 year"
  ExpiresByType image/gif "access plus 1 year"
  ExpiresByType image/png "access plus 1 year"
  ExpiresByType image/webp "access plus 1 year"
  ExpiresByType image/x-icon "access plus 1 year"
  ExpiresByType text/css "access plus 1 year"
  ExpiresByType application/javascript "access plus 1 year"
  ExpiresByType font/woff2 "access plus 1 year"
</IfModule>
<IfModule mod_headers.c>
  <FilesMatch "\.(ico|pdf|flv|jpg|jpeg|png|gif|webp|js|css|swf|woff2)$">
    Header set Cache-Control "max-age=31536000, public, immutable"
  </FilesMatch>
</IfModule>
<IfModule mod_deflate.c>
  AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css application/javascript application/x-javascript application/json font/woff2
</IfModule>
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
EOF' || true
fi

# ──────────────────────────────────────────────────────────
# Настройка Traefik
print_header "НАСТРОЙКА TRAEFIK..."
TRAEFIK_ID=$(docker ps --format '{{.ID}} {{.Names}}' | awk 'tolower($2) ~ /traefik/ {print $1; exit}')

if [ -z "$TRAEFIK_ID" ]; then
    print_warning "Traefik не найден."
    if [ "$MODE" == "INSTALL" ]; then
        ask_user "Установить Traefik? (y/n): " install_traefik_choice
        if [[ $install_traefik_choice =~ ^[Yy]$ ]]; then
            SSL_EMAIL_TRAEFIK="${SSL_EMAIL:-admin@example.com}"
            mkdir -p "$BASE_DIR/traefik/dynamic"
            touch "$BASE_DIR/traefik/acme.json"
            chmod 600 "$BASE_DIR/traefik/acme.json"
            cat << EOF_TRAEFIK > "$BASE_DIR/traefik/docker-compose.yml"
version: '3'
services:
  traefik:
    image: traefik:latest
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - comandos-network
    ports:
      - 80:80
      - 443:443
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./acme.json:/acme.json
      - ./dynamic:/dynamic_conf
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.file.directory=/dynamic_conf"
      - "--providers.file.watch=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.myresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.myresolver.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.myresolver.acme.email=${SSL_EMAIL_TRAEFIK}"
      - "--certificatesresolvers.myresolver.acme.storage=/acme.json"
networks:
  comandos-network:
    external: true
EOF_TRAEFIK
            docker compose -f "$BASE_DIR/traefik/docker-compose.yml" up -d
            TRAEFIK_ID=$(docker ps --format '{{.ID}}' --filter "name=traefik")
            print_success "Traefik запущен!"
            sleep 10
        fi
    fi
fi

if [ -n "$TRAEFIK_ID" ]; then
    docker network connect comandos-network "$TRAEFIK_ID" 2>/dev/null || true

    # Сначала определяем DYNAMIC_DIR (нужен для поиска certResolver)
    if [ ! -z "$install_traefik_choice" ] && [[ $install_traefik_choice =~ ^[Yy]$ ]]; then
        DYNAMIC_DIR="$BASE_DIR/traefik/dynamic"
    else
        DYNAMIC_DIR=$(docker inspect "$TRAEFIK_ID" --format '{{range .Mounts}}{{printf "%s|%s\n" .Destination .Source}}{{end}}' \
            | awk -F'|' '$1 ~ /traefik/ && $1 ~ /dynamic/ {print $2; exit}')
    fi
    DYNAMIC_DIR="${DYNAMIC_DIR:-/root/traefik-dynamic}"
    mkdir -p "$DYNAMIC_DIR"

    # Определяем certResolver: из конфига контейнера → из yml-файлов dynamic → из логов → дефолт
    TRAEFIK_RESOLVER=$(docker inspect "$TRAEFIK_ID" --format '{{json .Config.Cmd}} {{json .Config.Entrypoint}}' \
        | tr -d '[],' | tr ' ' '\n' | grep -oE -- 'certificatesresolvers\.[^=. "]+' | head -n1 | sed 's/certificatesresolvers\.//')
    if [ -z "$TRAEFIK_RESOLVER" ] && [ -d "$DYNAMIC_DIR" ]; then
        TRAEFIK_RESOLVER=$(grep -rh 'certResolver:' "$DYNAMIC_DIR" 2>/dev/null | head -n1 | awk '{print $2}' | tr -d '"\r')
    fi
    if [ -z "$TRAEFIK_RESOLVER" ]; then
        for known in "mytlschallenge" "myresolver" "letsencrypt" "comandos-resolver"; do
            docker logs --tail 100 "$TRAEFIK_ID" 2>&1 | grep -q "$known" && { TRAEFIK_RESOLVER="$known"; break; }
        done
    fi
    TRAEFIK_RESOLVER="${TRAEFIK_RESOLVER:-$DEFAULT_CERT_RESOLVER}"

    # Отдельный файл маршрута для каждого сайта
    cat << EOF_YAML > "$DYNAMIC_DIR/comandos-${SITE_SLUG}.yml"
http:
  routers:
    comandos-${SITE_SLUG}:
      rule: "Host(\`${WP_DOMAIN}\`)"
      entryPoints:
        - websecure
      tls:
        certResolver: ${TRAEFIK_RESOLVER}
      service: comandos-${SITE_SLUG}
  services:
    comandos-${SITE_SLUG}:
      loadBalancer:
        servers:
          - url: "http://${CONTAINER_WP}:80"
EOF_YAML
    print_success "Маршрут Traefik: $DYNAMIC_DIR/comandos-${SITE_SLUG}.yml"
fi

# ──────────────────────────────────────────────────────────
# Тема и плагины
if [ "$RESTORE_SNAPSHOT" != "true" ]; then
print_header "ПОДГОТОВКА ТЕМЫ И ПЛАГИНОВ COMANDOS..."

THEME_NAME="comandos-ai-blog"
THEME_DIR="/var/www/html/wp-content/themes/$THEME_NAME"
docker exec "$CONTAINER_WP" mkdir -p "$THEME_DIR"

sync_file() {
    local src=$1 dest=$2
    [ -f "$src" ] && docker cp "$src" "$CONTAINER_WP":"$dest" && docker exec "$CONTAINER_WP" chown www-data:www-data "$dest"
}

sync_file "comandos-wp.css"       "$THEME_DIR/comandos-wp.css"
sync_file "functions.php"         "$THEME_DIR/functions.php"
sync_file "single.php"            "$THEME_DIR/single.php"
sync_file "header.php"            "$THEME_DIR/header.php"
sync_file "footer.php"            "$THEME_DIR/footer.php"
sync_file "index.php"             "$THEME_DIR/index.php"
sync_file "archive.php"           "$THEME_DIR/archive.php"
sync_file "search.php"            "$THEME_DIR/search.php"
sync_file "style.css"             "$THEME_DIR/style.css"
sync_file "critical-desktop.css"  "$THEME_DIR/critical-desktop.css"
sync_file "critical-mobile.css"   "$THEME_DIR/critical-mobile.css"
sync_file ".htaccess"             "/var/www/html/.htaccess"

[ -d "inc" ]            && docker cp inc/            "$CONTAINER_WP":"$THEME_DIR/"
[ -d "assets" ]         && docker cp assets/         "$CONTAINER_WP":"$THEME_DIR/"
[ -d "template-parts" ] && docker cp template-parts/ "$CONTAINER_WP":"$THEME_DIR/"
[ -d "js" ]             && docker cp js/             "$CONTAINER_WP":"$THEME_DIR/"

docker exec "$CONTAINER_WP" chown -R www-data:www-data "$THEME_DIR"

if [ "$MODE" == "INSTALL" ]; then
    echo -e "\n${BLUE}==============================================${NC}"
    echo -e "${YELLOW}ШАГ 1:${NC} Перейдите: ${GREEN}https://$WP_DOMAIN/wp-admin/install.php${NC}"
    echo -e "${YELLOW}ШАГ 2:${NC} Завершите установку WordPress (создайте админа)."
    echo -e "${YELLOW}ШАГ 3:${NC} Вернитесь сюда и нажмите ${BLUE}[ENTER]${NC}."
    echo -e "${BLUE}==============================================${NC}"
    ask_user "Нажмите [ENTER] после завершения установки..." dummy

    ensure_wp_cli

    print_info "Активация темы..."
    if ! docker exec "$CONTAINER_WP" bash -c "wp theme activate $THEME_NAME --allow-root"; then
        print_warning "Через SQL..."
        docker exec "$CONTAINER_DB" mysql -uwordpress -p"$DB_PASSWORD" wordpress -e \
            "UPDATE wp_options SET option_value = '$THEME_NAME' WHERE option_name IN ('template', 'stylesheet');"
    fi

    print_info "Установка плагинов..."
    docker exec "$CONTAINER_WP" bash -c "wp plugin install wordpress-seo wp-graphql indexnow --activate --allow-root" || true
    docker exec "$CONTAINER_WP" bash -c "wp plugin install https://github.com/ashhitch/wp-graphql-yoast-seo/archive/refs/tags/v5.0.0.zip --activate --allow-root" || true

    print_info "Очистка дефолтного контента..."
    docker exec "$CONTAINER_WP" bash -c 'IDS=$(wp post list --post_type=post,page --format=ids --allow-root); [ -n "$IDS" ] && wp post delete $IDS --force --allow-root'
    docker exec "$CONTAINER_WP" bash -c 'CIDS=$(wp comment list --format=ids --allow-root); [ -n "$CIDS" ] && wp comment delete $CIDS --force --allow-root'
    docker exec "$CONTAINER_WP" bash -c 'wp plugin delete akismet hello --allow-root > /dev/null 2>&1 || true'
    docker exec "$CONTAINER_WP" bash -c "wp theme list --field=name --allow-root | grep -v \"^${THEME_NAME}$\" | xargs -r wp theme delete --allow-root" || true
fi
fi

# ──────────────────────────────────────────────────────────
# Финализация
echo -e "\n"
print_header "СИСТЕМА ГОТОВА!"
print_info "WordPress:   https://$WP_DOMAIN/"
print_info "Админка:     https://$WP_DOMAIN/wp-admin"
print_info "Контейнер:   $CONTAINER_WP"
print_info "Base dir:    $PRODUCT_DIR"
[ "$RESTORE_SNAPSHOT" == "true" ] && print_info "Режим: Клон (snapshot)" || print_info "Тема: Comandos AI Blog Premium v2.7.0"
print_warning "Если дизайн не обновился — Ctrl+F5"
echo
print_info "Все сайты Comandos:"
docker ps --format "  • {{.Names}}: запущен" | grep "comandos-wp-" || true
docker ps -a --format "  • {{.Names}}: {{.Status}}" | grep "comandos-wp-" | grep -v "Up" || true
echo -e "${BLUE}================================================${NC}"
