import { config } from "@workspace/eslint-config/react-internal"

/**
 * La caja es React sin Next, así que usa la configuración compartida de
 * biblioteca React. Antes tenía una configuración propia sin parser de
 * TypeScript: cualquier anotación de tipo rompía el lint sin que se notara,
 * porque los archivos existentes no tenían ninguna.
 *
 * @type {import("eslint").Linter.Config[]}
 */
export default [...config, { ignores: ["dist/**"] }]
