import { common } from '@kit.AbilityKit';

interface HostContextProvider {
  getHostContext?: () => common.UIAbilityContext;
}

export class ContextUtils {
  static getAbilityContext(context: Object): common.UIAbilityContext {
    const contextWithHost = context as HostContextProvider;
    if (contextWithHost && contextWithHost.getHostContext) {
      return contextWithHost.getHostContext();
    }
    return context as common.UIAbilityContext;
  }
}
