-- =====================================================
-- FATURE DATABASE - SCHEMA PRINCIPAL
-- Sistema de Afiliados com Integração de Dados Históricos
-- =====================================================

-- Extensões necessárias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- =====================================================
-- TIPOS ENUMERADOS (ENUMs)
-- =====================================================

-- Status de usuários
CREATE TYPE user_status AS ENUM ('pending', 'active', 'inactive', 'suspended', 'banned');

-- Categorias de afiliados
CREATE TYPE affiliate_category AS ENUM ('standard', 'premium', 'vip', 'diamond');

-- Status de afiliados
CREATE TYPE affiliate_status AS ENUM ('active', 'inactive', 'suspended', 'pending_reactivation');

-- Tipos de transação
CREATE TYPE transaction_type AS ENUM ('sale', 'deposit', 'bet', 'bonus', 'adjustment');

-- Status de transação
CREATE TYPE transaction_status AS ENUM ('pending', 'processed', 'failed', 'cancelled');

-- Status de comissão
CREATE TYPE commission_status AS ENUM ('calculated', 'approved', 'paid', 'cancelled', 'disputed');

-- Raridade de baús
CREATE TYPE chest_rarity AS ENUM ('common', 'rare', 'epic', 'legendary');

-- Status de baús
CREATE TYPE chest_status AS ENUM ('available', 'opened', 'expired');

-- Tipos de ranking
CREATE TYPE ranking_type AS ENUM ('monthly', 'quarterly', 'annual', 'special_event');

-- Status de ranking
CREATE TYPE ranking_status AS ENUM ('draft', 'active', 'completed', 'cancelled');

-- Status de sequência
CREATE TYPE sequence_status AS ENUM ('active', 'paused', 'completed', 'expired');

-- Status de inatividade
CREATE TYPE inactivity_status AS ENUM ('active', 'reactivated', 'expired');

-- Severidade de logs
CREATE TYPE log_severity AS ENUM ('debug', 'info', 'warning', 'error', 'critical');

-- =====================================================
-- TABELAS PRINCIPAIS
-- =====================================================

-- Tabela de usuários
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255),
    name VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    document VARCHAR(20) UNIQUE,
    status user_status NOT NULL DEFAULT 'pending',
    email_verified_at TIMESTAMP,
    phone_verified_at TIMESTAMP,
    last_login_at TIMESTAMP,
    mfa_secret VARCHAR(255),
    mfa_enabled BOOLEAN NOT NULL DEFAULT false,
    
    -- Campos de migração
    original_id VARCHAR(255), -- ID original do sistema antigo
    migrated_from VARCHAR(50), -- Sistema de origem
    
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMP,
    
    CONSTRAINT valid_email CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT valid_phone CHECK (phone IS NULL OR phone ~* '^\+?[1-9]\d{1,14}$')
);

-- Sessões de usuário
CREATE TABLE user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_token VARCHAR(255) UNIQUE NOT NULL,
    device_fingerprint VARCHAR(255),
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMP NOT NULL,
    last_used_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    CONSTRAINT valid_expires_at CHECK (expires_at > created_at)
);

-- Tabela de afiliados
CREATE TABLE affiliates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES affiliates(id),
    referral_code VARCHAR(20) UNIQUE NOT NULL,
    category affiliate_category NOT NULL DEFAULT 'standard',
    level INTEGER NOT NULL DEFAULT 0,
    status affiliate_status NOT NULL DEFAULT 'active',
    joined_at TIMESTAMP NOT NULL DEFAULT NOW(),
    last_activity_at TIMESTAMP,
    inactivity_applied_at TIMESTAMP,
    reactivation_count INTEGER NOT NULL DEFAULT 0,
    total_referrals INTEGER NOT NULL DEFAULT 0,
    active_referrals INTEGER NOT NULL DEFAULT 0,
    lifetime_volume DECIMAL(15,2) NOT NULL DEFAULT 0,
    lifetime_commissions DECIMAL(15,2) NOT NULL DEFAULT 0,
    current_month_volume DECIMAL(15,2) NOT NULL DEFAULT 0,
    current_month_commissions DECIMAL(15,2) NOT NULL DEFAULT 0,
    metadata JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    CONSTRAINT valid_referral_code CHECK (referral_code ~* '^[A-Z0-9]{6,20}$'),
    CONSTRAINT valid_level CHECK (level >= 0 AND level <= 10),
    CONSTRAINT no_self_reference CHECK (id != parent_id),
    CONSTRAINT positive_metrics CHECK (
        total_referrals >= 0 AND 
        active_referrals >= 0 AND 
        lifetime_volume >= 0 AND 
        lifetime_commissions >= 0 AND
        current_month_volume >= 0 AND
        current_month_commissions >= 0
    )
);

