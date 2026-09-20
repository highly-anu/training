#!/usr/bin/env python
"""Run a database migration against Supabase.

    python run_migration.py                        # 001_create_user_tables.sql
    python run_migration.py 003_workout_dedupe     # .sql suffix optional
    python run_migration.py --list
"""
import os
import sys
from pathlib import Path
from dotenv import load_dotenv
import psycopg2

# Load environment variables from .env
load_dotenv()

MIGRATIONS_DIR = Path(__file__).parent / 'migrations'


def resolve_migration(argv: list[str]) -> Path:
    """Pick the migration to run from argv, defaulting to the first one."""
    available = sorted(MIGRATIONS_DIR.glob('*.sql'))
    if '--list' in argv:
        print('Available migrations:')
        for m in available:
            print(f'  {m.name}')
        exit(0)

    name = argv[1] if len(argv) > 1 else '001_create_user_tables'
    if not name.endswith('.sql'):
        name += '.sql'
    path = MIGRATIONS_DIR / name
    if not path.exists():
        print(f'ERROR: no such migration: {name}')
        print('Available:')
        for m in available:
            print(f'  {m.name}')
        exit(1)
    return path


migration_file = resolve_migration(sys.argv)

DATABASE_URL = os.environ.get('DATABASE_URL', '')
if not DATABASE_URL:
    print('ERROR: DATABASE_URL not set in .env file')
    exit(1)

# Add SSL requirement for Supabase
dsn = DATABASE_URL if 'sslmode=' in DATABASE_URL else DATABASE_URL + ('&' if '?' in DATABASE_URL else '?') + 'sslmode=require'

print('Connecting to Supabase...')
try:
    conn = psycopg2.connect(dsn)
    conn.autocommit = True
    print('Connected successfully')
except Exception as e:
    print(f'Connection failed: {e}')
    exit(1)

print(f'Running migration: {migration_file.name}')

try:
    with conn.cursor() as cur:
        with open(migration_file, 'r', encoding='utf-8') as f:
            sql = f.read()
        cur.execute(sql)
    print('Migration applied successfully!')
except Exception as e:
    print(f'Migration failed: {e}')
    conn.close()
    exit(1)

conn.close()
print('Migration complete!')
