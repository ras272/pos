export type VerifiedActor = Readonly<{
  /** `sub` verificado del token. Es el único identificador de actor confiable. */
  id: string
  /**
   * Credencial ya verificada con la que se construye el cliente con alcance de
   * usuario. Nunca se audita ni se devuelve en un DTO: solo viaja de la
   * autenticación a `createScopedClient`.
   */
  credential?: string
}>

export type Authenticator<Context> = (
  context: Context
) => Promise<VerifiedActor | undefined>