-- Hierarquia de afiliados (closure table)
CREATE TABLE affiliate_hierarchy (
    descendant_id UUID NOT NULL REFERENCES affiliates(id) ON DELETE CASCADE,
    ancestor_id UUID NOT NULL REFERENCES affiliates(id) ON DELETE CASCADE,
    level_difference INTEGER NOT NULL,
    path_length INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    PRIMARY KEY (descendant_id, ancestor_id),
    CONSTRAINT valid_level_difference CHECK (level_difference >= 0),
    CONSTRAINT valid_path_length CHECK (path_length > 0)
);

-- Tabela de transações (particionada por data)
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_id VARCHAR(255) UNIQUE,
    affiliate_id UUID NOT NULL REFERENCES affiliates(id),
    customer_id UUID,
    type transaction_type NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'BRL',
    status transaction_status NOT NULL DEFAULT 'pending',
    processed_at TIMESTAMP,
    
    -- Campos específicos para migração
    original_id VARCHAR(255), -- ID original da transação
    source_table VARCHAR(50), -- Tabela de origem (deposits, casino_bets)
    
    metadata JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    CONSTRAINT positive_amount CHECK (amount > 0),
    CONSTRAINT valid_currency CHECK (currency IN ('BRL', 'USD', 'EUR'))
) PARTITION BY RANGE (created_at);

-- Partições para transações (2025)
CREATE TABLE transactions_2025_01 PARTITION OF transactions
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE transactions_2025_02 PARTITION OF transactions
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
CREATE TABLE transactions_2025_03 PARTITION OF transactions
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');
CREATE TABLE transactions_2025_04 PARTITION OF transactions
    FOR VALUES FROM ('2025-04-01') TO ('2025-05-01');
CREATE TABLE transactions_2025_05 PARTITION OF transactions
    FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
CREATE TABLE transactions_2025_06 PARTITION OF transactions
    FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');
CREATE TABLE transactions_2025_07 PARTITION OF transactions
    FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');
CREATE TABLE transactions_2025_08 PARTITION OF transactions
    FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');
CREATE TABLE transactions_2025_09 PARTITION OF transactions
    FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');
CREATE TABLE transactions_2025_10 PARTITION OF transactions
    FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
CREATE TABLE transactions_2025_11 PARTITION OF transactions
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');
CREATE TABLE transactions_2025_12 PARTITION OF transactions
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

-- Tabela de comissões (particionada por data)
CREATE TABLE commissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL REFERENCES transactions(id),
    affiliate_id UUID NOT NULL REFERENCES affiliates(id),
    source_affiliate_id UUID NOT NULL REFERENCES affiliates(id),
    level INTEGER NOT NULL,
    base_amount DECIMAL(15,2) NOT NULL,
    percentage DECIMAL(5,2) NOT NULL,
    commission_amount DECIMAL(15,2) NOT NULL,
    bonus_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    final_amount DECIMAL(15,2) NOT NULL,
    status commission_status NOT NULL DEFAULT 'calculated',
    calculation_rules JSONB,
    processed_at TIMESTAMP,
    paid_at TIMESTAMP,
    payment_reference VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    CONSTRAINT positive_amounts CHECK (
        base_amount > 0 AND 
        commission_amount >= 0 AND 
        bonus_amount >= 0 AND 
        final_amount >= 0
    ),
    CONSTRAINT valid_percentage CHECK (percentage >= 0 AND percentage <= 100),
    CONSTRAINT valid_level CHECK (level >= 1 AND level <= 10)
) PARTITION BY RANGE (created_at);

-- Partições para comissões (2025)
CREATE TABLE commissions_2025_01 PARTITION OF commissions
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE commissions_2025_02 PARTITION OF commissions
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
CREATE TABLE commissions_2025_03 PARTITION OF commissions
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');
CREATE TABLE commissions_2025_04 PARTITION OF commissions
    FOR VALUES FROM ('2025-04-01') TO ('2025-05-01');
