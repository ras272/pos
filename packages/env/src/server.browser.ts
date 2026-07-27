// @ts-expect-error This unresolved import intentionally fails browser bundles.
import { browserBuildMustFail } from "@workspace/env/server-entry-is-not-browser-safe"

void browserBuildMustFail
