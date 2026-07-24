/**
 * Centralized CLI error handler.
 * All commands route errors through here for consistent output + exit behavior.
 */

export function handleError(error) {
  if (!error) {
    console.error('❌ Unknown error');
    process.exit(1);
  }

  if (error.response) {
    const status = error.response.status;
    if (status === 401) {
      console.error('🔒 Token expired or invalid. Run: zea thalamus auth login');
    } else if (status === 403) {
      console.error('🚫 Forbidden. Check your permissions and active organization.');
    } else if (status === 404) {
      console.error('❌ Not found.');
    } else if (status >= 500) {
      console.error(`❌ Server error (HTTP ${status}). Try again later.`);
    } else {
      console.error(`❌ HTTP ${status}: ${error.message}`);
    }
  } else if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED') {
    console.error('❌ Cannot reach Cortex. Is it running?');
    console.error('   Run: zea cortex health');
  } else if (error.message?.includes('Not authenticated')) {
    console.error('❌ Not authenticated. Please authenticate first.');
  } else {
    console.error(`❌ Error: ${error.message || error}`);
  }

  process.exit(1);
}