CREATE TABLE commissions_2025_05 PARTITION OF commissions
    FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
CREATE TABLE commissions_2025_06 PARTITION OF commissions
    FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');
CREATE TABLE commissions_2025_07 PARTITION OF commissions
    FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');
CREATE TABLE commissions_2025_08 PARTITION OF commissions
    FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');
CREATE TABLE commissions_2025_09 PARTITION OF commissions
    FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');
CREATE TABLE commissions_2025_10 PARTITION OF commissions
    FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
CREATE TABLE commissions_2025_11 PARTITION OF commissions
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');
CREATE TABLE commissions_2025_12 PARTITION OF commissions
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

-- =====================================================
-- TABELAS DE GAMIFICAÇÃO
-- =====================================================

-- Atividades diárias
CREATE TABLE daily_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    activity_type VARCHAR(50) NOT NULL,
    activity_date DATE NOT NULL,
    points_earned INTEGER NOT NULL DEFAULT 0,
    metadata JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    UNIQUE(user_id, activity_type, activity_date),
    CONSTRAINT positive_points CHECK (points_earned >= 0)
);

-- Sequências diárias
CREATE TABLE daily_sequences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    current_streak INTEGER NOT NULL DEFAULT 0,
    longest_streak INTEGER NOT NULL DEFAULT 0,
    last_activity_date DATE,
    next_reward_day INTEGER NOT NULL DEFAULT 1,
    total_points INTEGER NOT NULL DEFAULT 0,
    status sequence_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    UNIQUE(user_id),
    CONSTRAINT valid_streaks CHECK (current_streak >= 0 AND longest_streak >= current_streak),
    CONSTRAINT valid_next_reward CHECK (next_reward_day >= 1 AND next_reward_day <= 30),
    CONSTRAINT positive_points CHECK (total_points >= 0)
);

-- Tipos de baús
CREATE TABLE chest_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    rarity chest_rarity NOT NULL,
    unlock_criteria JSONB NOT NULL,
    reward_probabilities JSONB NOT NULL,
    cooldown_hours INTEGER NOT NULL DEFAULT 24,
    max_per_day INTEGER NOT NULL DEFAULT 1,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    CONSTRAINT valid_cooldown CHECK (cooldown_hours >= 0),
    CONSTRAINT valid_max_per_day CHECK (max_per_day >= 0)
);

-- Baús dos usuários
CREATE TABLE user_chests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    chest_type_id UUID NOT NULL REFERENCES chest_types(id),
    status chest_status NOT NULL DEFAULT 'available',
    generated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    opened_at TIMESTAMP,
    reward_obtained JSONB,
    expires_at TIMESTAMP,
    
    CONSTRAINT valid_status_timing CHECK (
        (status = 'available' AND opened_at IS NULL) OR
        (status = 'opened' AND opened_at IS NOT NULL) OR
        (status = 'expired')
    )
);

-- =====================================================
-- TABELAS DE RANKINGS
-- =====================================================

-- Rankings
CREATE TABLE rankings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    type ranking_type NOT NULL,
    calculation_criteria JSONB NOT NULL,
    eligibility_rules JSONB,
    reward_structure JSONB NOT NULL,
    start_date TIMESTAMP NOT NULL,
    end_date TIMESTAMP NOT NULL,
    status ranking_status NOT NULL DEFAULT 'draft',
    max_participants INTEGER,
    current_participants INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    CONSTRAINT valid_dates CHECK (end_date > start_date),
    CONSTRAINT valid_participants CHECK (
        max_participants IS NULL OR 
        current_participants <= max_participants
    )
);

-- Participantes dos rankings
CREATE TABLE ranking_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ranking_id UUID NOT NULL REFERENCES rankings(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    current_position INTEGER,
    previous_position INTEGER,
    score DECIMAL(15,2) NOT NULL DEFAULT 0,
    metrics JSONB,
    last_updated TIMESTAMP NOT NULL DEFAULT NOW(),
    
    UNIQUE(ranking_id, user_id),
    CONSTRAINT positive_score CHECK (score >= 0),
    CONSTRAINT valid_positions CHECK (
        current_position IS NULL OR current_position > 0
    )
);

-- =====================================================
-- TABELAS DE CONFIGURAÇÃO E AUDITORIA
-- =====================================================

