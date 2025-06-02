-- =====================================================
-- FATURE DATABASE - MIGRAÇÃO DE DADOS HISTÓRICOS
-- Scripts para migrar dados das planilhas Excel
-- =====================================================

-- =====================================================
-- PREPARAÇÃO PARA MIGRAÇÃO
-- =====================================================

-- Criar tabelas temporárias para importação dos dados
CREATE TEMP TABLE temp_users (
    id TEXT,
    username TEXT,
    email TEXT,
    email_confirmed BOOLEAN,
    details_confirmed BOOLEAN,
    created_at TEXT,
    updated_at TEXT,
    -- Outros campos conforme necessário
    raw_data JSONB
);

CREATE TEMP TABLE temp_deposits (
    user_id TEXT,
    id TEXT,
    account_id TEXT,
    session_id TEXT,
    type TEXT,
    amount DECIMAL(15,2),
    currency TEXT,
    status TEXT,
    created_at TEXT,
    updated_at TEXT,
    internal_cpf BIGINT,
    internal_payer_full_name TEXT,
    gateway_id TEXT,
    pix_copia_e_cola TEXT,
    -- Outros campos
    raw_data JSONB
);

CREATE TEMP TABLE temp_casino_bets (
    id TEXT,
    user_id TEXT,
    reference_game_id TEXT,
    balance_type TEXT,
    amount DECIMAL(15,2),
    win_amount DECIMAL(15,2),
    profit DECIMAL(15,2),
    created_at TEXT,
    -- Outros campos
    raw_data JSONB
);

-- =====================================================
-- FUNÇÃO: MIGRAÇÃO DE USUÁRIOS
-- =====================================================

CREATE OR REPLACE FUNCTION migrate_users()
RETURNS TABLE (
    migrated_count INTEGER,
    error_count INTEGER,
    details JSONB
) AS $$
DECLARE
    success_count INTEGER := 0;
    error_count INTEGER := 0;
    current_user RECORD;
    error_details JSONB := '[]'::JSONB;
BEGIN
    -- Log início da migração
    INSERT INTO data_migration_log (source_table, source_file, status)
    VALUES ('users', 'upbet_plataforma_public_users.xlsx', 'running');
    
    -- Migrar usuários
    FOR current_user IN SELECT * FROM temp_users LOOP
        BEGIN
            INSERT INTO users (
                id,
                email,
                name,
                status,
                email_verified_at,
                original_id,
                migrated_from,
                created_at,
                updated_at
            ) VALUES (
                current_user.id::UUID,
                current_user.email,
                COALESCE(current_user.username, 'Usuário Migrado'),
                'active'::user_status,
                CASE 
                    WHEN current_user.email_confirmed THEN current_user.created_at::TIMESTAMP
                    ELSE NULL 
                END,
                current_user.id,
                'upbet_platform',
                current_user.created_at::TIMESTAMP,
                current_user.updated_at::TIMESTAMP
            );
            
            -- Registrar mapeamento de ID
            INSERT INTO id_mapping (source_system, source_id, target_table, target_id)
            VALUES ('upbet_platform', current_user.id, 'users', current_user.id::UUID);
            
            success_count := success_count + 1;
            
        EXCEPTION WHEN OTHERS THEN
            error_count := error_count + 1;
            error_details := error_details || jsonb_build_object(
                'user_id', current_user.id,
                'error', SQLERRM
            );
        END;
    END LOOP;
    
    -- Atualizar log de migração
    UPDATE data_migration_log 
    SET 
        records_processed = success_count + error_count,
        records_success = success_count,
        records_failed = error_count,
        status = CASE WHEN error_count = 0 THEN 'completed' ELSE 'completed_with_errors' END,
        error_details = error_details
    WHERE source_table = 'users' AND status = 'running';
    
    RETURN QUERY SELECT success_count, error_count, error_details;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNÇÃO: CRIAÇÃO DE AFILIADOS
-- =====================================================

