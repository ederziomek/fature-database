# GUIA DE TESTE E VALIDAÇÃO - RAILWAY DEPLOYMENT

## 🧪 Checklist de Validação Pós-Deploy

### 1. VERIFICAÇÃO BÁSICA DE DEPLOY

#### Status do Projeto
```bash
# Verificar se o projeto está ativo
railway status

# Verificar logs em tempo real
railway logs --follow

# Verificar variáveis de ambiente
railway variables
```

#### Resposta Esperada
```
✅ Project: fature-database
✅ Environment: production
✅ Status: deployed
✅ Services: 3 (app, postgres, redis)
```

### 2. TESTE DE CONECTIVIDADE

#### Health Check Principal
```bash
# Obter URL da aplicação
APP_URL=$(railway domain)

# Testar health check
curl -s "$APP_URL/health" | jq .
```

#### Resposta Esperada
```json
{
  "status": "healthy",
  "timestamp": "2025-06-02T...",
  "services": {
    "postgresql": true,
    "redis": true
  }
}
```

### 3. TESTE DE BANCO DE DADOS

#### Conexão PostgreSQL
```bash
# Testar conexão direta
railway run psql $DATABASE_URL -c "SELECT version();"

# Verificar tabelas criadas
railway run psql $DATABASE_URL -c "\dt"

# Testar query simples
railway run psql $DATABASE_URL -c "SELECT COUNT(*) FROM users;"
```

#### Resposta Esperada
```
PostgreSQL 15.x on x86_64-pc-linux-gnu
List of relations:
 Schema |        Name         | Type  |  Owner
--------+---------------------+-------+---------
 public | users               | table | postgres
 public | affiliates          | table | postgres
 public | transactions        | table | postgres
 ...
```

### 4. TESTE DE CACHE REDIS

#### Conexão Redis
```bash
# Testar conexão Redis
railway run redis-cli -u $REDIS_URL ping

# Testar set/get básico
railway run redis-cli -u $REDIS_URL set test_key "test_value"
railway run redis-cli -u $REDIS_URL get test_key

# Verificar databases configurados
railway run redis-cli -u $REDIS_URL info keyspace
```

#### Resposta Esperada
```
PONG
OK
test_value
# Keyspace
db0:keys=1,expires=0,avg_ttl=0
```

### 5. TESTE DE ENDPOINTS DA API

#### Dashboard Endpoint
```bash
curl -s "$APP_URL/api/dashboard" | jq .
```

#### Afiliados Endpoint
```bash
curl -s "$APP_URL/api/affiliates?limit=5" | jq .
```

#### Cache Stats Endpoint
```bash
curl -s "$APP_URL/api/cache/stats" | jq .
```

#### Resposta Esperada
```json
{
  "data": {
    "current_month": {},
    "previous_month": {},
    "generated_at": "2025-06-02T..."
  },
  "cached": false
}
```

### 6. TESTE DE PERFORMANCE

#### Tempo de Resposta
```bash
# Testar tempo de resposta do health check
time curl -s "$APP_URL/health" > /dev/null

# Testar múltiplas requisições
for i in {1..10}; do
  time curl -s "$APP_URL/health" > /dev/null
done
```

#### Métricas Esperadas
- Health check: < 500ms
- API endpoints: < 1s
- Cache hits: < 100ms

### 7. TESTE DE LOGS E MONITORAMENTO

#### Verificar Logs
```bash
# Logs da aplicação
railway logs --service fature-database

# Logs do PostgreSQL
railway logs --service postgres

# Logs do Redis
railway logs --service redis
```

#### Logs Esperados
```
[INFO] Starting Fature Database API
[INFO] Connected to PostgreSQL
[INFO] Connected to Redis
[INFO] Health check endpoint ready
```

### 8. TESTE DE VARIÁVEIS DE AMBIENTE

#### Verificar Configuração
```bash
# Verificar variáveis essenciais
railway variables | grep -E "(FLASK_ENV|DATABASE_URL|REDIS_URL|SECRET_KEY)"

# Testar se aplicação lê variáveis
curl -s "$APP_URL/health" | jq '.config // empty'
```

#### Configuração Esperada
```
FLASK_ENV=production
DATABASE_URL=postgresql://...
REDIS_URL=redis://...
SECRET_KEY=***
```

### 9. TESTE DE SEGURANÇA

#### Headers de Segurança
```bash
# Verificar headers HTTP
curl -I "$APP_URL/health"

# Verificar se não expõe informações sensíveis
curl -s "$APP_URL/api/cache/stats" | grep -i "password\|secret\|key" || echo "OK - Sem vazamentos"
```

#### Headers Esperados
```
HTTP/1.1 200 OK
Content-Type: application/json
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
```

### 10. TESTE DE MIGRAÇÃO DE DADOS

#### Preparar Dados de Teste
```bash
# Criar dados de teste
railway run psql $DATABASE_URL -c "
INSERT INTO users (email, name, status) 
VALUES ('test@fature.com', 'Test User', 'active');
"

# Verificar inserção
railway run psql $DATABASE_URL -c "SELECT * FROM users WHERE email = 'test@fature.com';"
```

