import { config } from "@workspace/eslint-config/react-internal"

/** @type {import("eslint").Linter.Config[]} */
export default [
  ...config,
  {
    // Temporary baseline for generated shadcn sources; all other warnings fail CI.
    files: ["src/components/carousel.tsx", "src/hooks/use-mobile.ts"],
    rules: {
      "react-hooks/set-state-in-effect": "off",
    },
  },
]
