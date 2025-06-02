# Documentação Técnica - Fature Database

## Visão Geral da Arquitetura

O sistema Fature Database foi projetado como uma solução completa de banco de dados para programas de afiliados, integrando PostgreSQL para persistência de dados e Redis para cache de alta performance. A arquitetura segue princípios de escalabilidade, performance e manutenibilidade.

## Componentes Principais

### 1. PostgreSQL Database

O PostgreSQL serve como o banco de dados principal, escolhido por suas características avançadas:

- **Particionamento automático** para tabelas de alto volume
- **JSONB** para dados semi-estruturados
- **Extensões especializadas** (uuid-ossp, pgcrypto, pg_cron)
- **Views materializadas** para consultas complexas
- **Triggers e stored procedures** para lógica de negócio

### 2. Redis Cache Layer

O Redis atua como camada de cache distribuído com múltiplos databases especializados:

- **Database 0**: Cache geral do sistema
- **Database 1**: Sessões de usuário
- **Database 2**: Estatísticas de afiliados
- **Database 3**: Rankings e gamificação
- **Database 4**: Cache de comissões
- **Database 5**: Cache de relatórios

### 3. Aplicação Flask

Uma API REST demonstrativa que ilustra as melhores práticas de uso do sistema:

- **Endpoints RESTful** para todas as operações
- **Cache-first strategy** para performance
- **Health checks** para monitoramento
- **Error handling** robusto

## Modelo de Dados

### Entidades Principais

#### Users
Tabela central de usuários do sistema com suporte a migração de dados históricos.

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    status user_status NOT NULL DEFAULT 'pending',
    original_id VARCHAR(255), -- Para migração
    migrated_from VARCHAR(50), -- Sistema de origem
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
```

#### Affiliates
Sistema MLM com hierarquia ilimitada usando closure table pattern.

```sql
CREATE TABLE affiliates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    parent_id UUID REFERENCES affiliates(id),
    referral_code VARCHAR(20) UNIQUE NOT NULL,
    category affiliate_category NOT NULL DEFAULT 'standard',
    level INTEGER NOT NULL DEFAULT 0,
    lifetime_volume DECIMAL(15,2) NOT NULL DEFAULT 0,
    lifetime_commissions DECIMAL(15,2) NOT NULL DEFAULT 0
);
```

#### Transactions (Particionada)
Todas as transações do sistema particionadas por mês para otimização.

```sql
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    affiliate_id UUID NOT NULL REFERENCES affiliates(id),
    type transaction_type NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    status transaction_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (created_at);
```

### Relacionamentos

O sistema implementa um modelo de relacionamentos complexo:

1. **Users ↔ Affiliates**: Relacionamento 1:1
2. **Affiliates ↔ Affiliate_Hierarchy**: Closure table para hierarquia MLM
3. **Affiliates ↔ Transactions**: Relacionamento 1:N
4. **Transactions ↔ Commissions**: Relacionamento 1:N

## Estratégias de Performance

### Particionamento

Tabelas de alto volume são particionadas automaticamente:

```sql
-- Criação automática de partições mensais
CREATE TABLE transactions_2025_06 PARTITION OF transactions
    FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');
```

### Indexação Estratégica

Índices otimizados para consultas frequentes:

```sql
-- Índice composto para performance de afiliados
CREATE INDEX CONCURRENTLY idx_affiliates_performance 
ON affiliates (status, category, level) 
WHERE status = 'active';

-- Índice para hierarquia MLM
CREATE INDEX CONCURRENTLY idx_affiliate_hierarchy_levels 
ON affiliate_hierarchy (ancestor_id, level_difference, descendant_id);
```

### Views Materializadas

Consultas complexas pré-calculadas com refresh automático:

```sql
-- Estatísticas de afiliados
CREATE MATERIALIZED VIEW affiliate_stats AS
SELECT 
    a.id,
    COUNT(DISTINCT t.customer_id) as unique_customers,
    SUM(t.amount) as total_volume,
    SUM(c.final_amount) as total_commissions
