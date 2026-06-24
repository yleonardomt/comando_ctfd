#!/bin/bash

# Script maestro: Instala CTFd, clona ctf-comando y ejecuta su script.sh
# Uso: curl -s https://raw.githubusercontent.com/yleonardomt/comando_ctfd/main/script_maestro.sh | bash

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# --- 2. LIMPIEZA TOTAL DE DOCKER ---
print_warning "Realizando limpieza total de Docker..."

# Parar todos los contenedores corriendo
RUNNING=$(docker ps -q)
if [ -n "$RUNNING" ]; then
    print_message "Parando todos los contenedores activos..."
    docker stop $RUNNING
    print_success "Contenedores parados."
fi

# Eliminar todos los contenedores (activos y parados)
ALL=$(docker ps -aq)
if [ -n "$ALL" ]; then
    print_message "Eliminando todos los contenedores..."
    docker rm -f $ALL
    print_success "Contenedores eliminados."
fi

# Eliminar redes no usadas (libera puertos atrapados)
print_message "Eliminando redes Docker no usadas..."
docker network prune -f
print_success "Redes eliminadas."

# Matar cualquier proceso del sistema en puerto 80
if sudo lsof -i :80 &> /dev/null; then
    PID=$(sudo lsof -t -i :80 | tr '\n' ' ')
    print_message "Proceso del sistema en puerto 80 (PID: $PID), eliminando..."
    sudo kill -9 $PID 2>/dev/null || true
    sleep 1
fi

print_success "Puerto 80 completamente libre."
sleep 2

# --- 3. INSTALAR CTFd CON DOCKER EN PUERTO 80 ---
print_message "Iniciando instalación de CTFd..."

if [ -d "CTFd" ]; then
    print_message "El directorio CTFd ya existe. Actualizando..."
    cd CTFd
    git pull
    cd ..
else
    print_message "Clonando CTFd desde GitHub..."
    git clone https://github.com/CTFd/CTFd.git
    print_success "CTFd clonado correctamente."
fi

cd CTFd

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
print_success "CTFd iniciado correctamente en http://localhost:80"
cd ..

# --- 4. CLONAR REPOSITORIO ctf-comando Y EJECUTAR script.sh ---
print_message "Clonando el repositorio ctf-comando..."
if [ -d "ctf-comando" ]; then
    print_message "El directorio ctf-comando ya existe. Actualizando..."
    cd ctf-comando
    git pull
    cd ..
else
    git clone https://github.com/yleonardomt/ctf-comando.git
    print_success "Repositorio ctf-comando clonado correctamente."
fi

print_message "Ejecutando script.sh del repositorio ctf-comando..."
cd ctf-comando
if [ -f "script.sh" ]; then
    chmod +x script.sh
    ./script.sh
    print_success "script.sh ejecutado correctamente."
else
    print_error "No se encontró script.sh en el repositorio ctf-comando."
    exit 1
fi
cd ..

# --- 5. MENSAJE FINAL ---
echo ""
print_success "==================== INSTALACIÓN COMPLETADA ===================="
echo ""
print_message "🌐 CTFd está corriendo en: http://localhost:80"
print_message "🔐 Credenciales de administrador: admin@admin.com / admin"
echo ""
print_warning "📦 IMPORTANTE PARA EL ADMINISTRADOR:"
print_message "   Debes subir manualmente el archivo ZIP con los retos."
print_message "   Ubicación esperada del ZIP en este servidor:"
print_message "   $(pwd)/ctf-comando/ (busca el archivo .zip)"
echo ""
print_message "   Pasos para importar:"
print_message "   1. Ve a http://localhost:80 y inicia sesión como admin"
print_message "   2. Entra al panel de administración"
print_message "   3. Busca la opción 'Importar' o 'Import Backup'"
print_message "   4. Selecciona el archivo ZIP y súbelo"
echo ""
print_message "📌 Comandos útiles para gestionar CTFd:"
print_message "   - Ver logs: cd CTFd && $DC logs -f"
print_message "   - Detener:  cd CTFd && $DC down"
print_message "   - Iniciar:  cd CTFd && $DC up -d"
echo ""
print_success "=================================================================="