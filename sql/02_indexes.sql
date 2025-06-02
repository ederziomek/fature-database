-- =====================================================
-- FATURE DATABASE - ÍNDICES PARA PERFORMANCE
-- Otimizações para consultas frequentes
-- =====================================================

-- =====================================================
-- ÍNDICES PARA TABELA USERS
-- =====================================================

-- Índice para busca por email (login)
CREATE INDEX CONCURRENTLY idx_users_email 
ON users(email) 
WHERE deleted_at IS NULL;

-- Índice para status de usuários ativos
CREATE INDEX CONCURRENTLY idx_users_status 
ON users(status) 
WHERE deleted_at IS NULL AND status = 'active';

-- Índice para ordenação por data de criação
CREATE INDEX CONCURRENTLY idx_users_created_at 
ON users(created_at DESC);

-- Índice para migração (busca por ID original)
CREATE INDEX CONCURRENTLY idx_users_original_id 
ON users(original_id, migrated_from) 
WHERE original_id IS NOT NULL;

-- =====================================================
-- ÍNDICES PARA TABELA USER_SESSIONS
-- =====================================================

-- Índice para busca por usuário
CREATE INDEX CONCURRENTLY idx_user_sessions_user_id 
ON user_sessions(user_id);

-- Índice para busca por token
CREATE INDEX CONCURRENTLY idx_user_sessions_token 
ON user_sessions(session_token);

-- Índice para limpeza de sessões expiradas
CREATE INDEX CONCURRENTLY idx_user_sessions_expires_at 
ON user_sessions(expires_at) 
WHERE expires_at < NOW();

-- =====================================================
-- ÍNDICES PARA TABELA AFFILIATES
-- =====================================================

-- Índice único para relacionamento user-affiliate
CREATE UNIQUE INDEX CONCURRENTLY idx_affiliates_user_id 
ON affiliates(user_id);

-- Índice único para código de referência
CREATE UNIQUE INDEX CONCURRENTLY idx_affiliates_referral_code 
ON affiliates(referral_code);

-- Índice para hierarquia (busca por parent)
CREATE INDEX CONCURRENTLY idx_affiliates_parent_id 
ON affiliates(parent_id) 
WHERE parent_id IS NOT NULL;

-- Índice composto para performance de afiliados ativos
CREATE INDEX CONCURRENTLY idx_affiliates_performance 
ON affiliates(status, category, level) 
WHERE status = 'active';

-- Índice para busca por categoria
CREATE INDEX CONCURRENTLY idx_affiliates_category 
ON affiliates(category);

-- Índice para busca por nível
CREATE INDEX CONCURRENTLY idx_affiliates_level 
ON affiliates(level);

-- Índice para última atividade (inatividade)
CREATE INDEX CONCURRENTLY idx_affiliates_last_activity 
ON affiliates(last_activity_at) 
WHERE last_activity_at IS NOT NULL;

-- Índice para volume mensal (rankings)
CREATE INDEX CONCURRENTLY idx_affiliates_monthly_volume 
ON affiliates(current_month_volume DESC) 
WHERE status = 'active';

-- =====================================================
-- ÍNDICES PARA TABELA AFFILIATE_HIERARCHY
-- =====================================================

-- Índice para busca de descendentes
CREATE INDEX CONCURRENTLY idx_affiliate_hierarchy_ancestor 
ON affiliate_hierarchy(ancestor_id, level_difference);

-- Índice para busca de ancestrais
CREATE INDEX CONCURRENTLY idx_affiliate_hierarchy_descendant 
ON affiliate_hierarchy(descendant_id, level_difference);

-- Índice composto para navegação na hierarquia
CREATE INDEX CONCURRENTLY idx_affiliate_hierarchy_levels 
ON affiliate_hierarchy(ancestor_id, level_difference, descendant_id);

-- =====================================================
-- ÍNDICES PARA TABELA TRANSACTIONS (PARTICIONADA)
-- =====================================================

-- Índices para cada partição de transações
-- Nota: Estes índices serão criados automaticamente para cada partição

-- Template para índices de transações
-- CREATE INDEX CONCURRENTLY idx_transactions_YYYY_MM_affiliate_date 
-- ON transactions_YYYY_MM(affiliate_id, created_at DESC);

-- Criar índices para partições de 2025
DO $$
DECLARE
    partition_name TEXT;
    month_num INTEGER;
