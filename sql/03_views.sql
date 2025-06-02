-- =====================================================
-- FATURE DATABASE - VIEWS MATERIALIZADAS
-- Views para relatórios e consultas frequentes
-- =====================================================

-- =====================================================
-- VIEW: ESTATÍSTICAS DE AFILIADOS
-- =====================================================

CREATE MATERIALIZED VIEW affiliate_stats AS
SELECT 
    a.id,
    a.user_id,
    a.referral_code,
    a.category,
    a.level,
    a.status,
    u.name as affiliate_name,
    u.email as affiliate_email,
    
    -- Estatísticas de referrals
    a.total_referrals,
    a.active_referrals,
    
    -- Estatísticas de transações
    COUNT(DISTINCT t.customer_id) as unique_customers,
    COUNT(t.id) as total_transactions,
    COALESCE(SUM(CASE WHEN t.type = 'deposit' THEN t.amount ELSE 0 END), 0) as total_deposits,
    COALESCE(SUM(CASE WHEN t.type = 'bet' THEN t.amount ELSE 0 END), 0) as total_bets,
    COALESCE(SUM(t.amount), 0) as total_volume,
    
    -- Estatísticas de comissões
    COALESCE(SUM(c.final_amount), 0) as total_commissions_earned,
    COALESCE(SUM(CASE WHEN c.status = 'paid' THEN c.final_amount ELSE 0 END), 0) as total_commissions_paid,
    COALESCE(SUM(CASE WHEN c.status IN ('calculated', 'approved') THEN c.final_amount ELSE 0 END), 0) as pending_commissions,
    
    -- Estatísticas temporais
    a.lifetime_volume,
    a.lifetime_commissions,
    a.current_month_volume,
    a.current_month_commissions,
    a.last_activity_at,
    
    -- Datas importantes
    a.joined_at,
    MAX(t.created_at) as last_transaction_date,
    MAX(c.created_at) as last_commission_date,
    
    -- Métricas calculadas
    CASE 
        WHEN COUNT(t.id) > 0 THEN COALESCE(SUM(t.amount), 0) / COUNT(t.id)
        ELSE 0 
    END as avg_transaction_value,
    
    CASE 
        WHEN a.total_referrals > 0 THEN COUNT(DISTINCT t.customer_id)::DECIMAL / a.total_referrals * 100
        ELSE 0 
    END as conversion_rate,
    
    -- Status calculado
    CASE 
        WHEN a.last_activity_at IS NULL THEN 'never_active'
        WHEN a.last_activity_at < NOW() - INTERVAL '30 days' THEN 'inactive'
        WHEN a.last_activity_at < NOW() - INTERVAL '7 days' THEN 'low_activity'
        ELSE 'active'
    END as activity_status

FROM affiliates a
JOIN users u ON a.user_id = u.id
LEFT JOIN transactions t ON a.id = t.affiliate_id AND t.status = 'processed'
LEFT JOIN commissions c ON a.id = c.affiliate_id
WHERE u.deleted_at IS NULL
GROUP BY 
    a.id, a.user_id, a.referral_code, a.category, a.level, a.status,
    u.name, u.email, a.total_referrals, a.active_referrals,
    a.lifetime_volume, a.lifetime_commissions, a.current_month_volume,
    a.current_month_commissions, a.last_activity_at, a.joined_at;

-- Índices para a view materializada
CREATE UNIQUE INDEX idx_affiliate_stats_id ON affiliate_stats(id);
CREATE INDEX idx_affiliate_stats_category ON affiliate_stats(category);
CREATE INDEX idx_affiliate_stats_volume ON affiliate_stats(total_volume DESC);
CREATE INDEX idx_affiliate_stats_commissions ON affiliate_stats(total_commissions_earned DESC);
CREATE INDEX idx_affiliate_stats_activity ON affiliate_stats(activity_status);

-- =====================================================
-- VIEW: HIERARQUIA DE AFILIADOS COM ESTATÍSTICAS
-- =====================================================

