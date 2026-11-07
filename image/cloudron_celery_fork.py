"""ADR 0009: give every forked Celery worker its own database connections.

docassemble creates its SQLAlchemy engines when the Celery parent imports the worker module, and the
parent opens connections before it forks the pool. Each child then inherits the same sockets, and two
processes using one PostgreSQL connection at once corrupt the protocol stream ("error with status
PGRES_TUPLES_OK and no message from the libpq", ResourceClosedError, StaleDataError). SQLAlchemy's
documented remedy: in each new child, dispose of the inherited pools with close=False, which drops the
child's references without touching the parent's sockets. Loaded with `celery ... --include
cloudron_celery_fork`; no docassemble code is changed.
"""
import gc

from celery.signals import worker_process_init


@worker_process_init.connect
def _fresh_database_connections(**_kwargs):
    from sqlalchemy.engine import Engine
    for obj in gc.get_objects():
        if isinstance(obj, Engine):
            obj.dispose(close=False)
