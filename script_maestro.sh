#!/bin/bash

# Script maestro: Instala CTFd, clona ctf-comando y ejecuta su script.sh
# Uso: curl -s https://raw.githubusercontent.com/yleonardomt/comando_ctfd/main/script_maestro.sh | bash

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[1;35m'
BOLD='\033[1m'
NC='\033[0m'

print_message() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 1. VERIFICAR E INSTALAR DEPENDENCIAS ---
print_message "Verificando e instalando dependencias necesarias..."

if ! command -v git &> /dev/null; then
    print_warning "Git no está instalado. Instalando..."
    sudo apt-get update && sudo apt-get install -y git
    print_success "Git instalado correctamente."
else
    print_success "Git ya está instalado."
fi

if ! command -v docker &> /dev/null; then
    print_warning "Docker no está instalado. Instalando..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker "$USER"
    rm -f get-docker.sh
    print_success "Docker instalado correctamente."
else
    print_success "Docker ya está instalado."
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
    print_warning "Docker Compose no está instalado. Instalando..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    print_success "Docker Compose instalado correctamente."
else
    print_success "Docker Compose ya está instalado."
fi

# Detectar el comando correcto de Docker Compose
if command -v docker-compose &> /dev/null; then
    DC="docker-compose"
else
    DC="docker compose"
fi
print_message "Usando comando: '$DC'"

# --- 2. DESCARGAR EL ZIP DESDE EL REPOSITORIO ---
print_message "Descargando archivo ZIP de retos desde GitHub..."
ZIP_DEST="$HOME/ctfd_backup.zip"
ZIP_URL=$(curl -s "https://api.github.com/repos/yleonardomt/comando_ctfd/contents" \
    | grep -o '"download_url":"[^"]*\.zip"' | head -1 | cut -d'"' -f4)

if [ -z "$ZIP_URL" ]; then
    ZIP_URL="https://github.com/yleonardomt/comando_ctfd/raw/main/Comando.2026-06-24_22_02_06.zip"
fi

curl -L "$ZIP_URL" -o "$ZIP_DEST"
if [ -f "$ZIP_DEST" ] && [ -s "$ZIP_DEST" ]; then
    print_success "ZIP descargado en: $ZIP_DEST"
else
    print_error "No se pudo descargar el ZIP."
fi

# --- 3. LIMPIEZA TOTAL DE DOCKER Y PUERTO 80 ---
print_warning "Realizando limpieza total de Docker y puerto 80..."

# Parar y eliminar todos los contenedores
RUNNING=$(docker ps -q)
if [ -n "$RUNNING" ]; then
    print_message "Parando todos los contenedores activos..."
    docker stop $RUNNING
fi
ALL=$(docker ps -aq)
if [ -n "$ALL" ]; then
    print_message "Eliminando todos los contenedores..."
    docker rm -f $ALL
fi

# Eliminar redes Docker (libera puertos)
print_message "Eliminando redes Docker no usadas..."
docker network prune -f
print_success "Redes eliminadas."

# Matar servicios del sistema en puerto 80 (apache2, nginx, etc.)
for SERVICIO in apache2 nginx lighttpd; do
    if sudo systemctl is-active --quiet $SERVICIO 2>/dev/null; then
        print_message "Deteniendo servicio $SERVICIO..."
        sudo systemctl stop $SERVICIO
        sudo systemctl disable $SERVICIO
    fi
done

# Matar cualquier proceso que quede en puerto 80
if sudo lsof -i :80 &> /dev/null; then
    PID=$(sudo lsof -t -i :80 | tr '\n' ' ')
    print_message "Proceso en puerto 80 (PID: $PID), eliminando..."
    sudo kill -9 $PID 2>/dev/null || true
fi

sleep 3

# Verificar que el puerto quedó libre
if sudo lsof -i :80 &> /dev/null; then
    print_error "El puerto 80 sigue ocupado. Abortando."
    sudo lsof -i :80
    exit 1
fi

print_success "Puerto 80 completamente libre."

# --- 4. INSTALAR CTFd CON DOCKER EN PUERTO 80 ---
print_message "Iniciando instalación de CTFd..."

if [ -d "$HOME/CTFd" ]; then
    print_message "El directorio CTFd ya existe. Actualizando..."
    cd "$HOME/CTFd"
    git pull
else
    print_message "Clonando CTFd desde GitHub..."
    git clone https://github.com/CTFd/CTFd.git "$HOME/CTFd"
    cd "$HOME/CTFd"
    print_success "CTFd clonado correctamente."
fi

print_message "Configurando CTFd para usar el puerto 80..."
if grep -q "80:8000" docker-compose.yml; then
    print_success "El puerto ya está configurado para 80."
else
    cp docker-compose.yml docker-compose.yml.bak
    sed -i 's/- "8000:8000"/- "80:8000"/g' docker-compose.yml
    print_success "Puerto configurado a 80:8000."
fi

print_message "Iniciando CTFd con Docker Compose..."
$DC up -d --build

# Esperar y verificar que nginx arrancó
sleep 5
if docker ps --format '{{.Names}} {{.Ports}}' | grep -q "nginx"; then
    print_success "CTFd iniciado correctamente en http://localhost:80"
else
    print_error "CTFd nginx no arrancó correctamente. Revisando logs..."
    $DC logs nginx 2>/dev/null | tail -20
    exit 1
fi

cd "$HOME"

# --- 5. CLONAR REPOSITORIO ctf-comando Y EJECUTAR script.sh ---
print_message "Clonando el repositorio ctf-comando..."
if [ -d "$HOME/ctf-comando" ]; then
    print_message "El directorio ctf-comando ya existe. Actualizando..."
    cd "$HOME/ctf-comando"
    git pull
    cd "$HOME"
else
    git clone https://github.com/yleonardomt/ctf-comando.git "$HOME/ctf-comando"
    print_success "Repositorio ctf-comando clonado correctamente."
fi

print_message "Ejecutando script.sh del repositorio ctf-comando..."
cd "$HOME/ctf-comando"
if [ -f "script.sh" ]; then
    chmod +x script.sh
    ./script.sh
    print_success "script.sh ejecutado correctamente."
else
    print_error "No se encontró script.sh en el repositorio ctf-comando."
    exit 1
fi

cd "$HOME"

# --- 6. MENSAJE FINAL ---
echo ""
echo -e "${GREEN}${BOLD}=================================================================="
echo -e "       ✅  INSTALACIÓN COMPLETADA EXITOSAMENTE  ✅"
echo -e "==================================================================${NC}"
echo ""
echo -e "${CYAN}${BOLD}  🌐  CTFd corriendo en:  http://localhost:80${NC}"
echo -e "${CYAN}${BOLD}  🔐  Admin:  admin@admin.com  /  admin${NC}"
echo ""
echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════════╗"
echo -e "║                                                                  ║"
echo -e "║   ⚠️   ACCIÓN REQUERIDA POR EL ADMINISTRADOR   ⚠️                ║"
echo -e "║                                                                  ║"
echo -e "╠══════════════════════════════════════════════════════════════════╣"
echo -e "║                                                                  ║"
echo -e "║   📦  EL ZIP DE RETOS YA FUE DESCARGADO AQUÍ:                   ║"
echo -e "║                                                                  ║"
echo -e "║   ${MAGENTA}➡️   $ZIP_DEST${YELLOW}${BOLD}"
echo -e "║                                                                  ║"
echo -e "╠══════════════════════════════════════════════════════════════════╣"
echo -e "║                                                                  ║"
echo -e "║   PASOS PARA IMPORTAR EN CTFd:                                   ║"
echo -e "║                                                                  ║"
echo -e "║   1️⃣   Abre navegador  →  http://localhost:80                    ║"
echo -e "║   2️⃣   Inicia sesión:  admin@admin.com / admin                   ║"
echo -e "║   3️⃣   Panel Admin  →  busca 'Import' o 'Import Backup'          ║"
echo -e "║   4️⃣   Sube el archivo ZIP de la ruta indicada arriba            ║"
echo -e "║                                                                  ║"
echo -e "╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}${BOLD}📌 Comandos útiles:${NC}"
echo -e "   Ver logs  →  cd ~/CTFd && $DC logs -f"
echo -e "   Detener   →  cd ~/CTFd && $DC down"
echo -e "   Iniciar   →  cd ~/CTFd && $DC up -d"
echo ""
echo -e "${GREEN}${BOLD}==================================================================${NC}"