CREATE MATERIALIZED VIEW affiliate_hierarchy_stats AS
WITH RECURSIVE hierarchy_tree AS (
    -- Nós raiz (sem parent)
    SELECT 
        a.id,
        a.user_id,
        a.referral_code,
        a.parent_id,
        u.name,
        0 as depth,
        ARRAY[a.id] as path,
        a.id::TEXT as path_string
    FROM affiliates a
    JOIN users u ON a.user_id = u.id
    WHERE a.parent_id IS NULL AND a.status = 'active'
    
    UNION ALL
    
    -- Nós filhos
    SELECT 
        a.id,
        a.user_id,
        a.referral_code,
        a.parent_id,
        u.name,
        ht.depth + 1,
        ht.path || a.id,
        ht.path_string || ' -> ' || a.id::TEXT
    FROM affiliates a
    JOIN users u ON a.user_id = u.id
    JOIN hierarchy_tree ht ON a.parent_id = ht.id
    WHERE a.status = 'active' AND ht.depth < 10 -- Limitar profundidade
)
SELECT 
    ht.*,
    
    -- Estatísticas diretas
    COALESCE(ast.total_volume, 0) as direct_volume,
    COALESCE(ast.total_commissions_earned, 0) as direct_commissions,
    COALESCE(ast.total_referrals, 0) as direct_referrals,
    
    -- Estatísticas da rede (incluindo descendentes)
    (
        SELECT COUNT(*)
        FROM affiliate_hierarchy ah
        WHERE ah.ancestor_id = ht.id
    ) as total_network_size,
    
    (
        SELECT COALESCE(SUM(ast2.total_volume), 0)
        FROM affiliate_hierarchy ah
        JOIN affiliate_stats ast2 ON ah.descendant_id = ast2.id
        WHERE ah.ancestor_id = ht.id
    ) as network_volume,
    
    (
        SELECT COALESCE(SUM(ast2.total_commissions_earned), 0)
        FROM affiliate_hierarchy ah
        JOIN affiliate_stats ast2 ON ah.descendant_id = ast2.id
        WHERE ah.ancestor_id = ht.id
    ) as network_commissions

FROM hierarchy_tree ht
LEFT JOIN affiliate_stats ast ON ht.id = ast.id;

-- Índices para hierarquia
CREATE UNIQUE INDEX idx_affiliate_hierarchy_stats_id ON affiliate_hierarchy_stats(id);
CREATE INDEX idx_affiliate_hierarchy_stats_parent ON affiliate_hierarchy_stats(parent_id);
CREATE INDEX idx_affiliate_hierarchy_stats_depth ON affiliate_hierarchy_stats(depth);
CREATE INDEX idx_affiliate_hierarchy_stats_network_volume ON affiliate_hierarchy_stats(network_volume DESC);

-- =====================================================
-- VIEW: RELATÓRIO MENSAL DE COMISSÕES
-- =====================================================