CREATE OR REPLACE FUNCTION create_affiliates_from_users()
RETURNS TABLE (
    created_count INTEGER,
    error_count INTEGER,
    details JSONB
) AS $$
DECLARE
    success_count INTEGER := 0;
    error_count INTEGER := 0;
    current_user RECORD;
    referral_code TEXT;
    error_details JSONB := '[]'::JSONB;
BEGIN
    -- Log início da criação
    INSERT INTO data_migration_log (source_table, source_file, status)
    VALUES ('affiliates', 'generated_from_users', 'running');
    
    -- Criar afiliados para todos os usuários migrados
    FOR current_user IN 
        SELECT * FROM users 
        WHERE migrated_from = 'upbet_platform' 
        AND deleted_at IS NULL 
    LOOP
        BEGIN
            -- Gerar código de referência único
            referral_code := UPPER(SUBSTRING(MD5(current_user.id::TEXT || current_user.email), 1, 8));
            
            -- Verificar se já existe
            WHILE EXISTS (SELECT 1 FROM affiliates WHERE referral_code = referral_code) LOOP
                referral_code := UPPER(SUBSTRING(MD5(random()::TEXT || current_user.id::TEXT), 1, 8));
            END LOOP;
            
            INSERT INTO affiliates (
                user_id,
                referral_code,
                category,
                level,
                status,
                joined_at,
                last_activity_at
            ) VALUES (
                current_user.id,
                referral_code,
                'standard'::affiliate_category,
                0,
                'active'::affiliate_status,
                current_user.created_at,
                current_user.updated_at
            );
            
            success_count := success_count + 1;
            
        EXCEPTION WHEN OTHERS THEN
            error_count := error_count + 1;
            error_details := error_details || jsonb_build_object(
                'user_id', current_user.id,
                'error', SQLERRM
            );
        END;
    END LOOP;
    
    -- Atualizar log
    UPDATE data_migration_log 
    SET 
        records_processed = success_count + error_count,
        records_success = success_count,
        records_failed = error_count,
        status = CASE WHEN error_count = 0 THEN 'completed' ELSE 'completed_with_errors' END,
        error_details = error_details
    WHERE source_table = 'affiliates' AND status = 'running';
    
    RETURN QUERY SELECT success_count, error_count, error_details;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNÇÃO: MIGRAÇÃO DE DEPÓSITOS
-- =====================================================

CREATE OR REPLACE FUNCTION migrate_deposits()
RETURNS TABLE (
    migrated_count INTEGER,
    error_count INTEGER,
    details JSONB
) AS $$
DECLARE
    success_count INTEGER := 0;
    error_count INTEGER := 0;
    current_deposit RECORD;
    affiliate_id UUID;
    error_details JSONB := '[]'::JSONB;
