#!/bin/bash

# =====================================================
# FATURE DATABASE - SCRIPT DE TESTE AUTOMATIZADO
# Validação completa do deploy no Railway
# =====================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Contadores
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Função para executar teste
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    ((TOTAL_TESTS++))
    log_info "Executando: $test_name"
    
    if eval "$test_command" > /dev/null 2>&1; then
        log_success "$test_name - PASSOU"
        return 0
    else
        log_error "$test_name - FALHOU"
        return 1
    fi
}

# Obter URL da aplicação
get_app_url() {
    if command -v railway &> /dev/null; then
        APP_URL=$(railway domain 2>/dev/null || echo "")
        if [ -z "$APP_URL" ]; then
            log_warning "URL da aplicação não encontrada via Railway CLI"
            read -p "Digite a URL da aplicação (ex: https://seu-app.railway.app): " APP_URL
        fi
    else
        log_warning "Railway CLI não encontrado"
        read -p "Digite a URL da aplicação (ex: https://seu-app.railway.app): " APP_URL
    fi
    
    # Remover trailing slash
    APP_URL=${APP_URL%/}
    
    if [ -z "$APP_URL" ]; then
        log_error "URL da aplicação é obrigatória"
        exit 1
    fi
    
    log_info "Testando aplicação em: $APP_URL"
}

# Teste 1: Health Check
test_health_check() {
    log_info "=== TESTE 1: Health Check ==="
    
    run_test "Health Check Response" \
        "curl -f -s '$APP_URL/health'" \
        "200"
    
    # Verificar conteúdo da resposta
    local response=$(curl -s "$APP_URL/health" 2>/dev/null || echo "{}")
    local status=$(echo "$response" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
    
    if [ "$status" = "healthy" ]; then
        log_success "Health Check Status - PASSOU"
        ((TESTS_PASSED++))
    else
        log_error "Health Check Status - FALHOU (status: $status)"
        ((TESTS_FAILED++))
    fi
    
    ((TOTAL_TESTS++))
}

# Teste 2: Database Connectivity
test_database() {
    log_info "=== TESTE 2: Database Connectivity ==="
    
    if command -v railway &> /dev/null; then
        run_test "PostgreSQL Connection" \
            "railway run psql \$DATABASE_URL -c 'SELECT 1;'" \
            "success"
        
        run_test "Tables Exist" \
            "railway run psql \$DATABASE_URL -c '\dt' | grep -q users" \
            "success"
    else
        log_warning "Railway CLI não disponível - pulando testes de banco"
        ((TOTAL_TESTS += 2))
    fi
}

# Teste 3: Redis Connectivity
test_redis() {
    log_info "=== TESTE 3: Redis Connectivity ==="
    
    if command -v railway &> /dev/null; then
        run_test "Redis Connection" \
            "railway run redis-cli -u \$REDIS_URL ping | grep -q PONG" \
            "success"
        
        run_test "Redis Set/Get" \
            "railway run redis-cli -u \$REDIS_URL set test_key test_value && railway run redis-cli -u \$REDIS_URL get test_key | grep -q test_value" \
            "success"
    else
        log_warning "Railway CLI não disponível - pulando testes de Redis"
        ((TOTAL_TESTS += 2))
    fi
}

# Teste 4: API Endpoints
test_api_endpoints() {
    log_info "=== TESTE 4: API Endpoints ==="
    
    run_test "Dashboard Endpoint" \
        "curl -f -s '$APP_URL/api/dashboard'" \
        "200"
    
    run_test "Affiliates Endpoint" \
        "curl -f -s '$APP_URL/api/affiliates'" \
        "200"
    
    run_test "Cache Stats Endpoint" \
        "curl -f -s '$APP_URL/api/cache/stats'" \
        "200"
}

# Teste 5: Performance
test_performance() {
    log_info "=== TESTE 5: Performance ==="
    
    # Testar tempo de resposta do health check
    local start_time=$(date +%s%N)
    if curl -f -s "$APP_URL/health" > /dev/null 2>&1; then
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 )) # em ms
        
        if [ $duration -lt 2000 ]; then
            log_success "Response Time - PASSOU ($duration ms)"
            ((TESTS_PASSED++))
        else
            log_error "Response Time - FALHOU ($duration ms > 2000ms)"
            ((TESTS_FAILED++))
        fi
    else
        log_error "Response Time - FALHOU (sem resposta)"
        ((TESTS_FAILED++))
    fi
    
    ((TOTAL_TESTS++))
}

# Teste 6: Security Headers
test_security() {
    log_info "=== TESTE 6: Security Headers ==="
    
    local headers=$(curl -I -s "$APP_URL/health" 2>/dev/null || echo "")
    
    if echo "$headers" | grep -q "Content-Type: application/json"; then
        log_success "Content-Type Header - PASSOU"
        ((TESTS_PASSED++))
    else
        log_error "Content-Type Header - FALHOU"
        ((TESTS_FAILED++))
    fi
    
    ((TOTAL_TESTS++))
}