CREATE MATERIALIZED VIEW monthly_commission_report AS
SELECT 
    DATE_TRUNC('month', c.created_at) as month_year,
    c.affiliate_id,
    a.referral_code,
    u.name as affiliate_name,
    a.category,
    
    -- Totais por status
    COUNT(*) as total_commissions,
    COUNT(CASE WHEN c.status = 'calculated' THEN 1 END) as calculated_count,
    COUNT(CASE WHEN c.status = 'approved' THEN 1 END) as approved_count,
    COUNT(CASE WHEN c.status = 'paid' THEN 1 END) as paid_count,
    COUNT(CASE WHEN c.status = 'cancelled' THEN 1 END) as cancelled_count,
    
    -- Valores por status
    COALESCE(SUM(c.final_amount), 0) as total_amount,
    COALESCE(SUM(CASE WHEN c.status = 'calculated' THEN c.final_amount ELSE 0 END), 0) as calculated_amount,
    COALESCE(SUM(CASE WHEN c.status = 'approved' THEN c.final_amount ELSE 0 END), 0) as approved_amount,
    COALESCE(SUM(CASE WHEN c.status = 'paid' THEN c.final_amount ELSE 0 END), 0) as paid_amount,
    COALESCE(SUM(CASE WHEN c.status = 'cancelled' THEN c.final_amount ELSE 0 END), 0) as cancelled_amount,
    
    -- Comissões por nível
    COALESCE(SUM(CASE WHEN c.level = 1 THEN c.final_amount ELSE 0 END), 0) as level_1_amount,
    COALESCE(SUM(CASE WHEN c.level = 2 THEN c.final_amount ELSE 0 END), 0) as level_2_amount,
    COALESCE(SUM(CASE WHEN c.level = 3 THEN c.final_amount ELSE 0 END), 0) as level_3_amount,
    COALESCE(SUM(CASE WHEN c.level >= 4 THEN c.final_amount ELSE 0 END), 0) as level_4_plus_amount,
    
    -- Métricas
    COALESCE(AVG(c.final_amount), 0) as avg_commission,
    COALESCE(AVG(c.percentage), 0) as avg_percentage,
    
    -- Datas
    MIN(c.created_at) as first_commission_date,
    MAX(c.created_at) as last_commission_date

FROM commissions c
JOIN affiliates a ON c.affiliate_id = a.id
JOIN users u ON a.user_id = u.id
WHERE c.created_at >= DATE_TRUNC('month', NOW() - INTERVAL '12 months')
GROUP BY 
    DATE_TRUNC('month', c.created_at),
    c.affiliate_id,
    a.referral_code,
    u.name,
    a.category;

-- Índices para relatório mensal
CREATE UNIQUE INDEX idx_monthly_commission_report_unique 
ON monthly_commission_report(month_year, affiliate_id);
CREATE INDEX idx_monthly_commission_report_month ON monthly_commission_report(month_year DESC);
CREATE INDEX idx_monthly_commission_report_affiliate ON monthly_commission_report(affiliate_id);
CREATE INDEX idx_monthly_commission_report_amount ON monthly_commission_report(total_amount DESC);

-- =====================================================
-- VIEW: DASHBOARD DE PERFORMANCE
-- =====================================================

CREATE MATERIALIZED VIEW performance_dashboard AS
SELECT 
    -- Período
    'current_month' as period,
    DATE_TRUNC('month', NOW()) as period_start,
    NOW() as period_end,
    
    -- Métricas gerais
    COUNT(DISTINCT a.id) as total_affiliates,
    COUNT(DISTINCT CASE WHEN a.status = 'active' THEN a.id END) as active_affiliates,
    COUNT(DISTINCT t.customer_id) as total_customers,
    COUNT(t.id) as total_transactions,
    COALESCE(SUM(t.amount), 0) as total_volume,
    
    -- Métricas de comissões
    COUNT(c.id) as total_commissions,
    COALESCE(SUM(c.final_amount), 0) as total_commission_amount,
    COALESCE(SUM(CASE WHEN c.status = 'paid' THEN c.final_amount ELSE 0 END), 0) as paid_commissions,
    COALESCE(SUM(CASE WHEN c.status IN ('calculated', 'approved') THEN c.final_amount ELSE 0 END), 0) as pending_commissions,
    
    -- Métricas por tipo de transação
    COALESCE(SUM(CASE WHEN t.type = 'deposit' THEN t.amount ELSE 0 END), 0) as total_deposits,
    COALESCE(SUM(CASE WHEN t.type = 'bet' THEN t.amount ELSE 0 END), 0) as total_bets,
    COUNT(CASE WHEN t.type = 'deposit' THEN 1 END) as deposit_count,
    COUNT(CASE WHEN t.type = 'bet' THEN 1 END) as bet_count,
    
    -- Métricas calculadas
    CASE 
        WHEN COUNT(t.id) > 0 THEN COALESCE(SUM(t.amount), 0) / COUNT(t.id)
        ELSE 0 
    END as avg_transaction_value,
    
    CASE 
        WHEN COUNT(DISTINCT a.id) > 0 THEN COALESCE(SUM(t.amount), 0) / COUNT(DISTINCT a.id)
        ELSE 0 
    END as avg_volume_per_affiliate,
    
    CASE 
        WHEN COALESCE(SUM(t.amount), 0) > 0 THEN COALESCE(SUM(c.final_amount), 0) / COALESCE(SUM(t.amount), 0) * 100
        ELSE 0 
    END as commission_rate_percentage

