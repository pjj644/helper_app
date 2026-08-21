import { preferences } from '@kit.ArkData';
import { AppConstants } from '../common/constants/AppConstants';

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface AgentTelemetryInfo {
  totalTokens?: number;
  promptTokens?: number;
  completionTokens?: number;
  durationMs?: number;
  ttftMs?: number;
}

export interface ChatDisplayMessage {
  role: string;
  content: string;
  isError: boolean;
  toolName?: string;
  toolArgs?: string;
  toolResult?: string;
  isToolSuccess?: boolean;
  telemetry?: AgentTelemetryInfo;
}

export interface ChatSession {
  id: string;
  title: string;
  messages: ChatMessage[];
  displayMessages: ChatDisplayMessage[];
  createdAt: number;
  updatedAt: number;
}

export class ChatSessionRepository {
  /**
   * 加载所有历史会话列表
   */
  static getSessions(context: Context): ChatSession[] {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const jsonStr: string = pref.getSync(AppConstants.AI_CHAT_SESSIONS_KEY, '[]') as string;
      if (jsonStr && jsonStr !== '[]') {
        return JSON.parse(jsonStr) as ChatSession[];
      }
    } catch (error) {
      console.error('[ChatSessionRepository] getSessions error:', JSON.stringify(error));
    }
    return [];
  }

  /**
   * 保存会话列表
   */
  static saveSessions(context: Context, sessions: ChatSession[]): void {
    try {
      const trimmed = sessions.slice(0, AppConstants.AI_CHAT_MAX_SESSIONS);
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      pref.putSync(AppConstants.AI_CHAT_SESSIONS_KEY, JSON.stringify(trimmed));
      pref.flushSync();
    } catch (error) {
      console.error('[ChatSessionRepository] saveSessions error:', JSON.stringify(error));
    }
  }

  /**
   * 新增或更新单个会话（置顶更新）
   */
  static saveOrUpdateSession(context: Context, session: ChatSession): void {
    const sessions = ChatSessionRepository.getSessions(context);
    let found = false;
    for (let i = 0; i < sessions.length; i++) {
      if (sessions[i].id === session.id) {
        sessions[i] = session;
        found = true;
        break;
      }
    }
    if (!found) {
      sessions.unshift(session);
    }
    ChatSessionRepository.saveSessions(context, sessions);
  }

  /**
   * 创建一个全新的会话对象
   */
  static createNewSession(title: string = '新对话'): ChatSession {
    return {
      id: `${Date.now()}`,
      title: title,
      messages: [],
      displayMessages: [],
      createdAt: Date.now(),
      updatedAt: Date.now()
    };
  }

  /**
   * 删除指定会话
   */
  static deleteSession(context: Context, sessionId: string): ChatSession[] {
    const sessions = ChatSessionRepository.getSessions(context);
    const filtered = sessions.filter((s: ChatSession) => s.id !== sessionId);
    ChatSessionRepository.saveSessions(context, filtered);
    return filtered;
  }
}
