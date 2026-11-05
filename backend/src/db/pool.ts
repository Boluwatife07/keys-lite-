import pg from 'pg';
import { config } from '../config.js';

export const pool = new pg.Pool({ connectionString: config.databaseUrl, max: 10 });

export type Db = pg.Pool | pg.PoolClient;

export async function q<T = any>(sql: string, params: unknown[] = [], db: Db = pool): Promise<T[]> {
  const res = await db.query(sql, params);
  return res.rows as T[];
}
export async function one<T = any>(sql: string, params: unknown[] = [], db: Db = pool): Promise<T | undefined> {
  const rows = await q<T>(sql, params, db);
  return rows[0];
}

export async function tx<T>(fn: (c: pg.PoolClient) => Promise<T>): Promise<T> {
  const c = await pool.connect();
  try {
    await c.query('begin');
    const out = await fn(c);
    await c.query('commit');
    return out;
  } catch (e) {
    await c.query('rollback');
    throw e;
  } finally {
    c.release();
  }
}
