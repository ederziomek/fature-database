# Fature Database - Sistema de Banco de Dados para Afiliados

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-blue.svg)
![Redis](https://img.shields.io/badge/Redis-7+-red.svg)
![Python](https://img.shields.io/badge/Python-3.11+-green.svg)
![Docker](https://img.shields.io/badge/Docker-Compose-blue.svg)

Sistema de banco de dados otimizado para o programa de afiliados **Fature**, incluindo migração de dados históricos, cache Redis e estrutura MLM completa.

## 📋 Visão Geral

Este repositório contém a implementação completa do banco de dados para o sistema de afiliados Fature, desenvolvido para suportar:

- **Sistema MLM (Multi-Level Marketing)** com hierarquia ilimitada
- **Migração de dados históricos** de planilhas Excel
- **Cache Redis** para alta performance
- **Relatórios e analytics** em tempo real
- **Gamificação** com sequências diárias e rankings
- **Auditoria completa** de todas as operações

### 🎯 Características Principais

- **PostgreSQL 15+** com particionamento automático
- **Redis 7+** com estratégias de cache otimizadas
- **Views materializadas** para relatórios rápidos
- **Stored procedures** para cálculos complexos
- **Docker Compose** para ambiente completo
- **Scripts de migração** automatizados

## 🏗️ Arquitetura

```
fature-database/
├── sql/                    # Scripts SQL principais
│   ├── 01_schema.sql      # Criação de tabelas e tipos
│   ├── 02_indexes.sql     # Índices para performance
│   └── 03_views.sql       # Views materializadas
├── migrations/            # Scripts de migração
│   └── 01_data_migration.sql
├── scripts/               # Scripts Python e utilitários
│   └── redis_cache.py     # Sistema de cache Redis
├── config/                # Configurações
│   ├── redis.conf         # Configuração Redis
│   └── postgresql.conf    # Configuração PostgreSQL
├── docs/                  # Documentação
└── docker-compose.yml     # Ambiente completo
```

## 🚀 Quick Start

### Pré-requisitos

- Docker e Docker Compose
- Python 3.11+
- PostgreSQL 15+ (se não usar Docker)
- Redis 7+ (se não usar Docker)

### 1. Clone o Repositório

```bash
git clone https://github.com/seu-usuario/fature-database.git
cd fature-database
```

### 2. Inicie o Ambiente

```bash
# Iniciar todos os serviços
docker-compose up -d

# Verificar status
docker-compose ps
```

### 3. Acesse as Interfaces

- **pgAdmin**: http://localhost:8080 (admin@fature.com / admin123)
- **Redis Commander**: http://localhost:8081
- **API Fature**: http://localhost:5000

### 4. Execute a Migração (Opcional)

```bash
# Conectar ao PostgreSQL
docker exec -it fature-postgres psql -U fature_user -d fature_db

# Executar migração de dados
SELECT * FROM run_complete_migration();
```

## 📊 Estrutura do Banco de Dados

### Tabelas Principais

| Tabela | Descrição | Registros Esperados |
|--------|-----------|-------------------|
| `users` | Usuários do sistema | ~500 |
| `affiliates` | Afiliados MLM | ~500 |
| `transactions` | Transações (particionada) | ~500k+ |
| `commissions` | Comissões calculadas | ~100k+ |
| `affiliate_hierarchy` | Hierarquia MLM (closure table) | ~2k+ |

### Particionamento

As tabelas `transactions`, `commissions` e `data_audit` são particionadas por mês para otimizar performance:

```sql
-- Exemplo de partição
CREATE TABLE transactions_2025_06 PARTITION OF transactions
    FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');
```

### Views Materializadas

- `affiliate_stats` - Estatísticas completas de afiliados
- `affiliate_hierarchy_stats` - Hierarquia com métricas
- `monthly_commission_report` - Relatório mensal de comissões
- `performance_dashboard` - Dashboard principal
- `top_performers` - Rankings de performance

## 🔄 Migração de Dados

### Dados Suportados

O sistema suporta migração de:

1. **Usuários** (`upbet_plataforma_public_users.xlsx`)
   - 409 usuários únicos
   - Criação automática de afiliados

2. **Depósitos** (`deposits.xlsx`)
   - 3.059 depósitos
   - Valor médio: R$ 105,57

3. **Apostas** (`casino_bets.xlsx`)
   - 514.686 apostas
   - Alta atividade por usuário

### Processo de Migração

```sql
-- 1. Carregar dados temporários
COPY temp_users FROM '/path/to/users.csv' WITH CSV HEADER;

-- 2. Executar migração completa
SELECT * FROM run_complete_migration();

-- 3. Validar migração
SELECT * FROM validate_migration();
```

## ⚡ Sistema de Cache Redis

### Databases Redis

| DB | Propósito | TTL Padrão |
|----|-----------|------------|
| 0 | Cache geral | 1 hora |
| 1 | Sessões de usuário | 24 horas |
| 2 | Estatísticas de afiliados | 30 minutos |
| 3 | Rankings e gamificação | 15 minutos |
| 4 | Cache de comissões | 1 hora |
| 5 | Cache de relatórios | 30 minutos |

### Uso do Cache

```python
from scripts.redis_cache import CacheManager

# Inicializar cache
cache = CacheManager()

# Buscar estatísticas de afiliado
stats = cache.affiliate_stats.get_affiliate_stats(affiliate_id)
if not stats:
    # Buscar do banco e cachear
    stats = fetch_from_database(affiliate_id)
    cache.affiliate_stats.set_affiliate_stats(affiliate_id, stats)
```

## 📈 Performance

### Otimizações Implementadas

1. **Índices Estratégicos**
   - Índices compostos para consultas frequentes
   - Índices parciais para dados ativos
   - Índices CONCURRENTLY para criação sem bloqueio

2. **Particionamento**
   - Tabelas grandes particionadas por data
   - Melhora significativa em consultas temporais

3. **Views Materializadas**
   - Refresh automático via pg_cron
   - Consultas complexas pré-calculadas

4. **Cache Redis**
   - Múltiplos databases especializados
   - TTL otimizado por tipo de dado

### Benchmarks Esperados

- **Consulta de afiliado**: < 10ms (com cache)
- **Cálculo de comissões**: < 100ms
- **Relatório mensal**: < 500ms
- **Dashboard principal**: < 200ms

## 🔐 Segurança

### Configurações de Segurança

1. **PostgreSQL**
   - Usuário dedicado com permissões limitadas
   - SSL/TLS em produção
   - Backup automático criptografado

2. **Redis**
   - Senha obrigatória em produção
   - Comandos perigosos desabilitados
   - Bind apenas para IPs autorizados

3. **Auditoria**
   - Log completo de todas as operações
   - Tabela `data_audit` particionada
   - Triggers automáticos de auditoria

## 🛠️ Manutenção

### Scripts de Manutenção

```bash
# Backup do banco
pg_dump -U fature_user fature_db > backup_$(date +%Y%m%d).sql

# Limpeza de partições antigas
SELECT drop_old_partitions('transactions', '3 months');

# Refresh de views materializadas
SELECT refresh_all_materialized_views();

# Estatísticas do cache
SELECT * FROM cache_stats();
```

### Monitoramento

- **PostgreSQL**: Logs em `/var/log/postgresql/`
- **Redis**: Logs em `/var/log/redis/`
- **Métricas**: Views de performance disponíveis
- **Health Check**: Endpoints de saúde implementados

## 📚 Documentação Adicional

- [Guia de Instalação](docs/installation.md)
- [Manual de Migração](docs/migration.md)
- [Referência de APIs](docs/api-reference.md)
- [Troubleshooting](docs/troubleshooting.md)

## 🤝 Contribuição

1. Fork o projeto
2. Crie uma branch para sua feature (`git checkout -b feature/nova-feature`)
3. Commit suas mudanças (`git commit -am 'Adiciona nova feature'`)
4. Push para a branch (`git push origin feature/nova-feature`)
5. Abra um Pull Request

## 📄 Licença

Este projeto está licenciado sob a Licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.

## 📞 Suporte

Para suporte técnico ou dúvidas:

- **Email**: suporte@fature.com
- **Issues**: [GitHub Issues](https://github.com/seu-usuario/fature-database/issues)
- **Documentação**: [Wiki do Projeto](https://github.com/seu-usuario/fature-database/wiki)

---

**Desenvolvido com ❤️ pela equipe Fature**

*Sistema de banco de dados otimizado para alta performance e escalabilidade*

