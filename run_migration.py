#!/usr/bin/env python
"""Run database migrations against Supabase."""
import os
from pathlib import Path
from dotenv import load_dotenv
import psycopg2

# Load environment variables from .env
load_dotenv()

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

# Run migration
migration_file = Path(__file__).parent / 'migrations' / '001_create_user_tables.sql'
print(f'Running migration: {migration_file.name}')

try:
    with conn.cursor() as cur:
        with open(migration_file, 'r', encoding='utf-8') as f:
            sql = f.read()
        cur.execute(sql)
    print('Tables created successfully!')
    print('  - profiles')
    print('  - user_programs')
    print('  - RLS policies enabled')
except Exception as e:
    print(f'Migration failed: {e}')
    conn.close()
    exit(1)

conn.close()
print('Migration complete!')