BEGIN
    -- Log início da migração
    INSERT INTO data_migration_log (source_table, source_file, status)
    VALUES ('transactions_deposits', 'deposits.xlsx', 'running');
    
    -- Migrar depósitos
    FOR current_deposit IN SELECT * FROM temp_deposits LOOP
        BEGIN
            -- Buscar afiliado do usuário
            SELECT a.id INTO affiliate_id
            FROM affiliates a
            JOIN users u ON a.user_id = u.id
            WHERE u.original_id = current_deposit.user_id
            AND u.migrated_from = 'upbet_platform';
            
            IF affiliate_id IS NOT NULL THEN
                INSERT INTO transactions (
                    id,
                    external_id,
                    affiliate_id,
                    customer_id,
                    type,
                    amount,
                    currency,
                    status,
                    processed_at,
                    original_id,
                    source_table,
                    created_at,
                    updated_at,
                    metadata
                ) VALUES (
                    current_deposit.id::UUID,
                    current_deposit.id,
                    affiliate_id,
                    (SELECT u.id FROM users u WHERE u.original_id = current_deposit.user_id),
                    'deposit'::transaction_type,
                    current_deposit.amount,
                    COALESCE(current_deposit.currency, 'BRL'),
                    CASE 
                        WHEN current_deposit.status = 'completed' THEN 'processed'::transaction_status
                        WHEN current_deposit.status = 'pending' THEN 'pending'::transaction_status
                        ELSE 'failed'::transaction_status
                    END,
                    current_deposit.updated_at::TIMESTAMP,
                    current_deposit.id,
                    'deposits',
                    current_deposit.created_at::TIMESTAMP,
                    current_deposit.updated_at::TIMESTAMP,
                    jsonb_build_object(
                        'gateway_id', current_deposit.gateway_id,
                        'pix_copia_e_cola', current_deposit.pix_copia_e_cola,
                        'internal_cpf', current_deposit.internal_cpf,
                        'internal_payer_full_name', current_deposit.internal_payer_full_name,
                        'account_id', current_deposit.account_id,
                        'session_id', current_deposit.session_id
                    )
                );
                
                success_count := success_count + 1;
            ELSE
                error_count := error_count + 1;
                error_details := error_details || jsonb_build_object(
                    'deposit_id', current_deposit.id,
                    'user_id', current_deposit.user_id,
                    'error', 'Affiliate not found for user'
                );
            END IF;
            
        EXCEPTION WHEN OTHERS THEN
            error_count := error_count + 1;
            error_details := error_details || jsonb_build_object(
                'deposit_id', current_deposit.id,
                'error', SQLERRM
            );
        END;
    END LOOP;
    
    -- Atualizar log
    UPDATE data_migration_log 
    SET 
        records_processed = success_count + error_count,
        records_success = success_count,
        records_failed = error_count,
        status = CASE WHEN error_count = 0 THEN 'completed' ELSE 'completed_with_errors' END,
        error_details = error_details
    WHERE source_table = 'transactions_deposits' AND status = 'running';
    
    RETURN QUERY SELECT success_count, error_count, error_details;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNÇÃO: MIGRAÇÃO DE APOSTAS
-- =====================================================

CREATE OR REPLACE FUNCTION migrate_casino_bets()
RETURNS TABLE (
    migrated_count INTEGER,
    error_count INTEGER,
    details JSONB
) AS $$
DECLARE
    success_count INTEGER := 0;
    error_count INTEGER := 0;
    current_bet RECORD;
    affiliate_id UUID;
    error_details JSONB := '[]'::JSONB;
    batch_size INTEGER := 1000;
    processed INTEGER := 0;
BEGIN
    -- Log início da migração
    INSERT INTO data_migration_log (source_table, source_file, status)
    VALUES ('transactions_bets', 'casino_bets.xlsx', 'running');
    
    -- Migrar apostas em lotes para melhor performance
    FOR current_bet IN SELECT * FROM temp_casino_bets LOOP
        BEGIN
            -- Buscar afiliado do usuário
            SELECT a.id INTO affiliate_id
            FROM affiliates a
            JOIN users u ON a.user_id = u.id
            WHERE u.original_id = current_bet.user_id
            AND u.migrated_from = 'upbet_platform';
            
            IF affiliate_id IS NOT NULL THEN
                INSERT INTO transactions (
                    id,
                    external_id,
                    affiliate_id,
                    customer_id,
                    type,
                    amount,
                    currency,
                    status,
                    processed_at,
                    original_id,
                    source_table,
                    created_at,
                    metadata
                ) VALUES (
                    current_bet.id::UUID,
                    current_bet.id,
                    affiliate_id,
                    (SELECT u.id FROM users u WHERE u.original_id = current_bet.user_id),
                    'bet'::transaction_type,
                    current_bet.amount,
                    'BRL',
                    'processed'::transaction_status,
                    current_bet.created_at::TIMESTAMP,
                    current_bet.id,
                    'casino_bets',
                    current_bet.created_at::TIMESTAMP,
                    jsonb_build_object(
                        'game_id', current_bet.reference_game_id,
                        'balance_type', current_bet.balance_type,
                        'win_amount', current_bet.win_amount,
                        'profit', current_bet.profit
                    )
                );
                
                success_count := success_count + 1;
            ELSE
                error_count := error_count + 1;
                error_details := error_details || jsonb_build_object(
                    'bet_id', current_bet.id,
                    'user_id', current_bet.user_id,
                    'error', 'Affiliate not found for user'
                );
            END IF;
            
            processed := processed + 1;
            
            -- Commit em lotes
            IF processed % batch_size = 0 THEN
                COMMIT;
            END IF;
            
        EXCEPTION WHEN OTHERS THEN
            error_count := error_count + 1;
            error_details := error_details || jsonb_build_object(
                'bet_id', current_bet.id,
                'error', SQLERRM
            );
        END;
    END LOOP;
    
    -- Atualizar log
    UPDATE data_migration_log 
    SET 
        records_processed = success_count + error_count,
        records_success = success_count,
        records_failed = error_count,
        status = CASE WHEN error_count = 0 THEN 'completed' ELSE 'completed_with_errors' END,
        error_details = error_details
    WHERE source_table = 'transactions_bets' AND status = 'running';
    
    RETURN QUERY SELECT success_count, error_count, error_details;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNÇÃO: ATUALIZAÇÃO DE ESTATÍSTICAS PÓS-MIGRAÇÃO
