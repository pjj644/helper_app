import { cloudDatabase } from '@kit.CloudFoundationKit';

/**
 * AI 会话云端记录（P2-7d），对应 CloudProgram/clouddb/objecttype/ChatSessionRecord.json。
 * - id = 本地 session.id（幂等 upsert 主键）；
 * - payload 为 AES-256-GCM 加密后 base64(IV ‖ cipherText ‖ authTag) 的整体会话密文，
 *   服务端只见密文（schema 中 isSensitive，无 World 角色）；
 * - updatedAt 为 LWW 时间戳（毫秒 Date）。
 */
export class ChatSessionRecord extends cloudDatabase.DatabaseObject {
  id: string = '';
  userId: string = '';
  payload: string = '';
  payloadVersion: number = 1;
  updatedAt?: Date;
}
