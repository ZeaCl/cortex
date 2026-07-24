/**
 * cortex doctor — Full integration diagnostic.
 *
 * Checks: connectivity, auth (via Thalamus), LLM providers, workers.
 */
import { loadConfig, getClient } from '../lib/client.js';
import { zeaFetch } from '../lib/http.js';
import chalk from 'chalk';

let passes = 0;
let warnings = 0;
let failures = 0;

function pass(msg) { passes++; console.log(`   ✅ ${msg}`); }
function warn(msg) { warnings++; console.log(`   ⚠️  ${msg}`); }
function fail(msg) { failures++; console.log(`   ❌ ${msg}`); }

export function register(program) {
  program.command('doctor')
    .description('Full integration diagnostic: connectivity, auth, LLM providers, workers')
    .action(async () => {
      let apiUrl = 'http://cortex.zea.localhost';
      let authUrl = 'https://auth.zea.cl';
      try {
        const config = await loadConfig();
        apiUrl = config.cortexUrl || apiUrl;
        authUrl = config.apiUrl || authUrl;
      } catch {}
      apiUrl = process.env.CORTEX_API_URL || process.env.CORTEX_URL || apiUrl;
      authUrl = process.env.ZEA_API_URL || process.env.THALAMUS_API_URL || authUrl;

      console.log('');
      console.log(chalk.cyan(`🩺 Cortex Doctor — ${apiUrl}`));
      console.log('');

      // ── 1. Connectivity ──────────────────────────
      console.log('── Connectivity ────────────────────────────');
      let healthData = null;
      try {
        const resp = await zeaFetch(`${apiUrl}/health`);
        if (resp.ok) {
          healthData = await resp.json();
          pass(`Cortex reachable (v${healthData.version || '?.?.?'})`);

          if (healthData.services) {
            if (healthData.services.database) {
              if (healthData.services.database === 'ok') pass('Database: ok');
              else fail(`Database: ${healthData.services.database}`);
            }
          }

          if (healthData.workers !== undefined) {
            const workerCount = healthData.workers || 0;
            if (workerCount > 0) pass(`${workerCount} workers registered`);
            else warn('No workers registered');
          }
        } else {
          fail(`Cortex returned HTTP ${resp.status}`);
        }
      } catch (e) {
        if (e.code === 'ENOTFOUND' || e.code === 'ECONNREFUSED') {
          fail(`Cannot reach ${apiUrl}`);
          console.log('');
          console.log(chalk.dim('   💡 Try: docker compose up -d'));
        } else {
          fail(`Connection error: ${e.message}`);
        }
      }

      if (!healthData) {
        printSummary();
        return;
      }

      // ── 2. Thalamus Connectivity ─────────────────
      console.log('── Authentication (Thalamus) ───────────────');
      let token = null;
      try {
        const client = await getClient(true);
        token = client.token;

        if (token) {
          pass('Token found in config');

          // Check Thalamus health
          try {
            const thalamusResp = await zeaFetch(`${authUrl}/api/public/health`);
            if (thalamusResp.ok) {
              pass(`Thalamus reachable at ${authUrl}`);
            } else {
              warn(`Thalamus returned HTTP ${thalamusResp.status}`);
            }
          } catch {
            warn(`Cannot reach Thalamus at ${authUrl}`);
            console.log(chalk.dim('   💡 Is Thalamus running?'));
          }

          // Check token validity
          try {
            const userResp = await zeaFetch(`${authUrl}/oauth/userinfo`, {
              headers: client.headers,
            });
            if (userResp.ok) {
              const userinfo = await userResp.json();
              pass(`Authenticated as ${userinfo.email || userinfo.sub}`);

              if (userinfo.organizations && userinfo.organizations.length > 0) {
                const orgNames = userinfo.organizations.map(o => o.name || o.slug).join(', ');
                pass(`Organizations: ${orgNames}`);
              }
            } else if (userResp.status === 401) {
              warn('Token expired or invalid');
              console.log(chalk.dim('   💡 Run: zea thalamus auth login'));
            }
          } catch {
            warn('Could not verify token with auth server');
          }
        } else {
          warn('No token found');
          console.log(chalk.dim('   💡 Run: zea thalamus auth login'));
        }
      } catch {
        warn('No token found');
        console.log(chalk.dim('   💡 Run: zea thalamus auth login'));
      }

      // ── 3. LLM Providers ─────────────────────────
      console.log('── LLM Providers ───────────────────────────');
      try {
        const headers = token
          ? { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }
          : { 'Content-Type': 'application/json' };

        const modelsResp = await zeaFetch(`${apiUrl}/api/models`, { headers });
        if (modelsResp.ok) {
          const modelsData = await modelsResp.json();
          const models = modelsData.data || modelsData.models || [];
          pass(`${models.length} models available`);

          // Group by provider
          const byProvider = {};
          for (const m of models) {
            const provider = m.provider || m.owned_by || 'unknown';
            if (!byProvider[provider]) byProvider[provider] = [];
            byProvider[provider].push(m.id || m.name);
          }

          for (const [provider, modelList] of Object.entries(byProvider)) {
            const preview = modelList.slice(0, 3).join(', ');
            const suffix = modelList.length > 3 ? ` +${modelList.length - 3} more` : '';
            console.log(chalk.dim(`     • ${provider}: ${preview}${suffix}`));
          }
        } else {
          warn(`Models endpoint returned HTTP ${modelsResp.status}`);
        }
      } catch {
        warn('Could not fetch models');
      }

      // ── 4. API Keys (DeepSeek priority) ──────────
      console.log('── API Keys ────────────────────────────────');
      const providers = ['deepseek', 'openai', 'anthropic', 'google', 'groq'];
      for (const provider of providers) {
        const envVar = `${provider.toUpperCase()}_API_KEYS`;
        const envKeys = process.env[envVar];
        if (envKeys) {
          const count = envKeys.split(',').filter(k => k.trim()).length;
          pass(`${provider}: ${count} key(s) from ${envVar}`);
        } else {
          const keyVar = `${provider.toUpperCase()}_API_KEY`;
          if (process.env[keyVar]) {
            pass(`${provider}: 1 key from ${keyVar}`);
          }
        }
      }

      printSummary();
    });
}

function printSummary() {
  console.log('');
  console.log('── Summary ──────────────────────────────────');
  const total = passes + warnings + failures;
  console.log(`   ✅ ${passes}  ⚠️  ${warnings}  ❌ ${failures}  (${total} checks)`);

  if (failures === 0 && warnings === 0) {
    console.log('');
    console.log(chalk.green('   🎉 All systems operational!'));
    process.exit(0);
  } else if (failures > 0) {
    console.log('');
    console.log(chalk.red('   🔴 Some checks failed. Review the ❌ items above.'));
    process.exit(1);
  } else {
    console.log('');
    console.log(chalk.yellow('   🟡 Minor warnings — system is functional.'));
    process.exit(0);
  }
}
