#!/bin/bash

# =====================================================
# FATURE DATABASE - SCRIPT DE SETUP
# Script para configuração inicial do ambiente
# =====================================================

set -e  # Parar em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções de log
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se está rodando como root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Este script não deve ser executado como root"
        exit 1
    fi
}

# Verificar dependências
check_dependencies() {
    log_info "Verificando dependências..."
    
    # Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker não está instalado. Instale o Docker primeiro."
        exit 1
    fi
    
    # Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose não está instalado. Instale o Docker Compose primeiro."
        exit 1
    fi
    
    # Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 não está instalado. Instale o Python 3 primeiro."
        exit 1
    fi
    
    # Git
    if ! command -v git &> /dev/null; then
        log_error "Git não está instalado. Instale o Git primeiro."
        exit 1
    fi
    
    log_success "Todas as dependências estão instaladas"
}

# Criar arquivo .env
create_env_file() {
    log_info "Criando arquivo de configuração..."
    
    if [ ! -f .env ]; then
        cp .env.example .env
        log_success "Arquivo .env criado a partir do .env.example"
        log_warning "Edite o arquivo .env com suas configurações específicas"
    else
        log_warning "Arquivo .env já existe, pulando criação"
    fi
}

# Criar diretórios necessários
create_directories() {
    log_info "Criando diretórios necessários..."
    
    mkdir -p logs
    mkdir -p data/postgres
    mkdir -p data/redis
    mkdir -p backups
    mkdir -p temp
    
    log_success "Diretórios criados"
}