FROM affiliates a
LEFT JOIN transactions t ON a.id = t.affiliate_id 
    AND t.status = 'processed' 
    AND t.created_at >= DATE_TRUNC('month', NOW())
LEFT JOIN commissions c ON a.id = c.affiliate_id 
    AND c.created_at >= DATE_TRUNC('month', NOW())

UNION ALL

-- Dados do mês anterior para comparação
SELECT 
    'previous_month' as period,
    DATE_TRUNC('month', NOW() - INTERVAL '1 month') as period_start,
    DATE_TRUNC('month', NOW()) as period_end,
    
    COUNT(DISTINCT a.id) as total_affiliates,
    COUNT(DISTINCT CASE WHEN a.status = 'active' THEN a.id END) as active_affiliates,
    COUNT(DISTINCT t.customer_id) as total_customers,
    COUNT(t.id) as total_transactions,
    COALESCE(SUM(t.amount), 0) as total_volume,
    
    COUNT(c.id) as total_commissions,
    COALESCE(SUM(c.final_amount), 0) as total_commission_amount,
    COALESCE(SUM(CASE WHEN c.status = 'paid' THEN c.final_amount ELSE 0 END), 0) as paid_commissions,
    COALESCE(SUM(CASE WHEN c.status IN ('calculated', 'approved') THEN c.final_amount ELSE 0 END), 0) as pending_commissions,
    
    COALESCE(SUM(CASE WHEN t.type = 'deposit' THEN t.amount ELSE 0 END), 0) as total_deposits,
    COALESCE(SUM(CASE WHEN t.type = 'bet' THEN t.amount ELSE 0 END), 0) as total_bets,
    COUNT(CASE WHEN t.type = 'deposit' THEN 1 END) as deposit_count,
    COUNT(CASE WHEN t.type = 'bet' THEN 1 END) as bet_count,
    
    CASE 
        WHEN COUNT(t.id) > 0 THEN COALESCE(SUM(t.amount), 0) / COUNT(t.id)
        ELSE 0 
    END as avg_transaction_value,
    
    CASE 
        WHEN COUNT(DISTINCT a.id) > 0 THEN COALESCE(SUM(t.amount), 0) / COUNT(DISTINCT a.id)
        ELSE 0 
    END as avg_volume_per_affiliate,
    
    CASE 
        WHEN COALESCE(SUM(t.amount), 0) > 0 THEN COALESCE(SUM(c.final_amount), 0) / COALESCE(SUM(t.amount), 0) * 100
        ELSE 0 
    END as commission_rate_percentage

FROM affiliates a
LEFT JOIN transactions t ON a.id = t.affiliate_id 
    AND t.status = 'processed' 
    AND t.created_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
    AND t.created_at < DATE_TRUNC('month', NOW())
LEFT JOIN commissions c ON a.id = c.affiliate_id 
    AND c.created_at >= DATE_TRUNC('month', NOW() - INTERVAL '1 month')
    AND c.created_at < DATE_TRUNC('month', NOW());

-- Índice para dashboard
CREATE UNIQUE INDEX idx_performance_dashboard_period ON performance_dashboard(period);

-- =====================================================
-- VIEW: TOP PERFORMERS
-- =====================================================

CREATE MATERIALIZED VIEW top_performers AS
SELECT 
    'volume' as metric_type,
    a.id as affiliate_id,
    a.referral_code,
    u.name as affiliate_name,
    a.category,
    ast.total_volume as metric_value,
    ast.total_transactions,
    ast.total_commissions_earned,
    ROW_NUMBER() OVER (ORDER BY ast.total_volume DESC) as ranking
