import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from './pool.js';

const dir = join(dirname(fileURLToPath(import.meta.url)), 'migrations');

export async function migrate() {
  await pool.query('create table if not exists schema_migrations (name text primary key, run_at timestamptz default now())');
  const done = new Set((await pool.query('select name from schema_migrations')).rows.map((r) => r.name));
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
    if (done.has(file)) continue;
    const c = await pool.connect();
    try {
      await c.query('begin');
      await c.query(readFileSync(join(dir, file), 'utf8'));
      await c.query('insert into schema_migrations(name) values ($1)', [file]);
      await c.query('commit');
    } catch (e) {
      await c.query('rollback');
      throw new Error(`Migration ${file} failed: ${(e as Error).message}`);
    } finally {
      c.release();
    }
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  migrate().then(() => { console.log('migrations done'); return pool.end(); });
}
