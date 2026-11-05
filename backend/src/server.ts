import { buildApp } from './app.js';
import { config } from './config.js';
import { migrate } from './db/migrate.js';
import { startJobs } from './jobs.js';

await migrate();
const app = await buildApp();
startJobs();
await app.listen({ port: config.port, host: '0.0.0.0' });
