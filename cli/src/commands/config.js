/**
 * cortex config — Manage Cortex configuration.
 *
 * Reads/writes the shared ZEA config file (~/.config/zea/config.json).
 * Manages cortexUrl and other cortex-specific settings.
 */
import fs from 'fs/promises';
import path from 'path';
import os from 'os';
import chalk from 'chalk';
import { loadConfig, saveConfig } from '../lib/client.js';
import { handleError } from '../lib/errors.js';

const CONFIG_FILE = path.join(os.homedir(), '.config', 'zea', 'config.json');

export function register(program) {
  const configCmd = program.command('config').description('Manage Cortex configuration');

  configCmd.command('set-env <env>')
    .description('Set standard environment profile (local or prod)')
    .action(async (envName) => {
      try {
        const config = await loadConfig();
        if (envName === 'local') {
          config.cortexUrl = 'http://cortex.zea.localhost';
          config.apiUrl = 'http://auth.zea.localhost';
          console.log(chalk.green('✅ Cortex environment set to LOCAL'));
        } else if (envName === 'prod') {
          config.cortexUrl = 'https://cortex.zea.cl';
          config.apiUrl = 'https://auth.zea.cl';
          console.log(chalk.green('✅ Cortex environment set to PROD'));
        } else {
          console.log(chalk.red('Unknown environment. Use "local" or "prod".'));
          return;
        }
        await saveConfig(config);
      } catch (e) {
        handleError(e);
      }
    });

  configCmd.command('set <key> <value>')
    .description('Set a configuration value')
    .action(async (key, value) => {
      try {
        const config = await loadConfig();
        config[key] = value;
        await saveConfig(config);
        console.log(chalk.green(`✅ ${key} = ${value}`));
      } catch (e) {
        handleError(e);
      }
    });

  configCmd.command('get <key>')
    .description('Get a configuration value')
    .action(async (key) => {
      try {
        const config = await loadConfig();
        if (config[key] !== undefined) {
          console.log(config[key]);
        } else {
          console.log(chalk.dim(`(not set: ${key})`));
        }
      } catch (e) {
        handleError(e);
      }
    });

  configCmd.command('list')
    .description('List all configuration values')
    .action(async () => {
      try {
        const config = await loadConfig();
        const keys = Object.keys(config);

        if (keys.length === 0) {
          console.log(chalk.dim('No configuration set.'));
          console.log(chalk.dim(`Config file: ${CONFIG_FILE}`));
          return;
        }

        console.log(chalk.cyan('ZEA Configuration:'));
        console.log(chalk.dim(`File: ${CONFIG_FILE}\n`));

        const masked = ['token', 'refreshToken', 'deepseek_key', 'deepseekKey'];

        for (const key of keys) {
          const val = masked.includes(key)
            ? '••••••••' + config[key].slice(-4)
            : config[key];
          console.log(`  ${chalk.yellow(key)}: ${val}`);
        }
      } catch (e) {
        handleError(e);
      }
    });

  configCmd.command('unset <key>')
    .description('Remove a configuration value')
    .action(async (key) => {
      try {
        const config = await loadConfig();
        delete config[key];
        await saveConfig(config);
        console.log(chalk.green(`✅ ${key} removed`));
      } catch (e) {
        handleError(e);
      }
    });

  configCmd.command('path')
    .description('Show config file path')
    .action(() => {
      console.log(CONFIG_FILE);
    });
}
