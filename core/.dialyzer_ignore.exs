[
  # rate_limit_error?/1 catch-all clause is intentional defensive code;
  # at call sites error_msg is always binary, but the clause is kept for safety.
  {"lib/cortex_core/workers/pool.ex", :pattern_match_cov},

  # Supervisor.init/1 — dialyzer false positive on generic Supervisor init.
  {"lib/cortex_core/workers/supervisor.ex", :no_return},

  # GroqWorker with_internal_retry — dialyzer can't infer error types through APIWorkerBase delegation
  {"lib/cortex_core/workers/adapters/groq_worker.ex", :pattern_match}
]