BEGIN
    FOR month_num IN 1..12 LOOP
        partition_name := 'transactions_2025_' || LPAD(month_num::TEXT, 2, '0');
        
        -- Índice por afiliado e data
        EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_affiliate_date ON %s(affiliate_id, created_at DESC)', 
                      partition_name, partition_name);
        
        -- Índice por ID externo
        EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_external_id ON %s(external_id) WHERE external_id IS NOT NULL', 
                      partition_name, partition_name);
        
        -- Índice por status e data
        EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_status_date ON %s(status, created_at DESC)', 
                      partition_name, partition_name);
        
        -- Índice por tipo de transação
        EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_type_date ON %s(type, created_at DESC)', 
                      partition_name, partition_name);
        
        -- Índice por customer_id
        EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_customer_id ON %s(customer_id) WHERE customer_id IS NOT NULL', 
                      partition_name, partition_name);
        
        -- Índice para migração
        EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_original_id ON %s(original_id, source_table) WHERE original_id IS NOT NULL', 
                      partition_name, partition_name);
    END LOOP;
END $$;

-- =====================================================
-- ÍNDICES PARA TABELA COMMISSIONS (PARTICIONADA)
-- =====================================================

-- Criar índices para partições de comissões 2025
DO $$
DECLARE
    partition_name TEXT;
    month_num INTEGER;
BEGIN
    FOR month_num IN 1..12 LOOP
        partition_name := 'commissions_2025_' || LPAD(month_num::TEXT, 2, '0');
        
        -- Índice por afiliado e data
        EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_affiliate_date ON %s(affiliate_id, created_at DESC)', 
                      partition_name, partition_name);
        
        -- Índice por transação
        EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_transaction ON %s(transaction_id)', 
                      partition_name, partition_name);
        
        -- Índice por status e data (para pagamentos)
        EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_status_date ON %s(status, created_at) WHERE status IN (''calculated'', ''approved'')', 
                      partition_name, partition_name);
        
        -- Índice por afiliado de origem
        EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_source_affiliate ON %s(source_affiliate_id, created_at DESC)', 
                      partition_name, partition_name);
        
        -- Índice por nível de comissão
        EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_level ON %s(level, affiliate_id)', 
                      partition_name, partition_name);
    END LOOP;
END $$;

-- =====================================================
-- ÍNDICES PARA TABELAS DE GAMIFICAÇÃO
-- =====================================================

-- Índices para daily_activities
CREATE INDEX CONCURRENTLY idx_daily_activities_user_date 
ON daily_activities(user_id, activity_date DESC);

CREATE INDEX CONCURRENTLY idx_daily_activities_type_date 
ON daily_activities(activity_type, activity_date DESC);

-- Índices para daily_sequences
CREATE INDEX CONCURRENTLY idx_daily_sequences_status 
ON daily_sequences(status);

CREATE INDEX CONCURRENTLY idx_daily_sequences_streak 
ON daily_sequences(current_streak DESC) 
WHERE status = 'active';

-- Índices para chest_types
CREATE INDEX CONCURRENTLY idx_chest_types_rarity 
ON chest_types(rarity) 
WHERE is_active = true;

CREATE INDEX CONCURRENTLY idx_chest_types_active 
ON chest_types(is_active);

-- Índices para user_chests
CREATE INDEX CONCURRENTLY idx_user_chests_user_status 
ON user_chests(user_id, status) 
WHERE status = 'available';

CREATE INDEX CONCURRENTLY idx_user_chests_expires_at 
ON user_chests(expires_at) 
WHERE expires_at IS NOT NULL;

-- =====================================================
-- ÍNDICES PARA TABELAS DE RANKINGS
-- =====================================================

-- Índices para rankings
CREATE INDEX CONCURRENTLY idx_rankings_status_dates 
ON rankings(status, start_date, end_date);

CREATE INDEX CONCURRENTLY idx_rankings_type 
ON rankings(type);

CREATE INDEX CONCURRENTLY idx_rankings_active 
ON rankings(status, start_date, end_date) 
WHERE status = 'active' AND start_date <= NOW() AND end_date >= NOW();

-- Índices para ranking_participants
CREATE INDEX CONCURRENTLY idx_ranking_participants_ranking_score 
ON ranking_participants(ranking_id, score DESC);

