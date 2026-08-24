import { SettingsRepository } from '../../repository/SettingsRepository'

/**
 * 助手后端接入点统一配置。
 * 所有访问 AI 后端（ai-proxy）的模块（对话流、工具回传、教务检索、视觉解析等）
 * 一律从这里取地址与密钥，禁止再读 AppConstants 默认值或散落硬编码请求头；
 * 地址与密钥由用户在「我的 - 应用设置 - 助手后端」中配置，持久化于 preferences。
 */

/** resolve() 的结构化结果：已归一化的地址 / 密钥 + 缺失项标记 */
export interface AgentEndpoint {
  /** 归一化后的基础地址（trim 且去尾部斜杠），未配置时为空串 */
  baseUrl: string
  /** 归一化后的访问密钥（trim），未配置时为空串 */
  proxyKey: string
  /** 后端地址是否缺失 */
  urlMissing: boolean
  /** 访问密钥是否缺失 */
  keyMissing: boolean
}

export class AgentEndpointConfig {
  static readonly STORAGE_KEY_CONFIGURED: string = 'agent_backend_configured';

  /**
   * 同步当前后端配置就绪状态至 AppStorage，供各组件响应式绑定
   */
  static async syncConfiguredState(context: Context): Promise<boolean> {
    const endpoint: AgentEndpoint = await AgentEndpointConfig.resolve(context);
    const ready: boolean = AgentEndpointConfig.isReady(endpoint);
    AppStorage.setOrCreate(AgentEndpointConfig.STORAGE_KEY_CONFIGURED, ready);
    return ready;
  }

  /**
   * 从设置读取并归一化地址与密钥，永不抛出；
   * 读偏好异常时按"全部缺失"处理，由调用方走引导 / 报错路径。
   */
  static async resolve(context: Context): Promise<AgentEndpoint> {
    let rawUrl: string = ''
    let rawKey: string = ''
    try {
      rawUrl = await SettingsRepository.getAgentBackendUrl(context)
      rawKey = await SettingsRepository.getAgentProxyKey(context)
    } catch (e) {
      console.error('[AgentEndpointConfig] resolve error:', String(e))
    }
    const baseUrl: string = AgentEndpointConfig.normalizeBaseUrl(rawUrl)
    const proxyKey: string = rawKey.trim()
    const result: AgentEndpoint = {
      baseUrl: baseUrl,
      proxyKey: proxyKey,
      urlMissing: baseUrl.length === 0,
      keyMissing: proxyKey.length === 0
    }
    return result
  }

  /** 是否已具备调用后端的最低条件（地址与密钥均已配置） */
  static isReady(endpoint: AgentEndpoint): boolean {
    return !endpoint.urlMissing && !endpoint.keyMissing
  }

  /** 缺失项的友好中文提示；配置齐全时返回空串 */
  static missingHint(endpoint: AgentEndpoint): string {
    if (endpoint.urlMissing && endpoint.keyMissing) {
      return 'AI 助手后端尚未配置：请先在「我的 - 应用设置 - 助手后端」填写后端地址与访问密钥。'
    }
    if (endpoint.urlMissing) {
      return 'AI 助手后端地址未配置：请先在「我的 - 应用设置 - 助手后端」填写后端地址。'
    }
    if (endpoint.keyMissing) {
      return 'AI 助手访问密钥未配置：请先在「我的 - 应用设置 - 助手后端」填写访问密钥。'
    }
    return ''
  }

  /** 构造带鉴权的通用请求头（含 x-proxy-key）；时间戳、Accept 等额外头由调用方自行追加 */
  static buildHeaders(endpoint: AgentEndpoint): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'x-proxy-key': endpoint.proxyKey
    }
    return headers
  }

  /** 拼接子路径：归一化地址 + '/' + 相对路径（如 api/chat、health），相对路径可带查询串 */
  static joinUrl(endpoint: AgentEndpoint, subPath: string): string {
    return `${endpoint.baseUrl}/${subPath.replace(/^\/+/, '')}`
  }

  /** 地址归一化：trim 并去掉尾部所有斜杠 */
  private static normalizeBaseUrl(raw: string): string {
    let url: string = raw.trim()
    while (url.length > 0 && url.endsWith('/')) {
      url = url.substring(0, url.length - 1)
    }
    return url
  }
}
