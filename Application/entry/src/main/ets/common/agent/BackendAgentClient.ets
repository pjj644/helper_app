import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { ToolExecutor, ToolResult } from './ToolExecutor'
import { ToolRegistry } from './ToolRegistry'
import { AppConstants } from '../constants/AppConstants'
import { AgentEndpointConfig, AgentEndpoint } from './AgentEndpointConfig'

import { AgentTelemetryInfo } from '../../repository/ChatSessionRepository'

// 从 AgentOrchestrator.ets 迁入，签名不变 -> AssistantPage 回调实现一字不改
// T3 追加两个可选回调（onIncomplete / onInterrupted）：旧实现不实现可选成员即可照常工作
export interface AgentCallbacks {
  onToolCallStart: (toolName: string, args: string) => void
  onToolCallResult: (toolName: string, result: string, success: boolean) => void
  onConfirmationNeeded: (toolName: string, args: string) => Promise<boolean>
  onTextChunk: (chunk: string) => void
  onThoughtChunk?: (chunk: string) => void
  onStatusChange?: (status: string, message: string) => void
  onError: (error: string) => void
  onComplete: (telemetry?: AgentTelemetryInfo) => void
  /** 可选：流干净结束但缺 final 帧（completed_with_warning），message 为「回复可能不完整」类轻提示文案 */
  onIncomplete?: (message: string) => void
  /** 可选：已收到部分内容后流中断（传输层断开，或已有正文时收到 error 帧），页面应保留已收内容并提供「重新发送」入口 */
  onInterrupted?: (message: string) => void
}

export interface AgentMessage {
  role: string
  content: string | null
}

interface ToolResultOut {
  tool_call_id: string
  success: boolean
  data: string
}

interface DecodeOptions {
  stream: boolean
}

/** 一次对话连接任务的参数包：多次重试共用同一份目标信息 */
interface ConnectJob {
  /** 发起本次 run 的代次号，用于让遗留异步回调失效 */
  seq: number
  sessionId: string
  message: string
  chatUrl: string
  toolResultUrl: string
  endpoint: AgentEndpoint
}

/**
 * 薄客户端：替代 AgentOrchestrator。
 * 把对话发给后端 LangGraph Agent，收 typed SSE 事件流，路由到 AgentCallbacks；
 * 收到 tool_call 事件时本地执行 ToolExecutor（含确认弹窗），再 POST /api/tool-result 回传。
 * LLM 推理、工具调度、提示词全在后端；手机只做展示 + 工具执行。
 *
 * T3 连接可靠性语义：
 * 1. 首包 watchdog：发起连接后 45s 内未收到任何事件 → 主动 abort，按「首事件前失败」处理；
 * 2. 首事件前失败（拒连 / watchdog 触发 / 服务端 5xx）→ 指数退避自动重试 2 次（1s、3s），
 *    期间经 onStatusChange 上报「连接中(第 N 次)」，3 次全败才报网络错误；
 * 3. 已收到事件后流中断（RST / 截断 / 异常关闭，无 final 无 error）→ onInterrupted 中断态，
 *    由页面保留已收内容并提供「重新发送」（同 session_id 借后端 checkpoint 幂等续接）；
 * 4. 流干净 FIN 但缺 final 帧 → onIncomplete（completed_with_warning），不当作完全成功也不进错误态；
 * 5. tool-result 回传失败 → 本地重试 2 次（0.5s、2s），三次均失败经 onError 报错并复位会话状态。
 */
export class BackendAgentClient {
  // 可靠性参数已收归 AppConstants（AI_FIRST_PACKET_WATCHDOG_MS / AI_CONNECT_RETRY_DELAYS_MS / AI_TOOL_RESULT_RETRY_DELAYS_MS）
  /** 缺 final 帧时的统一轻提示文案 */
  private static readonly INCOMPLETE_HINT: string = '回复可能不完整'
  /** 首事件前失败重试耗尽后的公共提示后缀 */
  private static readonly RETRY_EXHAUSTED_SUFFIX: string =
    '（已自动重试 2 次仍未成功）。请确认电脑已开机且在同一 WiFi，并在"我的-应用设置-助手后端"检查地址与密钥。'

