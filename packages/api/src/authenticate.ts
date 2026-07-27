export type VerifiedActor = Readonly<{ id: string }>

export type Authenticator<Context> = (
  context: Context
) => Promise<VerifiedActor | undefined>
