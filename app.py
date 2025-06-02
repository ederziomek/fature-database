"""
Fature Database - API de Exemplo
Aplicação Flask demonstrando uso do banco de dados
"""

import os
import json
from datetime import datetime
from flask import Flask, jsonify, request
from flask_cors import CORS
import psycopg2
from psycopg2.extras import RealDictCursor
import redis
from scripts.redis_cache import CacheManager, CacheConfig

# Configuração da aplicação
app = Flask(__name__)
CORS(app)

# Configuração do banco de dados
DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://fature_user:fature_password_2025@localhost:5432/fature_db')
REDIS_URL = os.getenv('REDIS_URL', 'redis://localhost:6379/0')

# Inicializar cache
cache_config = CacheConfig(
    host=os.getenv('REDIS_HOST', 'localhost'),
    port=int(os.getenv('REDIS_PORT', 6379)),
    password=os.getenv('REDIS_PASSWORD')
)
cache_manager = CacheManager(cache_config)

def get_db_connection():
    """Cria conexão com PostgreSQL"""
    return psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)

@app.route('/health')
def health_check():
    """Endpoint de health check"""
    try:
        # Testar PostgreSQL
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute('SELECT 1')
        
        # Testar Redis
        redis_health = cache_manager.health_check()
        
        return jsonify({
            'status': 'healthy',
            'timestamp': datetime.utcnow().isoformat(),
            'services': {
                'postgresql': True,
                'redis': all(redis_health.values())
            }
        })
    except Exception as e:
        return jsonify({
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }), 500

@app.route('/api/affiliates')
def get_affiliates():
    """Lista afiliados com paginação"""
    page = int(request.args.get('page', 1))
    limit = min(int(request.args.get('limit', 20)), 100)
    offset = (page - 1) * limit
    
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                # Buscar afiliados
                cur.execute("""
                    SELECT 
                        a.id,
                        a.referral_code,
                        u.name,
                        u.email,
                        a.category,
                        a.level,
                        a.status,
                        a.total_referrals,
                        a.lifetime_volume,
                        a.lifetime_commissions,
                        a.joined_at
                    FROM affiliates a
                    JOIN users u ON a.user_id = u.id
                    WHERE u.deleted_at IS NULL
                    ORDER BY a.lifetime_volume DESC
                    LIMIT %s OFFSET %s
                """, (limit, offset))
                
                affiliates = cur.fetchall()
                
                # Contar total
                cur.execute("""
                    SELECT COUNT(*)
                    FROM affiliates a
                    JOIN users u ON a.user_id = u.id
                    WHERE u.deleted_at IS NULL
                """)
                total = cur.fetchone()['count']
        
        return jsonify({
            'data': [dict(affiliate) for affiliate in affiliates],
            'pagination': {
                'page': page,
                'limit': limit,
                'total': total,
                'pages': (total + limit - 1) // limit
            }
        })
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/affiliates/<affiliate_id>/stats')
def get_affiliate_stats(affiliate_id):
    """Busca estatísticas de um afiliado (com cache)"""
    try:
        # Tentar buscar do cache primeiro
        stats = cache_manager.affiliate_stats.get_affiliate_stats(affiliate_id)
        
        if not stats:
            # Buscar do banco de dados
            with get_db_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        SELECT * FROM affiliate_stats
                        WHERE id = %s
                    """, (affiliate_id,))
                    
                    result = cur.fetchone()
                    if result:
                        stats = dict(result)
                        # Armazenar no cache
                        cache_manager.affiliate_stats.set_affiliate_stats(affiliate_id, stats)
        
        if not stats:
            return jsonify({'error': 'Affiliate not found'}), 404
        
        return jsonify({
            'data': stats,
            'cached': stats is not None
        })
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/dashboard')
def get_dashboard():
    """Dashboard principal com métricas gerais"""
    try:
        # Tentar buscar do cache
        dashboard_data = cache_manager.reports.get_dashboard_data()
        
        if not dashboard_data:
            # Buscar do banco
            with get_db_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        SELECT * FROM performance_dashboard
                        WHERE period = 'current_month'
                    """)
                    current_month = cur.fetchone()
                    
                    cur.execute("""
                        SELECT * FROM performance_dashboard
                        WHERE period = 'previous_month'
                    """)
                    previous_month = cur.fetchone()
                    
                    dashboard_data = {
                        'current_month': dict(current_month) if current_month else {},
                        'previous_month': dict(previous_month) if previous_month else {},
                        'generated_at': datetime.utcnow().isoformat()
                    }
                    
                    # Armazenar no cache
                    cache_manager.reports.set_dashboard_data(dashboard_data)
        
        return jsonify({
            'data': dashboard_data,
            'cached': dashboard_data is not None
        })
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/rankings')
def get_rankings():
    """Lista rankings ativos"""
    try:
        # Tentar buscar do cache
        rankings = cache_manager.rankings.get_active_rankings()
        
        if not rankings:
            # Buscar do banco
            with get_db_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        SELECT 
                            id,
                            name,
                            description,
                            type,
                            start_date,
                            end_date,
                            current_participants,
                            max_participants
                        FROM rankings
                        WHERE status = 'active'
                        AND start_date <= NOW()
                        AND end_date >= NOW()
                        ORDER BY start_date DESC
                    """)
                    
                    rankings = [dict(row) for row in cur.fetchall()]
                    
                    # Armazenar no cache
                    cache_manager.rankings.set_active_rankings(rankings)
        
        return jsonify({
            'data': rankings,
            'cached': rankings is not None
        })
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/cache/stats')
def get_cache_stats():
    """Estatísticas do cache Redis"""
    try:
        stats = cache_manager.get_cache_stats()
        return jsonify({
            'data': stats,
            'timestamp': datetime.utcnow().isoformat()
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/cache/clear', methods=['POST'])
def clear_cache():
    """Limpa cache (usar com cuidado)"""
    try:
        cache_type = request.json.get('type', 'all')
        
        if cache_type == 'all':
            cache_manager.clear_all_cache()
        elif cache_type == 'affiliates':
            # Implementar limpeza específica
            pass
        
        return jsonify({
            'message': f'Cache {cache_type} cleared successfully',
            'timestamp': datetime.utcnow().isoformat()
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/migration/status')
def get_migration_status():
    """Status da migração de dados"""
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT 
                        source_table,
                        source_file,
                        records_processed,
                        records_success,
                        records_failed,
                        status,
                        migration_date
                    FROM data_migration_log
                    ORDER BY migration_date DESC
                    LIMIT 10
                """)
                
                migrations = [dict(row) for row in cur.fetchall()]
        
        return jsonify({
            'data': migrations,
            'timestamp': datetime.utcnow().isoformat()
        })
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Endpoint not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    debug = os.getenv('FLASK_DEBUG', '0') == '1'
    
    app.run(
        host='0.0.0.0',
        port=port,
        debug=debug
    )