# Configurar permissões
set_permissions() {
    log_info "Configurando permissões..."
    
    chmod +x scripts/*.py 2>/dev/null || true
    chmod +x *.sh 2>/dev/null || true
    
    log_success "Permissões configuradas"
}

# Instalar dependências Python
install_python_deps() {
    log_info "Instalando dependências Python..."
    
    if [ -f requirements.txt ]; then
        # Criar virtual environment se não existir
        if [ ! -d "venv" ]; then
            python3 -m venv venv
            log_success "Virtual environment criado"
        fi
        
        # Ativar virtual environment
        source venv/bin/activate
        
        # Instalar dependências
        pip install --upgrade pip
        pip install -r requirements.txt
        
        log_success "Dependências Python instaladas"
    else
        log_warning "Arquivo requirements.txt não encontrado"
    fi
}

# Inicializar banco de dados
init_database() {
    log_info "Inicializando banco de dados..."
    
    # Verificar se o Docker está rodando
    if ! docker info &> /dev/null; then
        log_error "Docker não está rodando. Inicie o Docker primeiro."
        exit 1
    fi
    
    # Iniciar serviços
    docker-compose up -d postgres redis
    
    # Aguardar serviços ficarem prontos
    log_info "Aguardando serviços ficarem prontos..."
    sleep 30
    
    # Verificar se PostgreSQL está pronto
    for i in {1..30}; do
        if docker-compose exec postgres pg_isready -U fature_user -d fature_db &> /dev/null; then
            log_success "PostgreSQL está pronto"
            break
        fi
        
        if [ $i -eq 30 ]; then
            log_error "PostgreSQL não ficou pronto em tempo hábil"
            exit 1
        fi
        
        sleep 2
    done
    
    # Verificar se Redis está pronto
    for i in {1..30}; do
        if docker-compose exec redis redis-cli ping &> /dev/null; then
            log_success "Redis está pronto"
            break
        fi
        
        if [ $i -eq 30 ]; then
            log_error "Redis não ficou pronto em tempo hábil"
            exit 1
        fi
        
        sleep 2
    done
}

# Executar scripts SQL
run_sql_scripts() {
    log_info "Executando scripts SQL..."
    
    # Lista de scripts na ordem correta
    scripts=(
        "sql/01_schema.sql"
        "sql/02_indexes.sql"
        "sql/03_views.sql"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            log_info "Executando $script..."
            docker-compose exec -T postgres psql -U fature_user -d fature_db -f "/docker-entrypoint-initdb.d/$(basename $script)"
            log_success "$script executado com sucesso"
        else
            log_warning "Script $script não encontrado"
        fi
    done
}

# Testar conexões
test_connections() {
    log_info "Testando conexões..."
    
    # Testar PostgreSQL
    if docker-compose exec postgres psql -U fature_user -d fature_db -c "SELECT 1;" &> /dev/null; then
        log_success "Conexão PostgreSQL OK"
    else
        log_error "Falha na conexão PostgreSQL"
        exit 1
    fi
    
    # Testar Redis
    if docker-compose exec redis redis-cli ping &> /dev/null; then
        log_success "Conexão Redis OK"
    else
        log_error "Falha na conexão Redis"
        exit 1
    fi
}

# Iniciar aplicação
start_application() {
    log_info "Iniciando aplicação..."
    
    docker-compose up -d
    
    log_success "Aplicação iniciada"
    log_info "Acesse:"
    log_info "  - API: http://localhost:5000"
    log_info "  - pgAdmin: http://localhost:8080"
    log_info "  - Redis Commander: http://localhost:8081"
}

# Mostrar status
show_status() {
    log_info "Status dos serviços:"
    docker-compose ps
}

# Menu principal
show_menu() {
    echo ""
    echo "======================================================="
    echo "           FATURE DATABASE - SETUP SCRIPT"
    echo "======================================================="
    echo ""
    echo "Escolha uma opção:"
    echo "1) Setup completo (recomendado para primeira instalação)"
    echo "2) Apenas verificar dependências"
    echo "3) Criar arquivo .env"
    echo "4) Instalar dependências Python"
    echo "5) Inicializar banco de dados"
    echo "6) Executar scripts SQL"
    echo "7) Testar conexões"
    echo "8) Iniciar aplicação"
    echo "9) Mostrar status"
    echo "0) Sair"
    echo ""
    read -p "Digite sua opção: " choice
}

# Função principal
main() {
    check_root
    
    case $1 in
        --full|--complete)
            log_info "Executando setup completo..."
            check_dependencies
            create_env_file
            create_directories
            set_permissions
            install_python_deps
            init_database
            run_sql_scripts
            test_connections
            start_application
            show_status
            log_success "Setup completo finalizado!"
            ;;
        --deps)
            check_dependencies
            ;;
        --env)
            create_env_file
            ;;
        --python)
            install_python_deps
            ;;
        --db)
            init_database
            ;;
        --sql)
            run_sql_scripts
            ;;
        --test)
            test_connections
            ;;
        --start)
            start_application
            ;;
        --status)
            show_status
            ;;
        --help|-h)
            echo "Uso: $0 [opção]"
            echo ""
            echo "Opções:"
            echo "  --full, --complete  Setup completo"
            echo "  --deps              Verificar dependências"
            echo "  --env               Criar arquivo .env"
            echo "  --python            Instalar dependências Python"
            echo "  --db                Inicializar banco de dados"
            echo "  --sql               Executar scripts SQL"
            echo "  --test              Testar conexões"
            echo "  --start             Iniciar aplicação"
            echo "  --status            Mostrar status"
            echo "  --help, -h          Mostrar esta ajuda"
            echo ""
            echo "Sem argumentos: Mostrar menu interativo"
            ;;
        *)
            # Menu interativo
            while true; do
                show_menu
                case $choice in
                    1)
                        check_dependencies
                        create_env_file
                        create_directories
                        set_permissions
                        install_python_deps
                        init_database
                        run_sql_scripts
                        test_connections
                        start_application
                        show_status
                        log_success "Setup completo finalizado!"
                        ;;
                    2) check_dependencies ;;
                    3) create_env_file ;;
                    4) install_python_deps ;;
                    5) init_database ;;
                    6) run_sql_scripts ;;
                    7) test_connections ;;
                    8) start_application ;;
                    9) show_status ;;
                    0) 
                        log_info "Saindo..."
                        exit 0
                        ;;
                    *)
                        log_error "Opção inválida"
                        ;;
                esac
                echo ""
                read -p "Pressione Enter para continuar..."
            done
            ;;
    esac
}

# Executar função principal
main "$@"

