"""
FATURE DATABASE - ESTRATÉGIAS DE CACHE REDIS
Sistema de cache para otimização de performance
"""

import redis
import json
import hashlib
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Union
from dataclasses import dataclass
from enum import Enum

class CacheDatabase(Enum):
    """Databases Redis específicas para diferentes tipos de cache"""
    GENERAL = 0          # Cache geral
    SESSIONS = 1         # Sessões de usuário
    AFFILIATE_STATS = 2  # Estatísticas de afiliados
    RANKINGS = 3         # Rankings e gamificação
    COMMISSIONS = 4      # Cache de comissões
    REPORTS = 5          # Cache de relatórios

class CacheTTL(Enum):
    """Tempos de vida padrão para diferentes tipos de cache"""
    VERY_SHORT = 300     # 5 minutos
    SHORT = 900          # 15 minutos
    MEDIUM = 1800        # 30 minutos
    LONG = 3600          # 1 hora
    VERY_LONG = 86400    # 24 horas
    SESSION = 86400      # 24 horas (sessões)
    DAILY = 86400        # 24 horas (dados diários)

@dataclass
class CacheConfig:
    """Configuração de cache"""
    host: str = 'localhost'
    port: int = 6379
    password: Optional[str] = None
    decode_responses: bool = True
    socket_timeout: int = 5
    socket_connect_timeout: int = 5
    retry_on_timeout: bool = True
    health_check_interval: int = 30

class FatureRedisCache:
    """Classe principal para gerenciamento de cache Redis do sistema Fature"""
    
    def __init__(self, config: CacheConfig = None):
        self.config = config or CacheConfig()
        self.connections = {}
        self._initialize_connections()
    
    def _initialize_connections(self):
        """Inicializa conexões para cada database"""
        for db in CacheDatabase:
            self.connections[db] = redis.Redis(
                host=self.config.host,
                port=self.config.port,
                db=db.value,
                password=self.config.password,
                decode_responses=self.config.decode_responses,
                socket_timeout=self.config.socket_timeout,
                socket_connect_timeout=self.config.socket_connect_timeout,
                retry_on_timeout=self.config.retry_on_timeout,
                health_check_interval=self.config.health_check_interval
            )
    
    def get_connection(self, database: CacheDatabase) -> redis.Redis:
        """Retorna conexão para database específico"""
        return self.connections[database]
    
    def _generate_key(self, prefix: str, *args) -> str:
        """Gera chave padronizada para cache"""
        key_parts = [prefix] + [str(arg) for arg in args]
        return ':'.join(key_parts)
    
    def _serialize_data(self, data: Any) -> str:
        """Serializa dados para armazenamento"""
        if isinstance(data, (dict, list)):
            return json.dumps(data, default=str)
        return str(data)
    
    def _deserialize_data(self, data: str) -> Any:
        """Deserializa dados do cache"""
        try:
            return json.loads(data)
        except (json.JSONDecodeError, TypeError):
            return data

class AffiliateStatsCache(FatureRedisCache):
    """Cache específico para estatísticas de afiliados"""
    
    def __init__(self, config: CacheConfig = None):
        super().__init__(config)
        self.db = self.get_connection(CacheDatabase.AFFILIATE_STATS)
    
    def get_affiliate_stats(self, affiliate_id: str) -> Optional[Dict]:
        """Busca estatísticas de afiliado no cache"""
        key = self._generate_key('affiliate:stats', affiliate_id)
        data = self.db.get(key)
        return self._deserialize_data(data) if data else None
    
    def set_affiliate_stats(self, affiliate_id: str, stats: Dict, ttl: int = CacheTTL.MEDIUM.value):
        """Armazena estatísticas de afiliado no cache"""
        key = self._generate_key('affiliate:stats', affiliate_id)
        data = self._serialize_data(stats)
        self.db.setex(key, ttl, data)
    
    def get_affiliate_hierarchy(self, affiliate_id: str) -> Optional[List]:
        """Busca hierarquia de afiliado no cache"""
        key = self._generate_key('affiliate:hierarchy', affiliate_id)
        data = self.db.get(key)
        return self._deserialize_data(data) if data else None
    
    def set_affiliate_hierarchy(self, affiliate_id: str, hierarchy: List, ttl: int = CacheTTL.VERY_LONG.value):
        """Armazena hierarquia de afiliado no cache"""
        key = self._generate_key('affiliate:hierarchy', affiliate_id)
        data = self._serialize_data(hierarchy)
        self.db.setex(key, ttl, data)
    
    def get_monthly_stats(self, affiliate_id: str, year: int, month: int) -> Optional[Dict]:
        """Busca estatísticas mensais de afiliado"""
        key = self._generate_key('affiliate:monthly', affiliate_id, year, month)
        data = self.db.get(key)
        return self._deserialize_data(data) if data else None
    
    def set_monthly_stats(self, affiliate_id: str, year: int, month: int, stats: Dict, ttl: int = CacheTTL.LONG.value):
        """Armazena estatísticas mensais de afiliado"""
        key = self._generate_key('affiliate:monthly', affiliate_id, year, month)
        data = self._serialize_data(stats)
        self.db.setex(key, ttl, data)
    
    def invalidate_affiliate_cache(self, affiliate_id: str):
        """Invalida todo o cache de um afiliado"""
        patterns = [
            f'affiliate:stats:{affiliate_id}',
            f'affiliate:hierarchy:{affiliate_id}',
            f'affiliate:monthly:{affiliate_id}:*'
        ]
        
        for pattern in patterns:
            keys = self.db.keys(pattern)
            if keys:
                self.db.delete(*keys)