# Teste 7: Data Validation
test_data_validation() {
    log_info "=== TESTE 7: Data Validation ==="
    
    # Testar se endpoints retornam JSON válido
    local dashboard_response=$(curl -s "$APP_URL/api/dashboard" 2>/dev/null || echo "{}")
    
    if echo "$dashboard_response" | jq . > /dev/null 2>&1; then
        log_success "JSON Response Validation - PASSOU"
        ((TESTS_PASSED++))
    else
        log_error "JSON Response Validation - FALHOU"
        ((TESTS_FAILED++))
    fi
    
    ((TOTAL_TESTS++))
}

# Mostrar relatório final
show_report() {
    echo ""
    echo "======================================================="
    echo "           RELATÓRIO DE TESTES"
    echo "======================================================="
    echo ""
    echo "📊 Estatísticas:"
    echo "   Total de testes: $TOTAL_TESTS"
    echo "   Testes passaram: $TESTS_PASSED"
    echo "   Testes falharam: $TESTS_FAILED"
    
    local success_rate=0
    if [ $TOTAL_TESTS -gt 0 ]; then
        success_rate=$(( (TESTS_PASSED * 100) / TOTAL_TESTS ))
    fi
    
    echo "   Taxa de sucesso: $success_rate%"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo "🎉 TODOS OS TESTES PASSARAM!"
        echo "✅ Aplicação está funcionando corretamente"
        echo ""
        echo "🌐 URL da aplicação: $APP_URL"
        echo "🔗 Endpoints disponíveis:"
        echo "   - Health: $APP_URL/health"
        echo "   - Dashboard: $APP_URL/api/dashboard"
        echo "   - Afiliados: $APP_URL/api/affiliates"
        echo "   - Cache Stats: $APP_URL/api/cache/stats"
    else
        echo "⚠️  ALGUNS TESTES FALHARAM"
        echo "❌ Verifique os logs acima para detalhes"
        echo ""
        echo "🔧 Comandos úteis para debug:"
        echo "   railway logs --follow"
        echo "   railway status"
        echo "   railway variables"
    fi
    
    echo ""
    echo "📚 Documentação:"
    echo "   - README.md"
    echo "   - RAILWAY_SETUP.md"
    echo "   - TESTE_VALIDACAO.md"
    echo ""
}

# Menu principal
show_menu() {
    echo ""
    echo "======================================================="
    echo "        FATURE DATABASE - TESTE AUTOMATIZADO"
    echo "======================================================="
    echo ""
    echo "Escolha uma opção:"
    echo "1) Executar todos os testes"
    echo "2) Teste de Health Check"
    echo "3) Teste de Database"
    echo "4) Teste de Redis"
    echo "5) Teste de API Endpoints"
    echo "6) Teste de Performance"
    echo "7) Teste de Security"
    echo "8) Teste de Data Validation"
    echo "9) Configurar URL da aplicação"
    echo "0) Sair"
    echo ""
    read -p "Digite sua opção: " choice
}

# Função principal
main() {
    case $1 in
        --all|--complete)
            get_app_url
            test_health_check
            test_database
            test_redis
            test_api_endpoints
            test_performance
            test_security
            test_data_validation
            show_report
            ;;
        --health)
            get_app_url
            test_health_check
            show_report
            ;;
        --database)
            test_database
            show_report
            ;;
        --redis)
            test_redis
            show_report
            ;;
        --api)
            get_app_url
            test_api_endpoints
            show_report
            ;;
        --performance)
            get_app_url
            test_performance
            show_report
            ;;
        --security)
            get_app_url
            test_security
            show_report
            ;;
        --data)
            get_app_url
            test_data_validation
            show_report
            ;;
        --help|-h)
            echo "Uso: $0 [opção]"
            echo ""
            echo "Opções:"
            echo "  --all, --complete   Executar todos os testes"
            echo "  --health            Teste de health check"
            echo "  --database          Teste de database"
            echo "  --redis             Teste de Redis"
            echo "  --api               Teste de API endpoints"
            echo "  --performance       Teste de performance"
            echo "  --security          Teste de security"
            echo "  --data              Teste de data validation"
            echo "  --help, -h          Mostrar esta ajuda"
            ;;
        *)
            # Menu interativo
            while true; do
                show_menu
                case $choice in
                    1)
                        get_app_url
                        test_health_check
                        test_database
                        test_redis
                        test_api_endpoints
                        test_performance
                        test_security
                        test_data_validation
                        show_report
                        ;;
                    2) get_app_url; test_health_check; show_report ;;
                    3) test_database; show_report ;;
                    4) test_redis; show_report ;;
                    5) get_app_url; test_api_endpoints; show_report ;;
                    6) get_app_url; test_performance; show_report ;;
                    7) get_app_url; test_security; show_report ;;
                    8) get_app_url; test_data_validation; show_report ;;
                    9) get_app_url ;;
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

