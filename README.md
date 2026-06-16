# Cortex

Cortex es el gateway y orquestador central impulsado por IA de la plataforma ZEA.

Actualmente funciona bajo una arquitectura **Majestic Monolith** (Monolito Majestuoso), agrupando la aplicación web, la API REST y la lógica fundacional de inteligencia artificial en un solo repositorio unificado y altamente cohesionado.

## Arquitectura del Proyecto

Este repositorio consolida lo que anteriormente eran proyectos separados:

- **`/` (Aplicación Principal):** Contiene la aplicación web y la API REST, construidas sobre Phoenix Framework (`cortex_community`).
- **`/core` (Librería Central):** Contiene el motor lógico (`cortex_core`), los adaptadores a modelos (OpenAI, Anthropic, Qwen, DeepSeek) y los comportamientos de los Workers. Esta librería está vinculada localmente y se mantiene puramente enfocada en la lógica de negocio sin depender de la capa web.
- **`/cli` (Plugin de CLI Delegado):** Contiene el comando descentralizado `@zea-cl/cli-cortex`. Al ser instalado globalmente, nuestro router unificado (`zea-cli`) lo descubre dinámicamente, proveyendo la interfaz de comandos para la gestión de infraestructura.

## Instalación y Ejecución

### Requisitos Previos
- Elixir ~> 1.19
- Node.js ~> 22.x
- PostgreSQL

### Compilación del Proyecto
Al compilar la aplicación, Elixir resolverá localmente el código del core:
```bash
# Instalar dependencias (incluye la librería ./core local)
mix deps.get

# Compilar todo el proyecto
mix compile

# Preparar la base de datos
mix ecto.setup
```

### Iniciar el Servidor Web
```bash
mix phx.server
```

### Usar la CLI
Para usar la interfaz de línea de comandos delegada de Cortex a través del router `zea`:

```bash
cd cli
npm install -g .
```

Luego, en cualquier terminal:
```bash
zea cortex status
```