FROM affiliates a
LEFT JOIN transactions t ON a.id = t.affiliate_id
LEFT JOIN commissions c ON a.id = c.affiliate_id
GROUP BY a.id;

-- Refresh automático via pg_cron
SELECT cron.schedule('refresh-affiliate-stats', '0 * * * *', 
    'REFRESH MATERIALIZED VIEW CONCURRENTLY affiliate_stats;');
```

## Sistema de Cache

### Arquitetura de Cache

O sistema implementa uma estratégia de cache em múltiplas camadas:

1. **Application-level cache**: Cache de objetos Python
2. **Redis cache**: Cache distribuído com TTL otimizado
3. **Database cache**: Views materializadas

### Padrões de Cache

#### Cache-Aside Pattern
```python
def get_affiliate_stats(affiliate_id):
    # 1. Tentar buscar do cache
    stats = cache.get(f"affiliate:stats:{affiliate_id}")
    
    if not stats:
        # 2. Buscar do banco de dados
        stats = database.query_affiliate_stats(affiliate_id)
        
        # 3. Armazenar no cache
        cache.set(f"affiliate:stats:{affiliate_id}", stats, ttl=1800)
    
    return stats
```

#### Write-Through Pattern
```python
def update_affiliate_stats(affiliate_id, stats):
    # 1. Atualizar banco de dados
    database.update_affiliate_stats(affiliate_id, stats)
    
    # 2. Atualizar cache
    cache.set(f"affiliate:stats:{affiliate_id}", stats, ttl=1800)
```

### TTL Strategies

Diferentes tipos de dados têm TTLs otimizados:

- **Sessões de usuário**: 24 horas
- **Estatísticas de afiliados**: 30 minutos
- **Rankings**: 15 minutos
- **Relatórios**: 1 hora
- **Dados de configuração**: 24 horas

## Migração de Dados

### Processo de Migração

O sistema suporta migração de dados históricos através de um processo estruturado:

1. **Carregamento em tabelas temporárias**
2. **Validação e limpeza de dados**
3. **Mapeamento para estrutura target**
4. **Migração em lotes para performance**
5. **Validação pós-migração**

### Mapeamento de Dados

#### Usuários (upbet_plataforma_public_users.xlsx → users)
```sql
INSERT INTO users (id, email, name, status, original_id, migrated_from)
SELECT 
    id::UUID,
    email,
    username,
    'active'::user_status,
    id,
    'upbet_platform'
FROM temp_users;
```

#### Transações (deposits.xlsx + casino_bets.xlsx → transactions)
```sql
-- Depósitos
INSERT INTO transactions (id, affiliate_id, type, amount, status, original_id, source_table)
SELECT 
    d.id::UUID,
    a.id,
    'deposit'::transaction_type,
    d.amount,
    CASE d.status WHEN 'completed' THEN 'processed' ELSE 'pending' END,
    d.id,
    'deposits'
FROM temp_deposits d
JOIN affiliates a ON a.user_id = (SELECT u.id FROM users u WHERE u.original_id = d.user_id);
```

### Validação de Integridade

Funções automáticas de validação garantem a integridade dos dados migrados:

```sql
CREATE OR REPLACE FUNCTION validate_migration()
RETURNS TABLE (validation_item TEXT, expected_count BIGINT, actual_count BIGINT, status TEXT)
AS $$
BEGIN
    -- Validar usuários migrados
    RETURN QUERY 
    SELECT 
        'users_migrated'::TEXT,
        (SELECT COUNT(*) FROM temp_users)::BIGINT,
        (SELECT COUNT(*) FROM users WHERE migrated_from = 'upbet_platform')::BIGINT,
        CASE 
            WHEN (SELECT COUNT(*) FROM temp_users) = 
                 (SELECT COUNT(*) FROM users WHERE migrated_from = 'upbet_platform')
            THEN 'OK' ELSE 'ERROR' 
        END;
