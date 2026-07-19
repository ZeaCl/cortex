# MLX Worker — zea/models

Worker adapter para modelos locales optimizados para Apple Silicon vía `zea/models`.

## Requisitos

- macOS con Apple Silicon (M1/M2/M3/M4)
- [`zea/models`](https://github.com/ZeaCl/models) corriendo localmente
- Python 3.10+ y MLX instalados

## Instalación de zea/models

```bash
git clone https://github.com/ZeaCl/models
cd models
pip install -r requirements.txt
python server.py
```

El servidor expone los siguientes endpoints en `http://localhost:8000`:

| Endpoint | Método | Descripción |
|----------|--------|-------------|
| `/health` | GET | Health check + lista de modelos disponibles |
| `/v1/chat/completions` | POST | Chat completion (OpenAI-compatible) |

## Modelos disponibles

| Modelo | Underlying | Propósito |
|--------|-----------|-----------|
| `mlx-vision` | Qwen2.5-VL-3B-Instruct-4bit | Análisis de imágenes |
| `mlx-text` | Qwen2.5-3B-Instruct-4bit | Generación de texto |

Ambos modelos están cuantizados a 4-bit y optimizados para Apple Silicon.

## Variables de entorno

| Variable | Default | Descripción |
|----------|---------|-------------|
| `MLX_BASE_URL` | `http://localhost:8000` | URL del servidor zea/models |
| `MLX_MODEL` | `mlx-text` | Modelo por defecto |

## Uso con Cortex

### Registro automático

Cortex detecta automáticamente si `zea/models` está corriendo al iniciar (vía health check a `GET /health`). Si está disponible, registra el worker como `mlx-local`.

### vía API HTTP

```bash
# Usar el worker MLX explícitamente
curl -X POST http://localhost:4000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "¿Qué es MLX?"}],
    "provider": "mlx-local"
  }'

# Con el modelo de visión
curl -X POST http://localhost:4000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Describe esta imagen", "image": "base64..."}],
    "provider": "mlx-local",
    "model": "mlx-vision"
  }'
```

### vía CortexCore (Elixir)

```elixir
# Usar MLX explícitamente
{:ok, stream} = CortexCore.chat(
  [%{role: "user", content: "Explícame cómo funciona MLX"}],
  provider: "mlx-local"
)

# Sin provider — MLX se usará automáticamente si está disponible
# (prioridad 10, más alta que cualquier worker cloud)
{:ok, stream} = CortexCore.chat([
  %{role: "user", content: "Hola, ¿cómo estás?"}
])
```

## Prioridad en el pool

El worker MLX tiene prioridad **10**, que lo ubica:

- **Por debajo** de workers estrictamente locales (Ollama: 50)
- **Por encima** de cualquier worker cloud (OpenAI: 5, Anthropic: 15, Groq: 20, Gemini: 30)

Esto significa que si MLX está disponible, se usará **preferentemente sobre APIs cloud** durante desarrollo, con fallback automático a cloud si `zea/models` no está corriendo o falla.

## Health check

Cortex verifica la disponibilidad de `zea/models` al iniciar mediante `GET /health`. Si el servidor no responde en 2 segundos, el worker no se registra y se usa el siguiente disponible (failover automático a cloud).

## Limitaciones

- **Solo Apple Silicon** — MLX no funciona en Intel Macs ni otras arquitecturas
- **Modelos pequeños** — ~3B parámetros, cuantizados a 4-bit (no apto para tareas complejas)
- **Sin API keys** — solo acceso local, sin autenticación
- **Desarrollo** — diseñado para desarrollo local, no para producción
- **Sin herramientas** — no implementa `call_with_tools/3` (function calling no soportado)
