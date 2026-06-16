#!/usr/bin/env mix run

alias CortexCommunity.Auth.QwenCredentialReader
alias CortexCommunity.Workers.QwenOAuthWorker

IO.puts("=== Probando Qwen OAuth ===")
{:ok, creds} = QwenCredentialReader.read_credentials()
IO.puts("Resource URL: #{creds.resource_url}")
IO.puts("Access token presente: #{creds.access_token != nil}")

worker = QwenOAuthWorker.new(
  name: "qwen-oauth-local",
  access_token: creds.access_token,
  resource_url: creds.resource_url
)

IO.puts("\n=== Health Check ===")
result = QwenOAuthWorker.health_check(worker)
IO.inspect(result, label: "Resultado")

IO.puts("\n=== Test de conexión directa ===")
base_url = "https://#{creds.resource_url}"
resp = Req.post(base_url <> "/v1/chat/completions",
  headers: [{"authorization", "Bearer #{creds.access_token}"}],
  json: %{
    "model" => "coder-model",
    "messages" => [%{"role" => "user", "content" => "hi"}],
    "max_tokens" => 1,
    "stream" => false
  },
  receive_timeout: 30000,
  retry: false
)
IO.inspect(resp, label: "Respuesta directa")
