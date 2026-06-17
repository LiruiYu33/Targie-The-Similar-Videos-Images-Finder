# Targie

[English](README.md) | [简体中文](README_ZH.md) | [繁體中文](README_ZH_HANT.md) | [Français](README_FR.md)

> **Solo macOS.** Targie es una aplicación nativa para macOS 14+. No hay versión para Windows ni Linux, y no está prevista.

Targie encuentra vídeos e imágenes similares en las carpetas seleccionadas combinando metadatos, hashes de contenido, huellas perceptuales y características visuales.

## Funcionalidades

- Alterna entre los modos de escaneo Vídeos, Imágenes y Todos, y recuerda el modo seleccionado.
- Agrega múltiples carpetas mediante el selector o arrastrando desde Finder, y compara archivos multimedia entre todas las carpetas seleccionadas.
- Escanea recursivamente formatos de vídeo comunes además de imágenes JPEG, PNG, HEIC, HEIF, WebP, TIFF, GIF y BMP.
- Utiliza SHA-256, huellas perceptuales en caché, metadatos y características Vision reutilizables, aislando los archivos ilegibles.
- Mantiene los grupos de vídeos e imágenes separados para revisión lado a lado con vistas previas estáticas integradas.
- Abre vídeos en el reproductor predeterminado y muestra cualquier archivo multimedia en Finder.
- Permite la selección múltiple explícita y la eliminación por lotes con éxito parcial.
- Requiere elegir explícitamente entre mover a la Papelera o eliminar permanentemente, con una segunda confirmación para la eliminación permanente.
- Compatible con inglés, chino simplificado, chino tradicional, español y francés, con cambio instantáneo y preferencia recordada.
- **Modo exploración**: visualiza todos los archivos de las carpetas seleccionadas en una tabla ordenable y filtrable, con columnas redimensionables arrastrando, selección por lotes y título de ventana actualizado en tiempo real.

![Comparación de similitud de imágenes](asset/Screenshot1.png)

![Comparación de similitud de vídeos](asset/Screenshot2.png)

![Modo exploración — lista de archivos con vista previa](asset/Screenshot3.png)

## Compilación (solo macOS)

```bash
swift test
./script/build_app.sh
```

La aplicación generada se encuentra en:

```text
dist/Targie.app
```

Para desarrollo, compila y ejecuta con:

```bash
./script/build_and_run.sh
```

La aplicación está firmada ad-hoc para uso local. La distribución a través de internet o la App Store requiere un Developer ID, certificación notarial y el flujo de empaquetado correspondiente.

## Licencia

Targie está bajo la licencia **[GNU General Public License v3.0](LICENSE)**.

Copyright (C) 2026 Lirui Yu.

Si reutilizas este código (modificado o no):

- **Debes** mantener el aviso de copyright y atribuir al autor original (Lirui Yu).
- Cualquier obra derivada que distribuyas **debe** publicarse también bajo GPL-3.0 (o una versión posterior de GPL), con el código fuente completo disponible para sus usuarios.
- La redistribución de código cerrado o propietario **no** está permitida.

Consulta el archivo [LICENSE](LICENSE) para el texto legal completo.

## Contribuciones

Las pull requests son bienvenidas. Cada commit debe estar firmado bajo el [Developer Certificate of Origin (DCO)](DCO) — usa `-s` en `git commit`. Consulta [CONTRIBUTING.md](CONTRIBUTING.md) para más detalles.
