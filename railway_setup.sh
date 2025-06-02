#!/bin/bash

# =====================================================
# FATURE DATABASE - RAILWAY AUTO SETUP SCRIPT
# Script para configuração automática no Railway
# =====================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Verificar se Railway CLI está instalado
check_railway_cli() {
    if ! command -v railway &> /dev/null; then
        log_error "Railway CLI não está instalado."
        log_info "Instale com: npm install -g @railway/cli"
        exit 1
    fi
    log_success "Railway CLI encontrado"
}

# Fazer login no Railway
railway_login() {
    log_info "Fazendo login no Railway..."
    if ! railway whoami &> /dev/null; then
        railway login
        log_success "Login realizado com sucesso"
    else
        log_success "Já logado no Railway"
    fi
}

# Criar projeto no Railway
create_railway_project() {
    log_info "Criando projeto no Railway..."
    
    # Verificar se já está linkado a um projeto
    if railway status &> /dev/null; then
        log_warning "Projeto já está linkado ao Railway"
        return
    fi
    
    # Criar novo projeto
    railway login
    railway link
    
    log_success "Projeto criado e linkado com sucesso"
}

# Adicionar PostgreSQL
add_postgresql() {
    log_info "Adicionando PostgreSQL ao projeto..."
    
    # Verificar se PostgreSQL já existe
    if railway variables | grep -q "DATABASE_URL"; then
        log_warning "PostgreSQL já está configurado"
        return
    fi
    
    # Adicionar PostgreSQL
    railway add --database postgresql
    
    log_success "PostgreSQL adicionado com sucesso"
}

# Adicionar Redis
add_redis() {
    log_info "Adicionando Redis ao projeto..."
    
    # Verificar se Redis já existe
    if railway variables | grep -q "REDIS_URL"; then
        log_warning "Redis já está configurado"
        return
    fi
    
    # Adicionar Redis
    railway add --database redis
    
    log_success "Redis adicionado com sucesso"
}

# Configurar variáveis de ambiente
setup_environment_variables() {
    log_info "Configurando variáveis de ambiente..."
    
    # Gerar chaves seguras
    SECRET_KEY=$(openssl rand -hex 32)
    JWT_SECRET=$(openssl rand -hex 32)
    ENCRYPTION_KEY=$(openssl rand -hex 32)
    
    # Configurar variáveis essenciais
    railway variables set FLASK_ENV=production
    railway variables set FLASK_DEBUG=0
    railway variables set SECRET_KEY="$SECRET_KEY"
    railway variables set JWT_SECRET_KEY="$JWT_SECRET"
    railway variables set ENCRYPTION_KEY="$ENCRYPTION_KEY"
    railway variables set LOG_LEVEL=INFO
    railway variables set METRICS_ENABLED=true
    railway variables set CACHE_TTL_SHORT=300
    railway variables set CACHE_TTL_MEDIUM=1800
    railway variables set CACHE_TTL_LONG=3600
    railway variables set CACHE_TTL_VERY_LONG=86400
    
    log_success "Variáveis de ambiente configuradas"
    
    # Salvar chaves em arquivo local (para backup)
    cat > .railway_secrets << EOF
# RAILWAY SECRETS - BACKUP
# Gerado em: $(date)
SECRET_KEY=$SECRET_KEY
JWT_SECRET_KEY=$JWT_SECRET
ENCRYPTION_KEY=$ENCRYPTION_KEY
EOF
    
    log_warning "Chaves salvas em .railway_secrets (mantenha seguro!)"
}

# Fazer deploy
deploy_application() {
    log_info "Fazendo deploy da aplicação..."
    
    # Fazer deploy
    railway up --detach
    
    log_success "Deploy iniciado com sucesso"
    log_info "Acompanhe o progresso com: railway logs --follow"
}

# Aguardar deploy e verificar saúde
wait_and_check_health() {
    log_info "Aguardando deploy completar..."
    
    # Aguardar um tempo para o deploy
    sleep 60
    
    # Obter URL da aplicação
    APP_URL=$(railway domain)
    
    if [ -z "$APP_URL" ]; then
        log_warning "URL da aplicação não encontrada. Configure um domínio."
        return
    fi
    
    log_info "Verificando saúde da aplicação em: $APP_URL"
    
    # Verificar health check
    for i in {1..10}; do
        if curl -f "$APP_URL/health" &> /dev/null; then
            log_success "Aplicação está saudável!"
            log_info "URL da aplicação: $APP_URL"
            return
        fi
        
        log_info "Tentativa $i/10 - Aguardando aplicação ficar pronta..."
        sleep 30
    done
    
    log_error "Aplicação não respondeu ao health check"
    log_info "Verifique os logs com: railway logs"
}

