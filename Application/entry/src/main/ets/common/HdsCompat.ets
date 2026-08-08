export enum MaterialLevel {
  EXQUISITE = 0,
  GENTLE = 1,
  SMOOTH = 2,
  ADAPTIVE = 3
}

export enum MaterialType {
  NONE = 0,
  IMMERSIVE = 1
}

export enum PointLightIlluminatedType {
  BORDER_CONTENT = 0
}

interface EmptyEffect {
  type: string
}

export interface PointLightOptions {
  color: ResourceColor
  intensity: number
  height: number
}

export interface PointLightParams {
  options: PointLightOptions
}

export interface PointLightIlluminatedParams {
  illuminatedType: PointLightIlluminatedType
}

export class HdsEffectBuilder {
  pointLight(options: PointLightParams): HdsEffectBuilder {
    return this
  }

  pointLightIlluminated(options: PointLightIlluminatedParams): HdsEffectBuilder {
    return this
  }

  buildEffect(): EmptyEffect {
    const effect: EmptyEffect = { type: 'empty' }
    return effect
  }
}
