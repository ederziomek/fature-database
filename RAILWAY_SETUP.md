# RAILWAY DEPLOYMENT GUIDE - FATURE DATABASE

## 🚀 Deploy no Railway

### 1. CONFIGURAÇÃO INICIAL

1. **Acesse o Railway**: https://railway.app
2. **Conecte com GitHub**: Use sua conta GitHub
3. **Importe o repositório**: `ederziomek/fature-database`

### 2. VARIÁVEIS DE AMBIENTE OBRIGATÓRIAS

Configure as seguintes variáveis no Railway:

#### Aplicação Principal
```bash
# Flask Configuration
FLASK_ENV=production
FLASK_DEBUG=0
SECRET_KEY=sua_chave_secreta_muito_segura_aqui

# Database URLs (serão fornecidas pelo Railway)
DATABASE_URL=${{Postgres.DATABASE_URL}}
REDIS_URL=${{Redis.REDIS_URL}}

# Cache Configuration
CACHE_TTL_SHORT=300
CACHE_TTL_MEDIUM=1800
CACHE_TTL_LONG=3600
CACHE_TTL_VERY_LONG=86400

# Security
JWT_SECRET_KEY=sua_jwt_secret_key_aqui
ENCRYPTION_KEY=sua_chave_de_criptografia_aqui

# Logging
LOG_LEVEL=INFO
METRICS_ENABLED=true
```

### 3. SERVIÇOS NECESSÁRIOS

#### PostgreSQL Database
1. **Adicione PostgreSQL** ao projeto Railway
2. **Nome sugerido**: `fature-postgres`
3. **Versão**: PostgreSQL 15+

#### Redis Cache
1. **Adicione Redis** ao projeto Railway  
2. **Nome sugerido**: `fature-redis`
3. **Versão**: Redis 7+

### 4. CONFIGURAÇÃO DE DEPLOY

#### Build Settings
- **Build Command**: Automático (usa Dockerfile)
- **Start Command**: Automático (definido no Dockerfile)
- **Root Directory**: `/` (raiz do projeto)

#### Environment Variables
```bash
# Essenciais para Railway
PORT=${{RAILWAY_PORT}}  # Automático
RAILWAY_ENVIRONMENT=production

# Database (automático quando conectar serviços)
DATABASE_URL=${{Postgres.DATABASE_URL}}
REDIS_URL=${{Redis.REDIS_URL}}

# Aplicação
FLASK_ENV=production
SECRET_KEY=gere_uma_chave_segura_aqui
```

### 5. PASSOS DE DEPLOYMENT

#### Passo 1: Criar Projeto
```bash
# No Railway Dashboard:
1. New Project
2. Deploy from GitHub repo
3. Selecionar: ederziomek/fature-database
```

#### Passo 2: Adicionar Serviços
```bash
# Adicionar PostgreSQL:
1. Add Service → Database → PostgreSQL
2. Aguardar provisioning

# Adicionar Redis:  
1. Add Service → Database → Redis
2. Aguardar provisioning
```

#### Passo 3: Conectar Serviços
```bash
# Conectar ao app principal:
1. Ir em Settings do app
2. Variables → Connect → PostgreSQL
3. Variables → Connect → Redis
```

#### Passo 4: Configurar Variáveis
```bash
# Adicionar variáveis essenciais:
FLASK_ENV=production
SECRET_KEY=sua_chave_aqui
LOG_LEVEL=INFO
```

#### Passo 5: Deploy
```bash
# Deploy automático após configuração
# Verificar logs em tempo real
# Testar endpoints após deploy
```

### 6. INICIALIZAÇÃO DO BANCO

Após o deploy, execute os scripts SQL:

#### Via Railway CLI
```bash
# Instalar Railway CLI
npm install -g @railway/cli

# Login
railway login

# Conectar ao projeto
railway link

# Executar scripts SQL
railway run psql $DATABASE_URL -f sql/01_schema.sql
railway run psql $DATABASE_URL -f sql/02_indexes.sql  
railway run psql $DATABASE_URL -f sql/03_views.sql
```

#### Via Interface Web
```bash
# Acessar PostgreSQL no Railway Dashboard
# Usar Query Editor para executar scripts
# Ordem: schema → indexes → views
```

### 7. VERIFICAÇÃO PÓS-DEPLOY

#### Health Check
```bash
# Verificar se a aplicação está rodando
curl https://seu-app.railway.app/health

# Resposta esperada:
{
  "status": "healthy",
  "timestamp": "2025-06-02T...",
  "services": {
    "postgresql": true,
    "redis": true
  }
}
```

#### Endpoints Principais
```bash
# Dashboard
GET https://seu-app.railway.app/api/dashboard

# Afiliados
GET https://seu-app.railway.app/api/affiliates

# Cache Stats
GET https://seu-app.railway.app/api/cache/stats
```

### 8. MONITORAMENTO

#### Logs
```bash
# Ver logs em tempo real
railway logs --follow

# Filtrar por serviço
railway logs --service fature-database
```

#### Métricas
```bash
# CPU e Memória no Dashboard Railway
# Tempo de resposta das APIs
# Status dos serviços conectados
```

### 9. BACKUP E MANUTENÇÃO

#### Backup Automático
```bash
# PostgreSQL backup (configurar no Railway)
# Frequência: Diária
# Retenção: 7 dias
```

#### Manutenção
```bash
# Refresh views materializadas
railway run psql $DATABASE_URL -c "REFRESH MATERIALIZED VIEW CONCURRENTLY affiliate_stats;"

# Limpeza de cache
curl -X POST https://seu-app.railway.app/api/cache/clear \
  -H "Content-Type: application/json" \
  -d '{"type": "all"}'
```

### 10. TROUBLESHOOTING

#### Problemas Comuns

**Build Failed:**
- Verificar Dockerfile
- Verificar requirements.txt
- Verificar logs de build

**Connection Failed:**
- Verificar DATABASE_URL
- Verificar REDIS_URL  
- Verificar variáveis de ambiente

**Performance Issues:**
- Verificar logs de aplicação
- Verificar métricas de CPU/RAM
- Otimizar queries se necessário

#### Logs Importantes
```bash
# Erro de conexão com banco
"psycopg2.OperationalError: could not connect"

# Erro de Redis
"redis.exceptions.ConnectionError"

# Erro de porta
"Address already in use"
```

### 11. CUSTOS ESTIMADOS

#### Railway Pricing (Estimativa)
- **Hobby Plan**: $5/mês (adequado para desenvolvimento)
- **Pro Plan**: $20/mês (recomendado para produção)
- **PostgreSQL**: ~$5/mês
- **Redis**: ~$3/mês

**Total estimado**: $13-28/mês dependendo do plano

### 12. PRÓXIMOS PASSOS

Após deploy bem-sucedido:

1. **Configurar domínio customizado** (opcional)
2. **Implementar SSL/TLS** (automático no Railway)
3. **Configurar alertas** de monitoramento
4. **Executar migração** de dados históricos
5. **Conectar com sistema** Fature principal

---

**🎉 Seu banco de dados Fature estará rodando em produção!**

*URL do repositório: https://github.com/ederziomek/fature-database*

