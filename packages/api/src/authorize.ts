import type { VerifiedActor } from "./authenticate"

export type AuthorizationDecision = Readonly<{ allowed: boolean }>

export type Authorizer<Input> = (
  input: Input,
  actor: VerifiedActor
) => Promise<AuthorizationDecision>
