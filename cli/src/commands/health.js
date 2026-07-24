/**
 * cortex health — Check Cortex engine health status (no auth required).
 */
import { zeaFetch } from '../lib/http.js';
import { getGlobalOpts } from '../lib/globals.js';
import { handleError } from '../lib/errors.js';
import { loadConfig } from '../lib/client.js';
import chalk from 'chalk';

export function register(program) {
  program.command('health')
    .description('Check Cortex gateway health status (no auth required)')
    .action(async () => {
      const opts = getGlobalOpts();
      try {
        let apiUrl = 'http://cortex.zea.localhost';
        try {
          const config = await loadConfig();
          if (config.cortexUrl) apiUrl = config.cortexUrl;
        } catch { /* use default */ }

        apiUrl = process.env.CORTEX_API_URL || process.env.CORTEX_URL || apiUrl;

        const response = await zeaFetch(`${apiUrl}/health`);

        if (!response.ok) {
          console.error(chalk.red(`❌ Cortex returned HTTP ${response.status}`));
          process.exit(1);
        }

        const data = await response.json();

        if (opts.output === 'json') {
          console.log(JSON.stringify(data, null, 2));
          process.exit(data.status === 'ok' ? 0 : 1);
        }

        const statusIcon = data.status === 'ok' ? '✅' : '⚠️';

        console.log(chalk.cyan(`\n🧠 Cortex ${data.version || '?.?.?'} — ${apiUrl}`));
        console.log(`   Status:   ${statusIcon} ${(data.status || 'unknown').toUpperCase()}`);

        if (data.services) {
          if (data.services.database) {
            const dbIcon = data.services.database === 'ok' ? '✅' : '❌';
            console.log(`   Database: ${dbIcon} ${data.services.database}`);
          }
        }

        if (data.workers !== undefined) {
          const workerCount = data.workers || 0;
          const workerIcon = workerCount > 0 ? '✅' : '⚠️';
          console.log(`   Workers:  ${workerIcon} ${workerCount} registered`);
        }

        if (data.errors && data.errors.length > 0) {
          console.log(chalk.red('   Errors:'));
          for (const err of data.errors) {
            console.log(chalk.red(`     - ${err}`));
          }
        }

        console.log('');

        if (data.status !== 'ok') {
          console.log('   Run: zea cortex doctor');
          process.exit(1);
        }
      } catch (e) {
        if (e.code === 'ENOTFOUND' || e.code === 'ECONNREFUSED') {
          let url = 'http://cortex.zea.localhost';
          try {
            const config = await loadConfig();
            url = config.cortexUrl || url;
          } catch {}
          url = process.env.CORTEX_API_URL || process.env.CORTEX_URL || url;
          console.error(chalk.red(`❌ Cannot reach Cortex at ${url}`));
          console.error('   Is it running? Try: docker compose up -d');
        } else {
          handleError(e);
        }
        process.exit(1);
      }
    });
}
