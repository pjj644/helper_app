import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { ToolExecutor, ToolResult } from './ToolExecutor'
import { AppConstants } from '../constants/AppConstants'
import { SettingsRepository } from '../../repository/SettingsRepository'

import { AgentTelemetryInfo } from '../../repository/ChatSessionRepository'

// 从 AgentOrchestrator.ets 迁入，签名不变 -> AssistantPage 回调实现一字不改
export interface AgentCallbacks {
  onToolCallStart: (toolName: string, args: string) => void
  onToolCallResult: (toolName: string, result: string, success: boolean) => void
  onConfirmationNeeded: (toolName: string, args: string) => Promise<boolean>
  onTextChunk: (chunk: string) => void
  onError: (error: string) => void
  onComplete: (telemetry?: AgentTelemetryInfo) => void
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

/**
 * 薄客户端：替代 AgentOrchestrator。
 * 把对话发给后端 LangGraph Agent，收 typed SSE 事件流，路由到 AgentCallbacks；
 * 收到 tool_call 事件时本地执行 ToolExecutor（含确认弹窗），再 POST /api/tool-result 回传。
 * LLM 推理、工具调度、提示词全在后端；手机只做展示 + 工具执行。
 */
export class BackendAgentClient {
  private context: Context
  private executor: ToolExecutor
  private callbacks: AgentCallbacks
  private isCancelled: boolean = false
  private finished: boolean = false
  private currentRequest: http.HttpRequest | null = null
  private buffer: string = ''

  constructor(context: Context, executor: ToolExecutor, callbacks: AgentCallbacks) {
    this.context = context
    this.executor = executor
    this.callbacks = callbacks
  }

  cancel(): void {
    this.isCancelled = true
    if (this.currentRequest !== null) {
      this.currentRequest.destroy()
      this.currentRequest = null
    }
  }

  async run(sessionId: string, history: AgentMessage[]): Promise<void> {
    this.isCancelled = false
    this.finished = false
    this.buffer = ''

    const last: AgentMessage | undefined = history[history.length - 1]
    const message: string = (last && last.content) ? last.content : ''

    // 后端地址从设置读取，AppConstants 作默认回退
    let baseUrl: string = AppConstants.AI_AGENT_URL
    try {
      baseUrl = await SettingsRepository.getAgentBackendUrl(this.context)
    } catch (e) {
      // 用默认
    }
    if (!baseUrl.endsWith('/')) {
      baseUrl = baseUrl + '/'
    }
    const chatUrl: string = baseUrl + AppConstants.AI_CHAT_PATH
    const toolResultUrl: string = baseUrl + AppConstants.AI_TOOL_RESULT_PATH

    const httpRequest: http.HttpRequest = http.createHttp()
    this.currentRequest = httpRequest

    httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
      const opts: DecodeOptions = { stream: true }
      const chunk: string = decoder.decodeWithStream(new Uint8Array(data), opts)
      this.buffer += chunk
      let idx: number = this.buffer.indexOf('\n\n')
      while (idx !== -1) {
        const raw: string = this.buffer.substring(0, idx)
        this.buffer = this.buffer.substring(idx + 2)
        this.handleEvent(raw, sessionId, toolResultUrl)
        idx = this.buffer.indexOf('\n\n')
      }
    })

    httpRequest.on('dataEnd', () => {
      if (this.buffer.length > 0) {
        this.handleEvent(this.buffer, sessionId, toolResultUrl)
        this.buffer = ''
      }
      this.currentRequest = null
      // 兜底：流结束但没收到 final/error，按完成处理
      this.finish(false, '')
    })

    httpRequest.requestInStream(chatUrl, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'X-Proxy-Key': AppConstants.AI_AGENT_KEY,
        'Accept': 'text/event-stream'
      },
      extraData: JSON.stringify({ session_id: sessionId, message: message }),
      connectTimeout: 10000,
      readTimeout: 120000
    }).then((responseCode: number) => {
      if (responseCode !== 200 && !this.finished) {
        this.finish(true, `后端返回错误码 ${responseCode}（请检查后端地址与密钥）`)
      }
    }).catch((err: Error) => {
      if (this.isCancelled) {
        this.finish(false, '')
      } else {
        this.finish(true, `无法连接助手后端：${String(err)}。请确认电脑已开机且在同一 WiFi，地址在"应用设置-助手后端"中配置。`)
      }
    })
  }

  private finish(isError: boolean, msg: string, telemetry?: AgentTelemetryInfo): void {
    if (this.finished) {
      return
    }
    this.finished = true
    if (isError) {
      this.callbacks.onError(msg)
    } else {
      this.callbacks.onComplete(telemetry)
    }
  }

  private handleEvent(raw: string, sessionId: string, toolResultUrl: string): void {
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
        continue
      }
      const type: string = (evt['type'] as string) || ''
      if (type === 'text_chunk') {
        const content: string = (evt['content'] as string) || ''
        if (content.length > 0) {
          this.callbacks.onTextChunk(content)
        }
      } else if (type === 'tool_call') {
        const batchId: string = (evt['batch_id'] as string) || ''
        const toolCallsRaw: Object[] = (evt['tool_calls'] as Object[]) || []
        this.fireAndForget(this.handleToolCall(sessionId, batchId, toolCallsRaw, toolResultUrl))
      } else if (type === 'final') {
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
        this.finish(true, (evt['message'] as string) || '未知错误')
      }
    }
  }

  private fireAndForget(p: Promise<void>): void {
    p.catch((e: Error) => {
      console.error('[BackendAgentClient] async error:', String(e))
    })
  }

  private async handleToolCall(sessionId: string, batchId: string, toolCallsRaw: Object[], toolResultUrl: string): Promise<void> {
    const results: ToolResultOut[] = []
    for (let i = 0; i < toolCallsRaw.length; i++) {
      if (this.isCancelled) {
        break
      }
      const tcRaw: Record<string, Object> = toolCallsRaw[i] as Record<string, Object>
      const toolCallId: string = (tcRaw['tool_call_id'] as string) || ''
      const name: string = (tcRaw['name'] as string) || ''
      const args: Record<string, Object> = (tcRaw['args'] as Record<string, Object>) || {}
      const requiresConfirmation: boolean = (tcRaw['requiresConfirmation'] as boolean) || false

      const argsStr: string = JSON.stringify(args)
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
    await this.postToolResult(toolResultUrl, sessionId, batchId, results)
  }

  private async postToolResult(url: string, sessionId: string, batchId: string, results: ToolResultOut[]): Promise<void> {
    try {
      const req: http.HttpRequest = http.createHttp()
      await req.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'X-Proxy-Key': AppConstants.AI_AGENT_KEY
        },
        extraData: JSON.stringify({ session_id: sessionId, batch_id: batchId, results: results }),
        connectTimeout: 10000,
        readTimeout: 15000
      })
      req.destroy()
    } catch (e) {
      console.error('[BackendAgentClient] postToolResult error:', String(e))
    }
  }
}