CREATE INDEX CONCURRENTLY idx_ranking_participants_user 
ON ranking_participants(user_id);

CREATE INDEX CONCURRENTLY idx_ranking_participants_position 
ON ranking_participants(ranking_id, current_position) 
WHERE current_position IS NOT NULL;

-- =====================================================
-- ÍNDICES PARA TABELAS DE CONFIGURAÇÃO
-- =====================================================

-- Índices para inactivity_rules
CREATE INDEX CONCURRENTLY idx_inactivity_rules_active 
ON inactivity_rules(is_active);

CREATE INDEX CONCURRENTLY idx_inactivity_rules_categories 
ON inactivity_rules USING GIN(affiliate_categories);

-- Índices para affiliate_inactivity_status
CREATE INDEX CONCURRENTLY idx_affiliate_inactivity_status_affiliate 
ON affiliate_inactivity_status(affiliate_id);

CREATE INDEX CONCURRENTLY idx_affiliate_inactivity_status_next_reduction 
ON affiliate_inactivity_status(next_reduction_date) 
WHERE next_reduction_date IS NOT NULL AND status = 'active';

-- =====================================================
-- ÍNDICES PARA TABELAS DE AUDITORIA E MIGRAÇÃO
-- =====================================================

-- Índices para data_migration_log
CREATE INDEX CONCURRENTLY idx_data_migration_log_status 
ON data_migration_log(status, migration_date DESC);

CREATE INDEX CONCURRENTLY idx_data_migration_log_source 
ON data_migration_log(source_table, migration_date DESC);

-- Índices para id_mapping
CREATE INDEX CONCURRENTLY idx_id_mapping_source 
ON id_mapping(source_system, source_id);

CREATE INDEX CONCURRENTLY idx_id_mapping_target 
ON id_mapping(target_table, target_id);

-- Índices para data_audit (particionada)
DO $$
DECLARE
    partition_name TEXT;
    month_num INTEGER;
BEGIN
    FOR month_num IN 1..12 LOOP
        partition_name := 'data_audit_2025_' || LPAD(month_num::TEXT, 2, '0');
        
        -- Índice por tabela e registro
        EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_table_record ON %s(table_name, record_id)', 
                      partition_name, partition_name);
        
        -- Índice por operação e data
        EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_operation_date ON %s(operation, changed_at DESC)', 
                      partition_name, partition_name);
        
        -- Índice por usuário que fez a mudança
        EXECUTE format('CREATE INDEX CONCURRENTLY idx_%s_changed_by ON %s(changed_by) WHERE changed_by IS NOT NULL', 
                      partition_name, partition_name);
    END LOOP;
END $$;

-- =====================================================
-- ÍNDICES ESPECIAIS PARA PERFORMANCE
-- =====================================================

-- Índice para busca rápida de afiliados por volume
CREATE INDEX CONCURRENTLY idx_affiliates_volume_ranking 
ON affiliates(lifetime_volume DESC, current_month_volume DESC) 
WHERE status = 'active';

-- Índice para busca rápida de comissões não pagas
CREATE INDEX CONCURRENTLY idx_commissions_unpaid 
ON commissions(status, affiliate_id, final_amount DESC) 
WHERE status IN ('calculated', 'approved');

-- Índice para busca de transações por período
CREATE INDEX CONCURRENTLY idx_transactions_period 
ON transactions(created_at, affiliate_id, amount) 
WHERE status = 'processed';

-- =====================================================
-- ESTATÍSTICAS E MANUTENÇÃO
-- =====================================================

-- Atualizar estatísticas após criação dos índices
ANALYZE users;
ANALYZE affiliates;
ANALYZE affiliate_hierarchy;
ANALYZE transactions;
ANALYZE commissions;
ANALYZE daily_activities;
ANALYZE daily_sequences;
ANALYZE rankings;
ANALYZE ranking_participants;

-- Comentários sobre os índices
COMMENT ON INDEX idx_users_email IS 'Índice para login por email';
COMMENT ON INDEX idx_affiliates_performance IS 'Índice composto para performance de afiliados ativos';
COMMENT ON INDEX idx_affiliate_hierarchy_levels IS 'Índice para navegação eficiente na hierarquia MLM';
COMMENT ON INDEX idx_affiliates_volume_ranking IS 'Índice para rankings por volume de vendas';