#### Testar API com Dados
```bash
# Verificar se API retorna dados
curl -s "$APP_URL/api/affiliates" | jq '.data | length'
```

## 🚨 TROUBLESHOOTING

### Problemas Comuns e Soluções

#### 1. Deploy Failed
```bash
# Verificar logs de build
railway logs --deployment

# Verificar Dockerfile
cat Dockerfile

# Verificar requirements.txt
cat requirements.txt
```

**Soluções:**
- Verificar sintaxe do Dockerfile
- Verificar dependências no requirements.txt
- Verificar se todas as variáveis estão configuradas

#### 2. Database Connection Error
```bash
# Verificar se PostgreSQL está rodando
railway status

# Verificar DATABASE_URL
railway variables | grep DATABASE_URL

# Testar conexão manual
railway run psql $DATABASE_URL -c "SELECT 1;"
```

**Soluções:**
- Verificar se PostgreSQL foi adicionado ao projeto
- Verificar se DATABASE_URL está configurada
- Verificar se schema foi criado

#### 3. Redis Connection Error
```bash
# Verificar se Redis está rodando
railway status

# Verificar REDIS_URL
railway variables | grep REDIS_URL

# Testar conexão manual
railway run redis-cli -u $REDIS_URL ping
```

**Soluções:**
- Verificar se Redis foi adicionado ao projeto
- Verificar se REDIS_URL está configurada
- Verificar configuração de cache na aplicação

#### 4. Application Not Responding
```bash
# Verificar se aplicação está rodando
railway logs --follow

# Verificar porta
railway variables | grep PORT

# Verificar health check
curl -v "$APP_URL/health"
```

**Soluções:**
- Verificar se aplicação está escutando na porta correta
- Verificar se gunicorn está configurado corretamente
- Verificar logs de erro da aplicação

#### 5. Environment Variables Missing
```bash
# Listar todas as variáveis
railway variables

# Verificar variáveis específicas
railway variables | grep -E "(SECRET_KEY|JWT_SECRET)"
```

**Soluções:**
- Configurar variáveis faltantes
- Verificar sintaxe das variáveis
- Redeploy após configurar variáveis

## ✅ CHECKLIST FINAL DE VALIDAÇÃO

### Antes de Considerar Deploy Bem-Sucedido

- [ ] **Health check** retorna status "healthy"
- [ ] **PostgreSQL** conecta e responde queries
- [ ] **Redis** conecta e responde comandos
- [ ] **API endpoints** retornam dados válidos
- [ ] **Logs** não mostram erros críticos
- [ ] **Variáveis de ambiente** estão configuradas
- [ ] **Performance** está dentro do esperado
- [ ] **Segurança** não vaza informações sensíveis
- [ ] **Monitoramento** está funcionando
- [ ] **Backup** está configurado (se aplicável)

### Métricas de Sucesso

| Métrica | Valor Esperado | Status |
|---------|----------------|--------|
| Health Check Response Time | < 500ms | ⏳ |
| API Response Time | < 1s | ⏳ |
| Database Connection Time | < 2s | ⏳ |
| Redis Connection Time | < 100ms | ⏳ |
| Memory Usage | < 512MB | ⏳ |
| CPU Usage | < 50% | ⏳ |

### Comandos de Validação Rápida

```bash
#!/bin/bash
# Script de validação rápida

APP_URL=$(railway domain)

echo "🧪 Iniciando validação do deploy..."

# 1. Health Check
echo "1. Testando health check..."
if curl -f -s "$APP_URL/health" > /dev/null; then
    echo "✅ Health check OK"
else
    echo "❌ Health check FAILED"
fi

# 2. Database
echo "2. Testando PostgreSQL..."
if railway run psql $DATABASE_URL -c "SELECT 1;" > /dev/null 2>&1; then
    echo "✅ PostgreSQL OK"
else
    echo "❌ PostgreSQL FAILED"
fi

# 3. Redis
echo "3. Testando Redis..."
if railway run redis-cli -u $REDIS_URL ping > /dev/null 2>&1; then
    echo "✅ Redis OK"
else
    echo "❌ Redis FAILED"
fi

# 4. API Endpoints
echo "4. Testando API endpoints..."
if curl -f -s "$APP_URL/api/dashboard" > /dev/null; then
    echo "✅ API endpoints OK"
else
    echo "❌ API endpoints FAILED"
fi

echo "🎉 Validação concluída!"
echo "📊 URL da aplicação: $APP_URL"
```

## 📞 SUPORTE

### Em Caso de Problemas

1. **Verificar logs**: `railway logs --follow`
2. **Verificar status**: `railway status`
3. **Verificar variáveis**: `railway variables`
4. **Consultar documentação**: [Railway Docs](https://docs.railway.app)
5. **Abrir issue**: [GitHub Issues](https://github.com/ederziomek/fature-database/issues)

### Contatos

- **Documentação**: README.md do projeto
- **Issues**: GitHub Issues
- **Railway Support**: https://help.railway.app

