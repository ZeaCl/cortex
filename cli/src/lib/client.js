/**
 * Cortex CLI client — config & auth management.
 *
 * Reads the shared ZEA config at ~/.config/zea/config.json
 * (same file used by zea-cli, zea-thalamus, and zea-cerebelum).
 *
 * Token priority: ZEA_PAT → THALAMUS_PAT → ZEA_TOKEN → config.token
 * API URL priority: CORTEX_API_URL → CORTEX_URL → config.cortexUrl → default
 */
import fs from 'fs/promises';
import path from 'path';
import os from 'os';

export const CONFIG_DIR = path.join(os.homedir(), '.config', 'zea');
export const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');

export async function loadConfig() {
  try {
    const data = await fs.readFile(CONFIG_FILE, 'utf8');
    return JSON.parse(data);
  } catch {
    return {};
  }
}

export async function saveConfig(config) {
  await fs.mkdir(CONFIG_DIR, { recursive: true });
  await fs.writeFile(CONFIG_FILE, JSON.stringify(config, null, 2), 'utf8');
}

/**
 * Get a configured client for Cortex API calls.
 *
 * Reads auth token and API URLs from the shared ZEA config.
 * Throws if no token is found (unless allowUnauthenticated is true).
 */
export async function getClient(allowUnauthenticated = false) {
  const config = await loadConfig();
  const token =
    process.env.ZEA_PAT ||
    process.env.THALAMUS_PAT ||
    process.env.ZEA_TOKEN ||
    config.token ||
    null;

  const apiUrl =
    process.env.CORTEX_API_URL ||
    process.env.CORTEX_URL ||
    config.cortexUrl ||
    'http://cortex.zea.localhost';

  const authUrl =
    process.env.ZEA_API_URL ||
    process.env.THALAMUS_API_URL ||
    config.apiUrl ||
    'https://auth.zea.cl';

  const activeOrgId = config.activeOrgId || process.env.ZEA_ORG_ID || null;

  if (!token && !allowUnauthenticated) {
    throw new Error('Not authenticated. Please authenticate first.');
  }

  return {
    apiUrl,
    authUrl,
    token,
    activeOrgId,
    headers: token
      ? {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        }
      : {
          'Content-Type': 'application/json',
        },
  };
}
