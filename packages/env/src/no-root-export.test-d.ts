// @ts-expect-error @workspace/env intentionally has no root export.
import type { PublicEnv } from "@workspace/env"

export type RootExportMustNotExist = PublicEnv