class CommissionCache(FatureRedisCache):
    """Cache específico para cálculos de comissão"""
    
    def __init__(self, config: CacheConfig = None):
        super().__init__(config)
        self.db = self.get_connection(CacheDatabase.COMMISSIONS)
    
    def get_commission_calculation(self, transaction_id: str) -> Optional[Dict]:
        """Busca cálculo de comissão no cache"""
        key = self._generate_key('commission:calc', transaction_id)
        data = self.db.get(key)
        return self._deserialize_data(data) if data else None
    
    def set_commission_calculation(self, transaction_id: str, calculation: Dict, ttl: int = CacheTTL.LONG.value):
        """Armazena cálculo de comissão no cache"""
        key = self._generate_key('commission:calc', transaction_id)
        data = self._serialize_data(calculation)
        self.db.setex(key, ttl, data)
    
    def get_pending_commissions(self, affiliate_id: str) -> Optional[List]:
        """Busca comissões pendentes de um afiliado"""
        key = self._generate_key('commission:pending', affiliate_id)
        data = self.db.get(key)
        return self._deserialize_data(data) if data else None
    
    def set_pending_commissions(self, affiliate_id: str, commissions: List, ttl: int = CacheTTL.SHORT.value):
        """Armazena comissões pendentes de um afiliado"""
        key = self._generate_key('commission:pending', affiliate_id)
        data = self._serialize_data(commissions)
        self.db.setex(key, ttl, data)

