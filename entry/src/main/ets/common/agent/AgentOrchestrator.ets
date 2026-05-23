import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { ToolRegistry } from './ToolRegistry'
import { ToolExecutor, ToolResult } from './ToolExecutor'
import { AppConstants } from '../constants/AppConstants'

export interface ToolCallInfo {
  id: string
  name: string
  arguments: string
}

interface ApiToolCallFunction {
  name: string
  arguments: string
}

interface ApiToolCall {
  id: string
  type: string
  function: ApiToolCallFunction
}

export interface AgentCallbacks {
  onToolCallStart: (toolName: string, args: string) => void
  onToolCallResult: (toolName: string, result: string, success: boolean) => void
  onConfirmationNeeded: (toolName: string, args: string) => Promise<boolean>
  onTextChunk: (chunk: string) => void
  onError: (error: string) => void
  onComplete: () => void
}

export interface AgentMessage {
  role: string
  content: string | null
  reasoning_content?: string | null
  tool_calls?: Object[]
  tool_call_id?: string
}

const MODEL: string = 'deepseek-v4-flash'
const MAX_TOOL_ROUNDS: number = 5

export class AgentOrchestrator {
  private executor: ToolExecutor
  private callbacks: AgentCallbacks
  private isCancelled: boolean = false

  constructor(executor: ToolExecutor, callbacks: AgentCallbacks) {
    this.executor = executor
    this.callbacks = callbacks
  }

  cancel(): void {
    this.isCancelled = true
  }

  async run(systemPrompt: string, history: AgentMessage[]): Promise<void> {
    this.isCancelled = false
    const agentMessages: AgentMessage[] = [{ role: 'system', content: systemPrompt }]
    for (let i = 0; i < history.length; i++) {
      agentMessages.push(history[i])
    }

    for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
      if (this.isCancelled) {
        this.callbacks.onComplete()
        return
      }

      const response: AgentResponse | null = await this.callAPI(agentMessages)
      if (!response) {
        this.callbacks.onError('API调用失败')
        return
      }

      if (response.toolCalls && response.toolCalls.length > 0) {
        const assistantMsg: AgentMessage = {
          role: 'assistant',
          content: response.textContent || null,
          reasoning_content: response.reasoningContent || null,
          tool_calls: this.toApiToolCalls(response.toolCalls)
        }
        agentMessages.push(assistantMsg)

        if (response.textContent && response.textContent.length > 0) {
          this.callbacks.onTextChunk(response.textContent)
        }

        for (let i = 0; i < response.toolCalls.length; i++) {
          if (this.isCancelled) {
            this.callbacks.onComplete()
            return
          }

          const tc: ToolCallInfo = response.toolCalls[i] as ToolCallInfo
          this.callbacks.onToolCallStart(tc.name, tc.arguments)

          const needsConfirm: boolean = ToolRegistry.requiresConfirmation(tc.name)
          if (needsConfirm) {
            const confirmed: boolean = await this.callbacks.onConfirmationNeeded(tc.name, tc.arguments)
            if (!confirmed) {
              const rejectMsg: AgentMessage = {
                role: 'tool',
                tool_call_id: tc.id,
                content: '用户拒绝了此操作'
              }
              agentMessages.push(rejectMsg)
              this.callbacks.onToolCallResult(tc.name, '用户拒绝了此操作', false)
              continue
            }
          }

          let args: Record<string, Object> = {}
          try {
            if (tc.arguments && tc.arguments.length > 0) {
              args = JSON.parse(tc.arguments) as Record<string, Object>
            }
          } catch (e) {
            args = {}
          }

          const result: ToolResult = await this.executor.execute(tc.name, args)
          const resultContent: string = result.success ? result.data : `错误: ${result.data}`
          this.callbacks.onToolCallResult(tc.name, resultContent, result.success)

          const toolMsg: AgentMessage = {
            role: 'tool',
            tool_call_id: tc.id,
            content: resultContent
          }
          agentMessages.push(toolMsg)
        }
      } else {
        if (response.textContent && response.textContent.length > 0) {
          this.callbacks.onTextChunk(response.textContent)
        }
        this.callbacks.onComplete()
        return
      }
    }