-- =====================================================

CREATE OR REPLACE FUNCTION update_affiliate_stats_post_migration()
RETURNS void AS $$
BEGIN
    -- Atualizar contadores de referrals
    UPDATE affiliates 
    SET total_referrals = (
        SELECT COUNT(DISTINCT t.customer_id)
        FROM transactions t
        WHERE t.affiliate_id = affiliates.id
    );
    
    -- Atualizar volume lifetime
    UPDATE affiliates 
    SET lifetime_volume = (
        SELECT COALESCE(SUM(t.amount), 0)
        FROM transactions t
        WHERE t.affiliate_id = affiliates.id
        AND t.status = 'processed'
    );
    
    -- Atualizar volume do mês atual
    UPDATE affiliates 
    SET current_month_volume = (
        SELECT COALESCE(SUM(t.amount), 0)
        FROM transactions t
        WHERE t.affiliate_id = affiliates.id
        AND t.status = 'processed'
        AND t.created_at >= DATE_TRUNC('month', NOW())
    );
    
    -- Atualizar última atividade
    UPDATE affiliates 
    SET last_activity_at = (
        SELECT MAX(t.created_at)
        FROM transactions t
        WHERE t.affiliate_id = affiliates.id
    );
    
    -- Refresh das views materializadas
    REFRESH MATERIALIZED VIEW affiliate_stats;
    REFRESH MATERIALIZED VIEW performance_dashboard;
    
    -- Log da atualização
    INSERT INTO data_audit (table_name, record_id, operation, new_values, source_system)
    VALUES ('affiliates', gen_random_uuid(), 'UPDATE', 
            jsonb_build_object('action', 'post_migration_stats_update', 'timestamp', NOW()), 
            'migration_system');
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNÇÃO: MIGRAÇÃO COMPLETA
-- =====================================================

CREATE OR REPLACE FUNCTION run_complete_migration()
RETURNS TABLE (
    step TEXT,
    success_count INTEGER,
    error_count INTEGER,
    details JSONB
) AS $$
DECLARE
    result RECORD;
BEGIN
    -- Passo 1: Migrar usuários
    SELECT * INTO result FROM migrate_users();
    RETURN QUERY SELECT 'migrate_users'::TEXT, result.migrated_count, result.error_count, result.details;
    
    -- Passo 2: Criar afiliados
    SELECT * INTO result FROM create_affiliates_from_users();
    RETURN QUERY SELECT 'create_affiliates'::TEXT, result.created_count, result.error_count, result.details;
    
    -- Passo 3: Migrar depósitos
    SELECT * INTO result FROM migrate_deposits();
    RETURN QUERY SELECT 'migrate_deposits'::TEXT, result.migrated_count, result.error_count, result.details;
    
    -- Passo 4: Migrar apostas
    SELECT * INTO result FROM migrate_casino_bets();
    RETURN QUERY SELECT 'migrate_bets'::TEXT, result.migrated_count, result.error_count, result.details;
    
    -- Passo 5: Atualizar estatísticas
    PERFORM update_affiliate_stats_post_migration();
    RETURN QUERY SELECT 'update_stats'::TEXT, 1, 0, '{}'::JSONB;
    
    -- Log final
    INSERT INTO data_migration_log (source_table, source_file, status, records_processed)
    VALUES ('complete_migration', 'all_files', 'completed', 
            (SELECT SUM(records_success) FROM data_migration_log WHERE migration_date >= NOW() - INTERVAL '1 hour'));
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNÇÃO: VALIDAÇÃO PÓS-MIGRAÇÃO
-- =====================================================