class RankingCache(FatureRedisCache):
    """Cache específico para rankings e gamificação"""
    
    def __init__(self, config: CacheConfig = None):
        super().__init__(config)
        self.db = self.get_connection(CacheDatabase.RANKINGS)
    
    def get_active_rankings(self) -> Optional[List]:
        """Busca rankings ativos"""
        key = 'ranking:active'
        data = self.db.get(key)
        return self._deserialize_data(data) if data else None
    
    def set_active_rankings(self, rankings: List, ttl: int = CacheTTL.SHORT.value):
        """Armazena rankings ativos"""
        key = 'ranking:active'
        data = self._serialize_data(rankings)
        self.db.setex(key, ttl, data)
    
    def get_ranking_participants(self, ranking_id: str) -> Optional[List]:
        """Busca participantes de um ranking"""
        key = self._generate_key('ranking:participants', ranking_id)
        data = self.db.get(key)
        return self._deserialize_data(data) if data else None
    
    def set_ranking_participants(self, ranking_id: str, participants: List, ttl: int = CacheTTL.SHORT.value):
        """Armazena participantes de um ranking"""
        key = self._generate_key('ranking:participants', ranking_id)
        data = self._serialize_data(participants)
        self.db.setex(key, ttl, data)
    
    def get_user_daily_sequence(self, user_id: str) -> Optional[Dict]:
        """Busca sequência diária de um usuário"""
        key = self._generate_key('daily:sequence', user_id)
        data = self.db.get(key)
        return self._deserialize_data(data) if data else None
    
    def set_user_daily_sequence(self, user_id: str, sequence: Dict):
        """Armazena sequência diária de um usuário (expira à meia-noite)"""
        key = self._generate_key('daily:sequence', user_id)
        data = self._serialize_data(sequence)
        
        # Calcular TTL até meia-noite
        now = datetime.now()
        midnight = (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
        ttl = int((midnight - now).total_seconds())
        
        self.db.setex(key, ttl, data)

class SessionCache(FatureRedisCache):
    """Cache específico para sessões de usuário"""
    
    def __init__(self, config: CacheConfig = None):
        super().__init__(config)
        self.db = self.get_connection(CacheDatabase.SESSIONS)
    
    def get_user_session(self, session_token: str) -> Optional[Dict]:
        """Busca sessão de usuário"""
        key = self._generate_key('session', session_token)
        data = self.db.get(key)
        return self._deserialize_data(data) if data else None
    
    def set_user_session(self, session_token: str, session_data: Dict, ttl: int = CacheTTL.SESSION.value):
        """Armazena sessão de usuário"""
        key = self._generate_key('session', session_token)
        data = self._serialize_data(session_data)
        self.db.setex(key, ttl, data)
    
    def delete_user_session(self, session_token: str):
        """Remove sessão de usuário"""
        key = self._generate_key('session', session_token)
        self.db.delete(key)
    
    def get_user_active_sessions(self, user_id: str) -> Optional[List]:
        """Busca sessões ativas de um usuário"""
        key = self._generate_key('user:sessions', user_id)
        data = self.db.get(key)
        return self._deserialize_data(data) if data else None
    
    def add_user_session(self, user_id: str, session_token: str):
        """Adiciona sessão à lista de sessões ativas do usuário"""
        key = self._generate_key('user:sessions', user_id)
        self.db.sadd(key, session_token)
        self.db.expire(key, CacheTTL.SESSION.value)
    
    def remove_user_session(self, user_id: str, session_token: str):
        """Remove sessão da lista de sessões ativas do usuário"""
        key = self._generate_key('user:sessions', user_id)
        self.db.srem(key, session_token)

class ReportCache(FatureRedisCache):
    """Cache específico para relatórios"""
    
    def __init__(self, config: CacheConfig = None):
        super().__init__(config)
        self.db = self.get_connection(CacheDatabase.REPORTS)
    
    def get_dashboard_data(self) -> Optional[Dict]:
        """Busca dados do dashboard"""
        key = 'dashboard:main'
        data = self.db.get(key)
        return self._deserialize_data(data) if data else None
    
    def set_dashboard_data(self, dashboard_data: Dict, ttl: int = CacheTTL.SHORT.value):
        """Armazena dados do dashboard"""
        key = 'dashboard:main'
        data = self._serialize_data(dashboard_data)
        self.db.setex(key, ttl, data)
    
    def get_monthly_report(self, year: int, month: int) -> Optional[Dict]:
        """Busca relatório mensal"""
        key = self._generate_key('report:monthly', year, month)
        data = self.db.get(key)
        return self._deserialize_data(data) if data else None
    
    def set_monthly_report(self, year: int, month: int, report_data: Dict, ttl: int = CacheTTL.VERY_LONG.value):
        """Armazena relatório mensal"""
        key = self._generate_key('report:monthly', year, month)
        data = self._serialize_data(report_data)
        self.db.setex(key, ttl, data)

class CacheManager:
    """Gerenciador principal de cache para o sistema Fature"""
    
    def __init__(self, config: CacheConfig = None):
        self.config = config or CacheConfig()
        self.affiliate_stats = AffiliateStatsCache(config)
        self.commissions = CommissionCache(config)
        self.rankings = RankingCache(config)
        self.sessions = SessionCache(config)
        self.reports = ReportCache(config)
    
    def health_check(self) -> Dict[str, bool]:
        """Verifica saúde de todas as conexões Redis"""
        health = {}
        
        for db in CacheDatabase:
            try:
                conn = self.affiliate_stats.get_connection(db)
                conn.ping()
                health[db.name] = True
            except Exception:
                health[db.name] = False
        
        return health
    
    def clear_all_cache(self):
        """Limpa todo o cache (usar com cuidado)"""
        for db in CacheDatabase:
            conn = self.affiliate_stats.get_connection(db)
            conn.flushdb()
    
    def get_cache_stats(self) -> Dict[str, Dict]:
        """Retorna estatísticas de uso do cache"""
        stats = {}
        
        for db in CacheDatabase:
            conn = self.affiliate_stats.get_connection(db)
            info = conn.info()
            stats[db.name] = {
                'used_memory': info.get('used_memory_human'),
                'connected_clients': info.get('connected_clients'),
                'total_commands_processed': info.get('total_commands_processed'),
                'keyspace_hits': info.get('keyspace_hits'),
                'keyspace_misses': info.get('keyspace_misses'),
                'hit_rate': info.get('keyspace_hits', 0) / max(info.get('keyspace_hits', 0) + info.get('keyspace_misses', 0), 1) * 100
            }
        
        return stats

# Exemplo de uso
if __name__ == "__main__":
    # Configuração
    config = CacheConfig(
        host='localhost',
        port=6379,
        password=None  # Definir senha em produção
    )
    
    # Inicializar gerenciador de cache
    cache_manager = CacheManager(config)
    
    # Verificar saúde
    health = cache_manager.health_check()
    print("Cache Health:", health)
    
    # Exemplo de uso do cache de afiliados
    affiliate_id = "123e4567-e89b-12d3-a456-426614174000"
    
    # Buscar estatísticas (primeiro do cache, depois do banco se não existir)
    stats = cache_manager.affiliate_stats.get_affiliate_stats(affiliate_id)
    if not stats:
        # Aqui você buscaria do banco de dados
        stats = {
            "total_volume": 10000.00,
            "total_commissions": 500.00,
            "total_referrals": 25,
            "last_activity": "2025-06-02T10:30:00Z"
        }
        # Armazenar no cache
        cache_manager.affiliate_stats.set_affiliate_stats(affiliate_id, stats)
    
    print("Affiliate Stats:", stats)

