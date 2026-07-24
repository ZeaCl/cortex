/**
 * Global CLI options — parsed from process.argv.
 * Works regardless of Commander subcommand nesting.
 *
 * Usage:
 *   import { getGlobalOpts } from '../lib/globals.js';
 *   const opts = getGlobalOpts();
 *   if (opts.dryRun) { ... }
 */

export function getGlobalOpts() {
  const args = process.argv;

  return {
    output: getFlagValue(args, '--output', '-o') || 'table',
    debug: hasFlag(args, '--debug', '-d'),
    dryRun: hasFlag(args, '--dry-run'),
    quiet: hasFlag(args, '--quiet', '-q'),
    noColor: hasFlag(args, '--no-color'),
  };
}

function hasFlag(args, ...names) {
  return names.some((n) => args.includes(n));
}

function getFlagValue(args, ...names) {
  for (const name of names) {
    const idx = args.indexOf(name);
    if (idx !== -1 && idx + 1 < args.length) {
      const val = args[idx + 1];
      if (!val.startsWith('-')) return val;
    }
  }
  return null;
}

/**
 * Display data according to --output format.
 * - json: raw JSON.stringify
 * - text: plain string (no ANSI)
 * - table (default): human-readable with chalk
 */
export function display(data, opts = {}) {
  const format = opts.output || 'table';

  switch (format) {
    case 'json':
      console.log(JSON.stringify(data, null, 2));
      break;
    case 'text':
      console.log(stripAnsi(String(data)));
      break;
    default:
      console.log(data);
  }
}

function stripAnsi(str) {
  return str.replace(/\x1b\[[0-9;]*m/g, '');
}

export default { getGlobalOpts, display };
