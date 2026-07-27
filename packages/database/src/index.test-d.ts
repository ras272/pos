import type { Database } from "@workspace/database"

type TenantsRow = Database["public"]["Tables"]["tenants"]["Row"]

const tenant = {} as TenantsRow

tenant.id satisfies string
