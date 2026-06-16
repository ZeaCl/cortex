defmodule CortexCommunity.ModelDiscovery.ModelInfo do
  @moduledoc """
  Static lookup for context window sizes by model ID.

  Used by both ModelsController and HealthController so clients always
  know how many tokens they can send in a single request.

  Values are `%{input: integer, output: integer}` in tokens.
  """

  # Matches on substring so partial model IDs from discovery also work.
  # More specific patterns must come before generic ones.
  @context_windows [
    # Anthropic Claude
    {"claude-sonnet-4", %{input: 200_000, output: 64_000}},
    {"claude-opus-4", %{input: 200_000, output: 32_000}},
    {"claude-haiku-4", %{input: 200_000, output: 8_192}},
    {"claude-3-5-haiku", %{input: 200_000, output: 8_192}},
    {"claude-3.5-haiku", %{input: 200_000, output: 8_192}},
    {"claude-3-opus", %{input: 200_000, output: 4_096}},
    {"claude-3.7-sonnet", %{input: 200_000, output: 64_000}},
    # Google Gemini 2.5+
    {"gemini-2.5-pro", %{input: 1_048_576, output: 65_536}},
    {"gemini-2.5-flash", %{input: 1_048_576, output: 65_536}},
    {"gemini-2.0-flash", %{input: 1_048_576, output: 8_192}},
    {"gemini-1.5-pro", %{input: 2_097_152, output: 8_192}},
    {"gemini-1.5-flash", %{input: 1_048_576, output: 8_192}},
    # Groq / Meta LLaMA
    {"llama-4-maverick", %{input: 524_288, output: 8_192}},
    {"llama-4-scout", %{input: 327_680, output: 8_192}},
    {"llama-3.3-70b", %{input: 128_000, output: 32_768}},
    {"llama-3.1-70b", %{input: 128_000, output: 32_768}},
    {"llama-3.1-8b", %{input: 128_000, output: 32_768}},
    # Groq / Qwen
    {"qwen3-32b", %{input: 131_072, output: 32_768}},
    # Groq / Mixtral
    {"mixtral-8x7b", %{input: 32_768, output: 32_768}},
    # OpenAI
    {"gpt-4o", %{input: 128_000, output: 16_384}},
    {"gpt-4-turbo", %{input: 128_000, output: 4_096}},
    {"gpt-4", %{input: 8_192, output: 8_192}},
    {"gpt-3.5-turbo", %{input: 16_385, output: 4_096}},
    # xAI Grok
    {"grok-3-mini", %{input: 131_072, output: 16_384}},
    {"grok-code-fast", %{input: 131_072, output: 16_384}},
    {"grok-beta", %{input: 131_072, output: 16_384}},
    {"grok-3", %{input: 131_072, output: 16_384}},
    # Cohere
    {"command-r-plus", %{input: 128_000, output: 4_096}},
    {"command-r", %{input: 128_000, output: 4_096}},
    {"command-light", %{input: 4_096, output: 4_096}}
  ]

  @doc """
  Returns `%{input: tokens, output: tokens}` for a given model ID,
  or `nil` if unknown. Matches on substring — partial IDs work too.
  """
  @spec context_window(String.t() | nil) :: %{input: integer, output: integer} | nil
  def context_window(nil), do: nil

  def context_window(model_id) when is_binary(model_id) do
    Enum.find_value(@context_windows, fn {pattern, ctx} ->
      if String.contains?(model_id, pattern), do: ctx
    end)
  end
end