    this.callbacks.onTextChunk('\n\n[已达到最大工具调用轮次限制]')
    this.callbacks.onComplete()
  }

  async runStream(systemPrompt: string, history: AgentMessage[]): Promise<void> {
    this.isCancelled = false
    const agentMessages: AgentMessage[] = [{ role: 'system', content: systemPrompt }]
    for (let i = 0; i < history.length; i++) {
      agentMessages.push(history[i])
    }

    for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
      if (this.isCancelled) {
        this.callbacks.onComplete()
        return
      }

      const response: AgentResponse | null = await this.callAPIStream(agentMessages)
      if (!response) {
        this.callbacks.onError('API调用失败')
        return
      }

      if (response.toolCalls && response.toolCalls.length > 0) {
        const assistantMsg: AgentMessage = {
          role: 'assistant',
          content: response.textContent || null,
          reasoning_content: response.reasoningContent || null,
          tool_calls: this.toApiToolCalls(response.toolCalls)
        }
        agentMessages.push(assistantMsg)

        for (let i = 0; i < response.toolCalls.length; i++) {
          if (this.isCancelled) {
            this.callbacks.onComplete()
            return
          }

          const tc: ToolCallInfo = response.toolCalls[i] as ToolCallInfo
          this.callbacks.onToolCallStart(tc.name, tc.arguments)

          const needsConfirm: boolean = ToolRegistry.requiresConfirmation(tc.name)
          if (needsConfirm) {
            const confirmed: boolean = await this.callbacks.onConfirmationNeeded(tc.name, tc.arguments)
            if (!confirmed) {
              const rejectMsg: AgentMessage = {
                role: 'tool',
                tool_call_id: tc.id,
                content: '用户拒绝了此操作'
              }
              agentMessages.push(rejectMsg)
              this.callbacks.onToolCallResult(tc.name, '用户拒绝了此操作', false)
              continue
            }
          }

          let args: Record<string, Object> = {}
          try {
            if (tc.arguments && tc.arguments.length > 0) {
              args = JSON.parse(tc.arguments) as Record<string, Object>
            }
          } catch (e) {
            args = {}
          }

          const result: ToolResult = await this.executor.execute(tc.name, args)
          const resultContent: string = result.success ? result.data : `错误: ${result.data}`
          this.callbacks.onToolCallResult(tc.name, resultContent, result.success)

          const toolMsg: AgentMessage = {
            role: 'tool',
            tool_call_id: tc.id,
            content: resultContent
          }
          agentMessages.push(toolMsg)
        }
      } else {
        this.callbacks.onComplete()
        return
      }
    }

    this.callbacks.onTextChunk('\n\n[已达到最大工具调用轮次限制]')
    this.callbacks.onComplete()
  }

  private callAPI(messages: AgentMessage[]): Promise<AgentResponse | null> {
    return new Promise<AgentResponse | null>((resolve: (value: AgentResponse | null) => void) => {
      const httpRequest: http.HttpRequest = http.createHttp()
      const toolsSchema: Object[] = ToolRegistry.getToolsSchema()

      httpRequest.requestInStream(AppConstants.AI_PROXY_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'X-Proxy-Key': AppConstants.AI_PROXY_KEY,
          'Accept': 'text/event-stream'
        },
        extraData: JSON.stringify({
          model: MODEL,
          messages: messages,
          max_tokens: 2048,
          temperature: 0.7,
          stream: false,
          tools: toolsSchema
        }),
        connectTimeout: 10000,
        readTimeout: 60000
      }).then((responseCode: number) => {
        if (responseCode !== 200) {
          httpRequest.destroy()
          resolve(null)
        }
      }).catch((err: Error) => {
        console.error('[Agent] non-stream request error:', String(err))
        httpRequest.destroy()
        resolve(null)
      })

      let fullBuffer: string = ''

      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
        const decodeOpts: DecodeOptions = { stream: true }
        const chunk: string = decoder.decodeWithStream(new Uint8Array(data), decodeOpts)
        fullBuffer += chunk
      })

      httpRequest.on('dataEnd', () => {
        try {
          const jsonData: Record<string, Object> = JSON.parse(fullBuffer) as Record<string, Object>
          const choices: Object[] = jsonData['choices'] as Object[]
          if (!choices || choices.length === 0) {
            httpRequest.destroy()
            resolve(null)
            return
          }
          const firstChoice: Record<string, Object> = choices[0] as Record<string, Object>
          const message: Record<string, Object> = firstChoice['message'] as Record<string, Object>
          const content: string = (message['content'] as string) || ''
          const reasoning: string = (message['reasoning_content'] as string) || ''
          const toolCalls: Object[] | undefined = message['tool_calls'] as Object[] | undefined

          const result: AgentResponse = {
            textContent: content,
            reasoningContent: reasoning,
            toolCalls: toolCalls ? this.parseToolCalls(toolCalls) : []
          }
          httpRequest.destroy()
          resolve(result)
        } catch (e) {
          console.error('[Agent] parse non-stream response error:', String(e))
          httpRequest.destroy()
          resolve(null)
        }
      })
    })
  }

  private callAPIStream(messages: AgentMessage[]): Promise<AgentResponse | null> {
    return new Promise<AgentResponse | null>((resolve: (value: AgentResponse | null) => void) => {
      const httpRequest: http.HttpRequest = http.createHttp()
      const toolsSchema: Object[] = ToolRegistry.getToolsSchema()

      let fullContent: string = ''
      let fullReasoning: string = ''
      let toolCallsMap: Record<number, ToolCallBuilder> = {}
      let toolCallsNextIndex: number = 0
      let buffer: string = ''

      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
        const decodeOpts: DecodeOptions = { stream: true }
        const chunk: string = decoder.decodeWithStream(new Uint8Array(data), decodeOpts)
        buffer += chunk

        const lines: string[] = buffer.split('\n')
        buffer = lines.pop() || ''

        for (let i = 0; i < lines.length; i++) {
          const line: string = lines[i].trim()
          if (line.length === 0 || !line.startsWith('data:')) {
            continue
          }
          const dataStr: string = line.substring(5).trim()
          if (dataStr === '[DONE]') {
            continue
          }

          try {
            const jsonData: Record<string, Object> = JSON.parse(dataStr) as Record<string, Object>
            const choices: Object[] = jsonData['choices'] as Object[]
            if (!choices || choices.length === 0) {
              continue
            }
            const firstChoice: Record<string, Object> = choices[0] as Record<string, Object>
            const delta: Record<string, Object> = firstChoice['delta'] as Record<string, Object>
            if (!delta) {
              continue
            }

            if (delta['content']) {
              const textChunk: string = delta['content'] as string
              fullContent += textChunk
              this.callbacks.onTextChunk(textChunk)
            }

            if (delta['reasoning_content']) {
              fullReasoning += delta['reasoning_content'] as string
            }

            const deltaToolCalls: Object[] | undefined = delta['tool_calls'] as Object[] | undefined
            if (deltaToolCalls) {
              for (let j = 0; j < deltaToolCalls.length; j++) {
                const dtc: Record<string, Object> = deltaToolCalls[j] as Record<string, Object>
                const index: number = (dtc['index'] as number) || 0
                if (!toolCallsMap[index]) {
                  const newBuilder: ToolCallBuilder = { id: '', name: '', arguments: '' }
                  toolCallsMap[index] = newBuilder
                }
                const builder: ToolCallBuilder = toolCallsMap[index]
                if (dtc['id']) {
                  builder.id = dtc['id'] as string
                }
                const func: Record<string, string> = dtc['function'] as Record<string, string>
                if (func) {
                  if (func['name']) {
                    builder.name += func['name']
                  }
                  if (func['arguments']) {
                    builder.arguments += func['arguments']
                  }
                }
              }
            }
          } catch (parseErr) {
            console.warn('[Agent] stream parse error:', String(parseErr))
          }
        }
      })

      httpRequest.on('dataEnd', () => {
        if (buffer.trim().length > 0) {
          const line: string = buffer.trim()
          if (line.startsWith('data:')) {
            const dataStr: string = line.substring(5).trim()
            if (dataStr !== '[DONE]') {
              try {
                const jsonData: Record<string, Object> = JSON.parse(dataStr) as Record<string, Object>
                const choices: Object[] = jsonData['choices'] as Object[]
                if (choices && choices.length > 0) {
                  const firstChoice: Record<string, Object> = choices[0] as Record<string, Object>
                  const delta: Record<string, Object> = firstChoice['delta'] as Record<string, Object>
                  if (delta && delta['content']) {
                    const textChunk: string = delta['content'] as string
                    fullContent += textChunk
                    this.callbacks.onTextChunk(textChunk)
                  }
                }
              } catch (parseErr) {
                console.warn('[Agent] stream final parse error:', String(parseErr))
              }
            }
          }
        }

        const toolCalls: ToolCallInfo[] = []
        const keys: string[] = Object.keys(toolCallsMap)
        const indices: number[] = []
        for (let i = 0; i < keys.length; i++) {
          indices.push(Number(keys[i]))
        }
        indices.sort((a: number, b: number) => a - b)
        for (let i = 0; i < indices.length; i++) {
          const builder: ToolCallBuilder = toolCallsMap[indices[i]]
          toolCalls.push({
            id: builder.id,
            name: builder.name,
            arguments: builder.arguments
          })
        }

        const result: AgentResponse = {
          textContent: fullContent,
          reasoningContent: fullReasoning,
          toolCalls: toolCalls
        }
        httpRequest.destroy()
        resolve(result)
      })

      httpRequest.requestInStream(AppConstants.AI_PROXY_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'X-Proxy-Key': AppConstants.AI_PROXY_KEY,
          'Accept': 'text/event-stream'
        },
        extraData: JSON.stringify({
          model: MODEL,
          messages: messages,
          max_tokens: 2048,
          temperature: 0.7,
          stream: true,
          tools: toolsSchema
        }),
        connectTimeout: 10000,
        readTimeout: 60000
      }).then((responseCode: number) => {
        if (responseCode !== 200) {
          httpRequest.destroy()
          resolve(null)
        }
      }).catch((err: Error) => {
        console.error('[Agent] stream request error:', String(err))
        httpRequest.destroy()
        resolve(null)
      })
    })
  }

  private parseToolCalls(rawToolCalls: Object[]): ToolCallInfo[] {
    const result: ToolCallInfo[] = []
    for (let i = 0; i < rawToolCalls.length; i++) {
      const tc: Record<string, Object> = rawToolCalls[i] as Record<string, Object>
      const func: Record<string, string> = tc['function'] as Record<string, string>
      result.push({
        id: (tc['id'] as string) || '',
        name: func ? (func['name'] || '') : '',
        arguments: func ? (func['arguments'] || '{}') : '{}'
      })
    }
    return result
  }

  private toApiToolCalls(toolCalls: ToolCallInfo[]): ApiToolCall[] {
    const result: ApiToolCall[] = []
    for (let i = 0; i < toolCalls.length; i++) {
      const tc: ToolCallInfo = toolCalls[i]
      result.push({
        id: tc.id,
        type: 'function',
        function: {
          name: tc.name,
          arguments: tc.arguments
        }
      })
    }
    return result
  }
}

interface AgentResponse {
  textContent: string
  reasoningContent: string
  toolCalls: ToolCallInfo[]
}

interface DecodeOptions {
  stream: boolean
}

interface ToolCallBuilder {
  id: string
  name: string
  arguments: string
}