# Executar scripts SQL iniciais
setup_database_schema() {
    log_info "Configurando schema do banco de dados..."
    
    # Verificar se DATABASE_URL está disponível
    if ! railway variables | grep -q "DATABASE_URL"; then
        log_error "DATABASE_URL não encontrada. Adicione PostgreSQL primeiro."
        return 1
    fi
    
    # Executar scripts SQL
    log_info "Executando script de schema..."
    railway run psql \$DATABASE_URL -f sql/01_schema.sql
    
    log_info "Executando script de índices..."
    railway run psql \$DATABASE_URL -f sql/02_indexes.sql
    
    log_info "Executando script de views..."
    railway run psql \$DATABASE_URL -f sql/03_views.sql
    
    log_success "Schema do banco configurado com sucesso"
}

# Mostrar informações finais
show_final_info() {
    log_success "Setup do Railway concluído com sucesso!"
    echo ""
    echo "======================================================="
    echo "           INFORMAÇÕES DO DEPLOYMENT"
    echo "======================================================="
    echo ""
    
    # Mostrar URL da aplicação
    APP_URL=$(railway domain 2>/dev/null || echo "Não configurado")
    echo "🌐 URL da Aplicação: $APP_URL"
    
    # Mostrar variáveis importantes
    echo ""
    echo "📋 Variáveis Configuradas:"
    railway variables | grep -E "(FLASK_ENV|DATABASE_URL|REDIS_URL)" || true
    
    echo ""
    echo "🔧 Comandos Úteis:"
    echo "  railway logs --follow    # Ver logs em tempo real"
    echo "  railway status          # Status do projeto"
    echo "  railway domain          # Configurar domínio"
    echo "  railway variables       # Ver todas as variáveis"
    
    echo ""
    echo "🧪 Endpoints para Testar:"
    if [ "$APP_URL" != "Não configurado" ]; then
        echo "  $APP_URL/health"
        echo "  $APP_URL/api/dashboard"
        echo "  $APP_URL/api/affiliates"
        echo "  $APP_URL/api/cache/stats"
    fi
    
    echo ""
    log_warning "Mantenha o arquivo .railway_secrets seguro!"
}

# Menu principal
show_menu() {
    echo ""
    echo "======================================================="
    echo "        FATURE DATABASE - RAILWAY SETUP"
    echo "======================================================="
    echo ""
    echo "Escolha uma opção:"
    echo "1) Setup completo (recomendado)"
    echo "2) Apenas verificar Railway CLI"
    echo "3) Criar projeto Railway"
    echo "4) Adicionar PostgreSQL"
    echo "5) Adicionar Redis"
    echo "6) Configurar variáveis de ambiente"
    echo "7) Fazer deploy"
    echo "8) Configurar schema do banco"
    echo "9) Verificar status"
    echo "0) Sair"
    echo ""
    read -p "Digite sua opção: " choice
}

# Função principal
main() {
    case $1 in
        --full|--complete)
            log_info "Executando setup completo do Railway..."
            check_railway_cli
            railway_login
            create_railway_project
            add_postgresql
            add_redis
            setup_environment_variables
            deploy_application
            wait_and_check_health
            setup_database_schema
            show_final_info
            ;;
        --check)
            check_railway_cli
            ;;
        --project)
            create_railway_project
            ;;
        --postgres)
            add_postgresql
            ;;
        --redis)
            add_redis
            ;;
        --env)
            setup_environment_variables
            ;;
        --deploy)
            deploy_application
            ;;
        --schema)
            setup_database_schema
            ;;
        --status)
            railway status
            ;;
        --help|-h)
            echo "Uso: $0 [opção]"
            echo ""
            echo "Opções:"
            echo "  --full, --complete  Setup completo"
            echo "  --check             Verificar Railway CLI"
            echo "  --project           Criar projeto Railway"
            echo "  --postgres          Adicionar PostgreSQL"
            echo "  --redis             Adicionar Redis"
            echo "  --env               Configurar variáveis"
            echo "  --deploy            Fazer deploy"
            echo "  --schema            Configurar schema"
            echo "  --status            Verificar status"
            echo "  --help, -h          Mostrar esta ajuda"
            ;;
        *)
            # Menu interativo
            while true; do
                show_menu
                case $choice in
                    1)
                        check_railway_cli
                        railway_login
                        create_railway_project
                        add_postgresql
                        add_redis
                        setup_environment_variables
                        deploy_application
                        wait_and_check_health
                        setup_database_schema
                        show_final_info
                        ;;
                    2) check_railway_cli ;;
                    3) create_railway_project ;;
                    4) add_postgresql ;;
                    5) add_redis ;;
                    6) setup_environment_variables ;;
                    7) deploy_application ;;
                    8) setup_database_schema ;;
                    9) railway status ;;
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