-- Regras de inatividade
CREATE TABLE inactivity_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    affiliate_categories affiliate_category[],
    inactivity_period_days INTEGER NOT NULL,
    reduction_intervals JSONB NOT NULL,
    reactivation_criteria JSONB,
    notification_schedule JSONB,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    CONSTRAINT valid_inactivity_period CHECK (inactivity_period_days > 0),
    CONSTRAINT non_empty_categories CHECK (array_length(affiliate_categories, 1) > 0)
);

-- Status de inatividade dos afiliados
CREATE TABLE affiliate_inactivity_status (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    affiliate_id UUID NOT NULL REFERENCES affiliates(id) ON DELETE CASCADE,
    rule_id UUID NOT NULL REFERENCES inactivity_rules(id),
    applied_at TIMESTAMP NOT NULL,
    current_reduction_percentage DECIMAL(5,2) NOT NULL DEFAULT 0,
    next_reduction_date TIMESTAMP,
    status inactivity_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    UNIQUE(affiliate_id, rule_id),
    CONSTRAINT valid_reduction CHECK (current_reduction_percentage >= 0 AND current_reduction_percentage <= 100)
);

-- Log de migração de dados
CREATE TABLE data_migration_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_table VARCHAR(100) NOT NULL,
    source_file VARCHAR(255),
    records_processed INTEGER NOT NULL DEFAULT 0,
    records_success INTEGER NOT NULL DEFAULT 0,
    records_failed INTEGER NOT NULL DEFAULT 0,
    migration_date TIMESTAMP NOT NULL DEFAULT NOW(),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    error_details JSONB,
    
    CONSTRAINT valid_status CHECK (status IN ('pending', 'running', 'completed', 'failed'))
);

-- Mapeamento de IDs para migração
CREATE TABLE id_mapping (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_system VARCHAR(50) NOT NULL,
    source_id VARCHAR(255) NOT NULL,
    target_table VARCHAR(100) NOT NULL,
    target_id UUID NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    UNIQUE(source_system, source_id, target_table)
);

-- Auditoria de dados
CREATE TABLE data_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name VARCHAR(100) NOT NULL,
    record_id UUID NOT NULL,
    operation VARCHAR(10) NOT NULL, -- INSERT, UPDATE, DELETE
    old_values JSONB,
    new_values JSONB,
    changed_by UUID REFERENCES users(id),
    changed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    source_system VARCHAR(50) DEFAULT 'fature'
) PARTITION BY RANGE (changed_at);

-- Partições para auditoria (2025)
CREATE TABLE data_audit_2025_01 PARTITION OF data_audit
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE data_audit_2025_02 PARTITION OF data_audit
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
CREATE TABLE data_audit_2025_03 PARTITION OF data_audit
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');
CREATE TABLE data_audit_2025_04 PARTITION OF data_audit
    FOR VALUES FROM ('2025-04-01') TO ('2025-05-01');
CREATE TABLE data_audit_2025_05 PARTITION OF data_audit
    FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
CREATE TABLE data_audit_2025_06 PARTITION OF data_audit
    FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');
CREATE TABLE data_audit_2025_07 PARTITION OF data_audit
    FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');
CREATE TABLE data_audit_2025_08 PARTITION OF data_audit
    FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');
CREATE TABLE data_audit_2025_09 PARTITION OF data_audit
    FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');
CREATE TABLE data_audit_2025_10 PARTITION OF data_audit
    FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
CREATE TABLE data_audit_2025_11 PARTITION OF data_audit
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');
CREATE TABLE data_audit_2025_12 PARTITION OF data_audit
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

-- =====================================================
-- COMENTÁRIOS NAS TABELAS
-- =====================================================

COMMENT ON TABLE users IS 'Tabela principal de usuários do sistema';
COMMENT ON TABLE affiliates IS 'Tabela de afiliados com hierarquia MLM';
COMMENT ON TABLE affiliate_hierarchy IS 'Closure table para hierarquia de afiliados';
COMMENT ON TABLE transactions IS 'Transações particionadas por data';
COMMENT ON TABLE commissions IS 'Comissões calculadas e pagas';
COMMENT ON TABLE data_migration_log IS 'Log de migração de dados históricos';
COMMENT ON TABLE id_mapping IS 'Mapeamento de IDs entre sistemas';
COMMENT ON TABLE data_audit IS 'Auditoria de mudanças nos dados';