  private context: Context
  private executor: ToolExecutor
  private callbacks: AgentCallbacks
  private isCancelled: boolean = false
  private finished: boolean = false
  private currentRequest: http.HttpRequest | null = null
  private buffer: string = ''
  /** 本次 run 的代次号：新 run / cancel 时自增，使遗留异步回调（重试定时器、sleep 循环）失效 */
  private runSeq: number = 0
  /** 是否已收到至少一个有效 SSE 事件（决定失败走「自动重试」还是「中断态」） */
  private hasReceivedEvent: boolean = false
  /** 是否已收到 final 帧（区分正常完成 / 缺 final 警告） */
  private receivedFinal: boolean = false
  /** 是否已向页面流出过正文或思维链内容（决定 error 帧按普通错误还是中断态处理） */
  private hasStreamedContent: boolean = false
  /** 已执行的自动重试次数（0 表示首次尝试） */
  private retryCount: number = 0
  /** 当前这次连接尝试是否已有结论（防 watchdog 与请求异常双重触发同一失败路径） */
  private attemptSettled: boolean = false
  /** 首包 watchdog 定时器句柄 */
  private watchdogTimerId: number = -1
  /** 连接重试定时器句柄 */
  private retryTimerId: number = -1

  constructor(context: Context, executor: ToolExecutor, callbacks: AgentCallbacks) {
    this.context = context
    this.executor = executor
    this.callbacks = callbacks
  }

  /**
   * 取消本轮对话：清理 watchdog 与重试定时器、销毁在途请求。
   * 用户新发消息 / 新建会话 / 离开页面时应调用。
   */
  cancel(): void {
    this.isCancelled = true
    this.runSeq++
    this.clearWatchdog()
    this.clearRetryTimer()
    this.destroyCurrentRequest()
  }

  async run(sessionId: string, history: AgentMessage[]): Promise<void> {
    this.runSeq++
    const seq: number = this.runSeq
    this.isCancelled = false
    this.finished = false
    this.buffer = ''
    this.hasReceivedEvent = false
    this.receivedFinal = false
    this.hasStreamedContent = false
    this.retryCount = 0

    const last: AgentMessage | undefined = history[history.length - 1]
    const message: string = (last && last.content) ? last.content : ''

    // 后端地址与密钥统一从设置读取（归一化），缺失时直接走错误回调引导用户去配置
    const endpoint: AgentEndpoint = await AgentEndpointConfig.resolve(this.context)
    if (seq !== this.runSeq || this.isCancelled) {
      return
    }
    if (!AgentEndpointConfig.isReady(endpoint)) {
      this.finish(true, AgentEndpointConfig.missingHint(endpoint))
      return
    }

    const job: ConnectJob = {
      seq: seq,
      sessionId: sessionId,
      message: message,
      chatUrl: AgentEndpointConfig.joinUrl(endpoint, AppConstants.AI_CHAT_PATH),
      toolResultUrl: AgentEndpointConfig.joinUrl(endpoint, AppConstants.AI_TOOL_RESULT_PATH),
      endpoint: endpoint
    }
    this.attemptConnect(job)
  }