CREATE OR REPLACE FUNCTION validate_migration()
RETURNS TABLE (
    validation_item TEXT,
    expected_count BIGINT,
    actual_count BIGINT,
    status TEXT
) AS $$
BEGIN
    -- Validar usuários
    RETURN QUERY 
    SELECT 
        'users_migrated'::TEXT,
        (SELECT COUNT(*) FROM temp_users)::BIGINT,
        (SELECT COUNT(*) FROM users WHERE migrated_from = 'upbet_platform')::BIGINT,
        CASE 
            WHEN (SELECT COUNT(*) FROM temp_users) = (SELECT COUNT(*) FROM users WHERE migrated_from = 'upbet_platform')
            THEN 'OK' ELSE 'ERROR' 
        END;
    
    -- Validar afiliados
    RETURN QUERY 
    SELECT 
        'affiliates_created'::TEXT,
        (SELECT COUNT(*) FROM users WHERE migrated_from = 'upbet_platform')::BIGINT,
        (SELECT COUNT(*) FROM affiliates a JOIN users u ON a.user_id = u.id WHERE u.migrated_from = 'upbet_platform')::BIGINT,
        CASE 
            WHEN (SELECT COUNT(*) FROM users WHERE migrated_from = 'upbet_platform') = 
                 (SELECT COUNT(*) FROM affiliates a JOIN users u ON a.user_id = u.id WHERE u.migrated_from = 'upbet_platform')
            THEN 'OK' ELSE 'ERROR' 
        END;
    
    -- Validar depósitos
    RETURN QUERY 
    SELECT 
        'deposits_migrated'::TEXT,
        (SELECT COUNT(*) FROM temp_deposits)::BIGINT,
        (SELECT COUNT(*) FROM transactions WHERE source_table = 'deposits')::BIGINT,
        CASE 
            WHEN (SELECT COUNT(*) FROM temp_deposits) <= (SELECT COUNT(*) FROM transactions WHERE source_table = 'deposits')
            THEN 'OK' ELSE 'CHECK' 
        END;
    
    -- Validar apostas
    RETURN QUERY 
    SELECT 
        'bets_migrated'::TEXT,
        (SELECT COUNT(*) FROM temp_casino_bets)::BIGINT,
        (SELECT COUNT(*) FROM transactions WHERE source_table = 'casino_bets')::BIGINT,
        CASE 
            WHEN (SELECT COUNT(*) FROM temp_casino_bets) <= (SELECT COUNT(*) FROM transactions WHERE source_table = 'casino_bets')
            THEN 'OK' ELSE 'CHECK' 
        END;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- COMENTÁRIOS
-- =====================================================

COMMENT ON FUNCTION migrate_users() IS 'Migra usuários da planilha para a tabela users';
COMMENT ON FUNCTION create_affiliates_from_users() IS 'Cria registros de afiliados para usuários migrados';
COMMENT ON FUNCTION migrate_deposits() IS 'Migra depósitos para a tabela transactions';
COMMENT ON FUNCTION migrate_casino_bets() IS 'Migra apostas de casino para a tabela transactions';
COMMENT ON FUNCTION run_complete_migration() IS 'Executa migração completa de todos os dados';
COMMENT ON FUNCTION validate_migration() IS 'Valida se a migração foi executada corretamente';