END;
$$ LANGUAGE plpgsql;
```

## Segurança

### Controle de Acesso

O sistema implementa múltiplas camadas de segurança:

1. **Database-level**: Usuários com permissões limitadas
2. **Application-level**: Autenticação e autorização
3. **Network-level**: Firewall e VPN

### Auditoria

Todas as operações são auditadas automaticamente:

```sql
CREATE TABLE data_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name VARCHAR(100) NOT NULL,
    record_id UUID NOT NULL,
    operation VARCHAR(10) NOT NULL,
    old_values JSONB,
    new_values JSONB,
    changed_by UUID REFERENCES users(id),
    changed_at TIMESTAMP NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (changed_at);
```

### Criptografia

Dados sensíveis são criptografados usando:

- **AES-256-GCM** para dados em repouso
- **TLS 1.3** para dados em trânsito
- **bcrypt** para senhas de usuário

## Monitoramento e Observabilidade

### Métricas de Performance

O sistema expõe métricas detalhadas:

```sql
-- View de performance do sistema
CREATE VIEW system_performance AS
SELECT 
    'database_size' as metric,
    pg_size_pretty(pg_database_size(current_database())) as value
UNION ALL
SELECT 
    'active_connections' as metric,
    COUNT(*)::TEXT as value
FROM pg_stat_activity
WHERE state = 'active';
```

### Health Checks

Endpoints de saúde verificam todos os componentes:

```python
@app.route('/health')
def health_check():
    return {
        'postgresql': check_postgresql_health(),
        'redis': check_redis_health(),
        'cache_hit_rate': get_cache_hit_rate(),
        'active_connections': get_active_connections()
    }
```

### Alertas

Sistema de alertas baseado em métricas:

- **CPU > 80%**: Alerta de performance
- **Memória > 90%**: Alerta de memória
- **Cache hit rate < 70%**: Alerta de cache
- **Conexões > 80% do limite**: Alerta de conexões

## Backup e Disaster Recovery

### Estratégia de Backup

1. **Backup completo**: Diário às 2:00 AM
2. **Backup incremental**: A cada 6 horas
3. **WAL shipping**: Contínuo para standby
4. **Backup de configuração**: Semanal

### Procedimentos de Recovery

```bash
# Restore completo
pg_restore -U fature_user -d fature_db backup_20250602.dump

# Point-in-time recovery
pg_ctl stop -D /var/lib/postgresql/data
cp -R /backup/base /var/lib/postgresql/data
pg_ctl start -D /var/lib/postgresql/data
```

## Escalabilidade

### Horizontal Scaling

O sistema suporta escalabilidade horizontal através de:

1. **Read replicas** para distribuir carga de leitura
2. **Sharding** por affiliate_id para grandes volumes
3. **Connection pooling** para otimizar conexões
4. **Load balancing** para distribuir requisições

### Vertical Scaling

Otimizações para escalabilidade vertical:

1. **Particionamento** de tabelas grandes
2. **Índices especializados** para consultas frequentes
3. **Views materializadas** para relatórios complexos
4. **Cache distribuído** para reduzir carga no banco

## Manutenção

### Rotinas Automáticas

```sql
-- Limpeza de partições antigas
SELECT cron.schedule('cleanup-old-partitions', '0 2 * * 0', 
    'SELECT drop_old_partitions(''transactions'', ''3 months'');');

-- Atualização de estatísticas
SELECT cron.schedule('update-stats', '0 3 * * *', 
    'ANALYZE;');

-- Vacuum automático
SELECT cron.schedule('vacuum-tables', '0 4 * * *', 
    'VACUUM ANALYZE;');
```

### Monitoramento de Performance

```sql
-- Queries lentas
SELECT query, mean_time, calls, total_time
FROM pg_stat_statements
WHERE mean_time > 1000
ORDER BY mean_time DESC;

-- Índices não utilizados
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0;
```

## Conclusão

O sistema Fature Database representa uma solução robusta e escalável para programas de afiliados, combinando as melhores práticas de arquitetura de dados com tecnologias modernas. A implementação cuidadosa de cache, particionamento e otimizações garante performance superior mesmo com grandes volumes de dados.

A arquitetura modular permite fácil manutenção e evolução do sistema, enquanto as estratégias de backup e monitoramento garantem alta disponibilidade e confiabilidade operacional.