  /** 发起一次连接尝试（SSE 流式）；首事件前的失败统一交 handlePreEventFailure 调度重试 */
  private attemptConnect(job: ConnectJob): void {
    if (job.seq !== this.runSeq || this.isCancelled || this.finished) {
      return
    }
    this.attemptSettled = false
    this.buffer = ''

    const httpRequest: http.HttpRequest = http.createHttp()
    this.currentRequest = httpRequest
    const sessionId: string = job.sessionId
    const toolResultUrl: string = job.toolResultUrl
    const endpoint: AgentEndpoint = job.endpoint

    httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      if (job.seq !== this.runSeq) {
        return
      }
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
      const opts: DecodeOptions = { stream: true }
      const chunk: string = decoder.decodeWithStream(new Uint8Array(data), opts)
      this.buffer += chunk
      let idx: number = this.buffer.indexOf('\n\n')
      while (idx !== -1) {
        const raw: string = this.buffer.substring(0, idx)
        this.buffer = this.buffer.substring(idx + 2)
        this.handleEvent(raw, sessionId, toolResultUrl, endpoint)
        idx = this.buffer.indexOf('\n\n')
      }
    })

    httpRequest.on('dataEnd', () => {
      if (job.seq !== this.runSeq || this.attemptSettled) {
        return
      }
      this.clearWatchdog()
      if (this.buffer.length > 0) {
        const tail: string = this.buffer
        this.buffer = ''
        this.handleEvent(tail, sessionId, toolResultUrl, endpoint)
      }
      this.destroyCurrentRequest()
      if (this.receivedFinal) {
        // final 帧已在 handleEvent 中正常收尾
        return
      }
      if (this.hasReceivedEvent) {
        // 场景(missing-final)：流干净结束但缺 final 帧 → completed_with_warning 轻提示，不进错误态
        this.completeWithWarning()
      } else {
        // 一个有效事件都没收到就被服务端关闭 → 视作「首事件前失败」，进入退避重试
        this.settleAttempt()
        this.handlePreEventFailure(job, '连接已被服务端关闭且未返回任何数据')
      }
    })

    const timestampStr: string = Date.now().toString()
    const nonceStr: string = 'nonce_' + Date.now() + '_' + Math.floor(Math.random() * 100000)

    // 鉴权头统一由 AgentEndpointConfig 构造，这里只追加流式请求的额外头
    const requestHeaders: Record<string, string> = AgentEndpointConfig.buildHeaders(endpoint)
    requestHeaders['X-Timestamp'] = timestampStr
    requestHeaders['X-Nonce'] = nonceStr
    requestHeaders['Accept'] = 'text/event-stream'

    // 武装首包 watchdog：45s 内无任何事件则主动 abort，按「首事件前失败」处理
    this.armWatchdog(job)

    httpRequest.requestInStream(job.chatUrl, {
      method: http.RequestMethod.POST,
      header: requestHeaders,
      extraData: JSON.stringify({ session_id: job.sessionId, message: job.message }),
      connectTimeout: 10000,
      readTimeout: 120000
    }).then((responseCode: number) => {
      if (job.seq !== this.runSeq || this.finished) {
        return
      }
      if (responseCode !== 200) {
        // 本次尝试立即定论，避免 watchdog 之后再次触发
        this.settleAttempt()
        this.destroyCurrentRequest()
        if (responseCode >= 500 || responseCode === 429) {
          // 服务端瞬时故障 → 按「首事件前失败」走退避重试
          this.handlePreEventFailure(job, `后端返回错误码 ${responseCode}`)
        } else {
          // 401/403/404 等配置类问题，重试无意义 → 直接报错引导检查配置
          this.finish(true, `后端返回错误码 ${responseCode}（请检查后端地址与密钥）`)
        }
      }
    }).catch((err: Error) => {
      if (job.seq !== this.runSeq) {
        return
      }
      this.destroyCurrentRequest()
      if (this.isCancelled) {
        // 用户主动取消：页面自行复位，不再回调
        return
      }
      if (this.attemptSettled) {
        // watchdog（或非 200 分支）已先行 abort 定论，此处仅是 abort 引发的异常，避免重复处理
        return
      }
      this.settleAttempt()
      if (this.hasReceivedEvent) {
        // 场景(mid-stream-reset)：已收到事件后传输层异常中断（RST/截断/异常关闭）→ 中断态
        this.markInterrupted('网络连接中断，回复未完成')
      } else {
        this.handlePreEventFailure(job, `无法连接助手后端：${String(err)}`)
      }
    })
  }

  /**
   * 「首事件前失败」统一入口：尚未收到任何事件时的连接失败 / watchdog 触发 / 服务端 5xx。
   * 指数退避自动重试 2 次（1s、3s），重试期间经 onStatusChange 让 UI 显示「连接中(第 N 次)」；
   * 3 次全败才报网络错误（不得白屏 / 卡死在 loading 态）。
   */
  private handlePreEventFailure(job: ConnectJob, reason: string): void {
    if (job.seq !== this.runSeq || this.isCancelled || this.finished) {
      return
    }
    if (this.retryCount < AppConstants.AI_CONNECT_RETRY_DELAYS_MS.length) {
      const delayMs: number = AppConstants.AI_CONNECT_RETRY_DELAYS_MS[this.retryCount]
      this.retryCount++
      if (this.callbacks.onStatusChange) {
        this.callbacks.onStatusChange('connecting_retry', `连接中(第 ${this.retryCount} 次)...`)
      }
      this.clearRetryTimer()
      this.retryTimerId = setTimeout(() => {
        this.retryTimerId = -1
        this.attemptConnect(job)
      }, delayMs)
      return
    }
    this.finish(true, `${reason}${BackendAgentClient.RETRY_EXHAUSTED_SUFFIX}`)
  }

  /** 武装首包 watchdog：到期未收到任何事件则主动 abort 本次连接 */
  private armWatchdog(job: ConnectJob): void {
    this.clearWatchdog()
    this.watchdogTimerId = setTimeout(() => {
      this.watchdogTimerId = -1
      if (job.seq !== this.runSeq || this.finished || this.hasReceivedEvent || this.attemptSettled) {
        return
      }
      this.settleAttempt()
      this.destroyCurrentRequest()
      this.handlePreEventFailure(job, `连接超时：服务器 ${Math.round(AppConstants.AI_FIRST_PACKET_WATCHDOG_MS / 1000)} 秒内未返回任何数据`)
    }, AppConstants.AI_FIRST_PACKET_WATCHDOG_MS)
  }

  /** 本次连接尝试定论：置标志并撤掉 watchdog，保证失败路径只走一次 */
  private settleAttempt(): void {
    this.attemptSettled = true
    this.clearWatchdog()
  }

  /** 缺 final 帧：先轻提示再按完成收尾（内容照常展示、不进错误态、不触发重试风暴） */
  private completeWithWarning(): void {
    if (this.finished) {
      return
    }
    if (this.callbacks.onIncomplete) {
      this.callbacks.onIncomplete(BackendAgentClient.INCOMPLETE_HINT)
    }
    this.finish(false, '')
  }

  /**
   * 中断态收尾：只通知页面（保留已收内容、提供「重新发送」入口），
   * 刻意不触发 onComplete —— 否则半截回复会被写入消息历史，重发续接后会重复入库。
   */
  private markInterrupted(message: string): void {
    if (this.finished) {
      return
    }
    this.finished = true
    this.clearWatchdog()
    this.clearRetryTimer()
    this.destroyCurrentRequest()
    if (this.callbacks.onInterrupted) {
      this.callbacks.onInterrupted(message)
    }
  }

  private finish(isError: boolean, msg: string, telemetry?: AgentTelemetryInfo): void {
    if (this.finished) {
      return
    }
    this.finished = true
    this.clearWatchdog()
    this.clearRetryTimer()
    this.destroyCurrentRequest()
    if (isError) {
      this.callbacks.onError(msg)
    } else {
      this.callbacks.onComplete(telemetry)
    }
  }

  private handleEvent(raw: string, sessionId: string, toolResultUrl: string, endpoint: AgentEndpoint): void {
    if (this.finished) {
      return
    }
    const lines: string[] = raw.split('\n')
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim()
      if (!line.startsWith('data:')) {
        continue
      }
      const jsonStr: string = line.substring(5).trim()
      if (jsonStr.length === 0) {
        continue
      }
      let evt: Record<string, Object>
      try {
        evt = JSON.parse(jsonStr) as Record<string, Object>
      } catch (e) {
        // 场景(mid-stream-reset)：容忍残缺/非法 JSON 行，跳过而不崩溃
        continue
      }
      const type: string = (evt['type'] as string) || ''
      if (type.length > 0 && !this.hasReceivedEvent) {
        // 收到第一个有效事件：解除首包 watchdog，此后断开不再走「自动重试」而是「中断态」
        this.hasReceivedEvent = true
        this.clearWatchdog()
      }
      if (type === 'text_chunk') {
        const content: string = (evt['content'] as string) || ''
        if (content.length > 0) {
          this.hasStreamedContent = true
          this.callbacks.onTextChunk(content)
        }
      } else if (type === 'thought_chunk' || type === 'thinking_chunk') {
        const content: string = (evt['content'] as string) || ''
        if (content.length > 0 && this.callbacks.onThoughtChunk) {
          this.hasStreamedContent = true
          this.callbacks.onThoughtChunk(content)
        }
      } else if (type === 'status') {
        const status: string = (evt['status'] as string) || ''
        const message: string = (evt['message'] as string) || ''
        if (this.callbacks.onStatusChange) {
          this.callbacks.onStatusChange(status, message)
        }
      } else if (type === 'tool_call') {
        const batchId: string = (evt['batch_id'] as string) || ''
        const toolCallsRaw: Object[] = (evt['tool_calls'] as Object[]) || []
        this.fireAndForget(this.handleToolCall(sessionId, batchId, toolCallsRaw, toolResultUrl, endpoint))
      } else if (type === 'final') {
        this.receivedFinal = true
        let telemetry: AgentTelemetryInfo | undefined = undefined
        if (evt['telemetry']) {
          const tRaw: Record<string, Object> = evt['telemetry'] as Record<string, Object>
          telemetry = {
            totalTokens: Number(tRaw['total_tokens'] || 0),
            promptTokens: Number(tRaw['prompt_tokens'] || 0),
            completionTokens: Number(tRaw['completion_tokens'] || 0),
            durationMs: Number(tRaw['duration_ms'] || 0),
            ttftMs: Number(tRaw['ttft_ms'] || 0),
          }
        }
        this.finish(false, '', telemetry)
      } else if (type === 'error') {
        const errMsg: string = (evt['message'] as string) || '未知错误'
        if (this.hasStreamedContent) {
          // 场景(mid-stream-error)：已有部分正文时收到 error 帧 → 按「已收内容后中断」处理：
          // 保留已收内容、标记中断态并提供「重新发送」，不清空已有文本
          this.markInterrupted(errMsg)
        } else {
          this.finish(true, errMsg)
        }
      }
    }
  }

  private fireAndForget(p: Promise<void>): void {
    p.catch((e: Error) => {
      console.error('[BackendAgentClient] async error:', String(e))
    })
  }

  private async handleToolCall(sessionId: string, batchId: string, toolCallsRaw: Object[], toolResultUrl: string, endpoint: AgentEndpoint): Promise<void> {
    const results: ToolResultOut[] = []
    for (let i = 0; i < toolCallsRaw.length; i++) {
      if (this.isCancelled) {
        break
      }
      const tcRaw: Record<string, Object> = toolCallsRaw[i] as Record<string, Object>
      const toolCallId: string = (tcRaw['tool_call_id'] as string) || ''
      const name: string = (tcRaw['name'] as string) || ''
      const args: Record<string, Object> = (tcRaw['args'] as Record<string, Object>) || {}
      const argsStr: string = JSON.stringify(args)
      // 确认闸门取「后端下发 ∨ 端侧注册表」并集（fail-closed）：
      // 未注册工具经 ToolRegistry 哨兵强制要求确认，防止后端显式下发 false 造成旁路（阻塞表 B-04）。
      const backendRequires: boolean = (tcRaw['requiresConfirmation'] as boolean) || false
      const requiresConfirmation: boolean = backendRequires || ToolRegistry.requiresConfirmation(name, argsStr)
      this.callbacks.onToolCallStart(name, argsStr)

      let result: ToolResult
      if (requiresConfirmation) {
        const confirmed: boolean = await this.callbacks.onConfirmationNeeded(name, argsStr)
        if (!confirmed) {
          this.callbacks.onToolCallResult(name, '用户拒绝了此操作', false)
          results.push({ tool_call_id: toolCallId, success: false, data: '用户拒绝了此操作' })
          continue
        }
      }
      result = await this.executor.execute(name, args)
      const resultContent: string = result.success ? result.data : `错误: ${result.data}`
      this.callbacks.onToolCallResult(name, resultContent, result.success)
      results.push({ tool_call_id: toolCallId, success: result.success, data: result.data })
    }

    if (this.isCancelled) {
      return
    }
    await this.postToolResult(toolResultUrl, sessionId, batchId, results, endpoint)
  }

  /**
   * 回传工具执行结果：POST 失败本地重试 2 次（间隔 0.5s、2s，对应线级场景 tool-result-fail）；
   * 任一次成功 → 对话继续走完至 final，用户无感；
   * 三次均失败 → 经 onError 明确报错，页面据此解锁输入框、复位会话状态，
   * 不再依赖后端 interrupt 超时导致对话悬挂。
   */
  private async postToolResult(url: string, sessionId: string, batchId: string, results: ToolResultOut[], endpoint: AgentEndpoint): Promise<void> {
    const seq: number = this.runSeq
    for (let attempt: number = 0; attempt <= AppConstants.AI_TOOL_RESULT_RETRY_DELAYS_MS.length; attempt++) {
      if (this.isCancelled || seq !== this.runSeq || this.finished) {
        return
      }
      try {
        const req: http.HttpRequest = http.createHttp()
        const resp: http.HttpResponse = await req.request(url, {
          method: http.RequestMethod.POST,
          header: AgentEndpointConfig.buildHeaders(endpoint),
          extraData: JSON.stringify({ session_id: sessionId, batch_id: batchId, results: results }),
          connectTimeout: 10000,
          readTimeout: 15000
        })
        req.destroy()
        if (resp.responseCode >= 200 && resp.responseCode < 300) {
          return
        }
        console.error(`[BackendAgentClient] postToolResult HTTP ${resp.responseCode}（第 ${attempt + 1} 次尝试）`)
      } catch (e) {
        console.error(`[BackendAgentClient] postToolResult error（第 ${attempt + 1} 次尝试）:`, String(e))
      }
      if (attempt < AppConstants.AI_TOOL_RESULT_RETRY_DELAYS_MS.length) {
        await this.sleep(AppConstants.AI_TOOL_RESULT_RETRY_DELAYS_MS[attempt])
      }
    }
    this.finish(true, '工具结果回传失败（已自动重试 2 次仍未成功），本轮对话已中止，请重新发送。')
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve()
      }, ms)
    })
  }

  private destroyCurrentRequest(): void {
    if (this.currentRequest !== null) {
      try {
        this.currentRequest.destroy()
      } catch (e) {
        // 请求对象可能已被网络栈销毁，忽略二次销毁异常
      }
      this.currentRequest = null
    }
  }

  private clearWatchdog(): void {
    if (this.watchdogTimerId !== -1) {
      clearTimeout(this.watchdogTimerId)
      this.watchdogTimerId = -1
    }
  }

  private clearRetryTimer(): void {
    if (this.retryTimerId !== -1) {
      clearTimeout(this.retryTimerId)
      this.retryTimerId = -1
    }
  }
}
