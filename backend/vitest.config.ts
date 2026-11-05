import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    fileParallelism: false,
    testTimeout: 20000,
    hookTimeout: 30000,
    env: {
      NODE_ENV: 'test',
      DATABASE_URL: process.env.TEST_DATABASE_URL ?? 'postgres://keys@localhost:5433/keys_test',
      STORAGE_DIR: './.test-storage',
      MAX_CODES_PER_IP_HOUR: '100000',
    },
  },
});