FROM affiliates a
JOIN users u ON a.user_id = u.id
JOIN affiliate_stats ast ON a.id = ast.id
WHERE a.status = 'active' AND ast.total_volume > 0
ORDER BY ast.total_volume DESC
LIMIT 100

UNION ALL

SELECT 
    'commissions' as metric_type,
    a.id as affiliate_id,
    a.referral_code,
    u.name as affiliate_name,
    a.category,
    ast.total_commissions_earned as metric_value,
    ast.total_transactions,
    ast.total_commissions_earned,
    ROW_NUMBER() OVER (ORDER BY ast.total_commissions_earned DESC) as ranking
FROM affiliates a
JOIN users u ON a.user_id = u.id
JOIN affiliate_stats ast ON a.id = ast.id
WHERE a.status = 'active' AND ast.total_commissions_earned > 0
ORDER BY ast.total_commissions_earned DESC
LIMIT 100

UNION ALL

SELECT 
    'referrals' as metric_type,
    a.id as affiliate_id,
    a.referral_code,
    u.name as affiliate_name,
    a.category,
    a.total_referrals::DECIMAL as metric_value,
    ast.total_transactions,
    ast.total_commissions_earned,
    ROW_NUMBER() OVER (ORDER BY a.total_referrals DESC) as ranking
FROM affiliates a
JOIN users u ON a.user_id = u.id
JOIN affiliate_stats ast ON a.id = ast.id
WHERE a.status = 'active' AND a.total_referrals > 0
ORDER BY a.total_referrals DESC
LIMIT 100;

-- Índices para top performers
CREATE INDEX idx_top_performers_metric ON top_performers(metric_type);
CREATE INDEX idx_top_performers_ranking ON top_performers(metric_type, ranking);
CREATE INDEX idx_top_performers_affiliate ON top_performers(affiliate_id);

-- =====================================================
-- FUNÇÕES PARA REFRESH AUTOMÁTICO
-- =====================================================

-- Função para refresh de todas as views materializadas
CREATE OR REPLACE FUNCTION refresh_all_materialized_views()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY affiliate_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY affiliate_hierarchy_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY monthly_commission_report;
    REFRESH MATERIALIZED VIEW CONCURRENTLY performance_dashboard;
    REFRESH MATERIALIZED VIEW CONCURRENTLY top_performers;
    
    -- Log do refresh
    INSERT INTO data_audit (table_name, record_id, operation, new_values, source_system)
    VALUES ('materialized_views', gen_random_uuid(), 'REFRESH', 
            jsonb_build_object('refreshed_at', NOW(), 'views', 'all'), 'system');
END;
$$ LANGUAGE plpgsql;

-- Função para refresh rápido (apenas views críticas)
CREATE OR REPLACE FUNCTION refresh_critical_views()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY affiliate_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY performance_dashboard;
END;
$$ LANGUAGE plpgsql;

-- Agendar refresh automático das views
-- Refresh completo a cada 6 horas
SELECT cron.schedule('refresh-all-views', '0 */6 * * *', 'SELECT refresh_all_materialized_views();');

-- Refresh crítico a cada hora
SELECT cron.schedule('refresh-critical-views', '0 * * * *', 'SELECT refresh_critical_views();');

-- =====================================================
-- COMENTÁRIOS NAS VIEWS
-- =====================================================

COMMENT ON MATERIALIZED VIEW affiliate_stats IS 'Estatísticas completas de cada afiliado';
COMMENT ON MATERIALIZED VIEW affiliate_hierarchy_stats IS 'Hierarquia MLM com estatísticas de rede';
COMMENT ON MATERIALIZED VIEW monthly_commission_report IS 'Relatório mensal de comissões por afiliado';
COMMENT ON MATERIALIZED VIEW performance_dashboard IS 'Dashboard de performance com métricas principais';
COMMENT ON MATERIALIZED VIEW top_performers IS 'Ranking dos melhores afiliados por diferentes métricas';

