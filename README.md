# Mi Ganado 🐄

Web app (PWA) de control ganadero: animales, reproducción, producción de leche y carne, sanidad,
alertas, fotos y documentos, y finanzas. Funciona sin internet y sincroniza con Supabase.

- **Sitio:** https://mi-ganaderia.netlify.app
- **Base de datos:** Supabase (PostgreSQL + Auth + Storage), con seguridad por usuario (RLS).

## Estructura

| Carpeta | Contenido |
|---|---|
| `web/` | La app publicada (Netlify publica solo esta carpeta) |
| `supabase/` | Scripts SQL, en orden: ejecutar en Supabase → SQL Editor |

## Versiones

- **v1** – App local (IndexedDB): fincas, lotes, animales, eventos, alertas, informes.
- **v2** – Nube con Supabase, inicio de sesión, sincronización sin conexión, instalable (PWA).
- **v3** – Fotos y documentos por animal (Supabase Storage) y módulo de finanzas.

## Publicar una versión nueva

Cada `git push` a `main` publica automáticamente en Netlify. Si una versión da problemas,
en Netlify → Deploys se puede volver a una anterior con **Publish deploy**.
