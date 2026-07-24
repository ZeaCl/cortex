# ZEA Cortex CLI

## Qué se construyó

CLI `zea-cortex` — binario Node.js descubrible por el router `zea` del PATH. Sigue la misma arquitectura que `zea-thalamus` y `zea-cerebelum`.

## Comandos

```
zea cortex
├── config           Configuración local
│   ├── set-env <local|prod>
│   ├── set <key> <value>
│   ├── get <key>
│   ├── list
│   ├── unset <key>
│   └── path
├── health           Health check (público)
└── doctor           Diagnóstico completo
```

## Archivos

| Archivo | Rol |
|---------|-----|
| `cli/package.json` | npm package `@zea.cl/cortex` |
| `cli/bin/zea-cortex.js` | Entry point (commander) |
| `cli/src/commands/config.js` | Configuración (set-env, set, get, list, unset, path) |
| `cli/src/commands/health.js` | Health check → `GET /health` |
| `cli/src/commands/doctor.js` | Diagnóstico: connectivity, auth (Thalamus), LLM providers, API keys |
| `cli/src/lib/http.js` | `zeaFetch` — HTTP client con resolución DNS del SO + header Host para Caddy |
| `cli/src/lib/client.js` | `getClient()` + `loadConfig()` — token y URLs desde `~/.config/zea/config.json` |
| `cli/src/lib/errors.js` | `handleError()` — manejo centralizado de errores HTTP y de red |
| `cli/src/lib/globals.js` | `getGlobalOpts()` + `display()` — flags globales y formatos de salida |

## Decisiones de diseño

### ¿Por qué copiar lib/ de Cerebelum?
Cerebelum tiene las versiones más limpias de `http.js` (con fix del header `Host` para Caddy), `errors.js` (sin sugerir comandos de login que no le corresponden), y `client.js` (sin URLs de otros servicios). Partir de ahí evita propagar los issues ya identificados en Thalamus.

### Doctor diagnostica lo específico de cortex
- Thalamus reachable + token validity
- LLM providers configurados (vía `/api/models`)
- API keys disponibles (env vars por provider)
- Workers registrados

### Sin dependencia de `open` ni `ora`
A diferencia de Thalamus y Cerebelum, cortex no necesita OAuth2 browser flow ni spinners — solo `commander` + `chalk`.

## Issues relacionados

- #13 — Crear CLI zea-cortex
- #16 — Implementar cortex doctor
