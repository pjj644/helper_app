import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

/**
 * AI 会话上云加解密工具（P2-7d）。
 *
 * - 密钥派生：cryptoFramework.createKdf('PBKDF2|SHA256') + PBKDF2Spec
 *   （password = 登录账号 UID，salt = 固定应用盐值 UTF-8 字节，iterations = 10000，
 *   keySize = 32 字节 → AES256 密钥）。API 形态依据本 SDK 文档
 *   《使用PBKDF2进行密钥派生(ArkTS)》（docs id: crypto-key-derivation-using-pbkdf2）。
 * - 加解密：AES-256-GCM（createCipher('AES256|GCM')），随机 12 字节 IV，
 *   authTag 在加密时由 doFinal(null) 产出、解密时填回 init 参数——依据文档
 *   《使用AES对称密钥（GCM模式）加解密(ArkTS)》（docs id: crypto-aes-sym-encrypt-decrypt-gcm）。
 * - 输出格式：base64(IV ‖ cipherText ‖ authTag)，解密侧按 IV_LEN / TAG_LEN 定长切分。
 * - 派生密钥按 UID 缓存在静态字段；UID 变化自动重派生（账号间数据自然隔离），
 *   登出/注销时由 SessionSyncService.stopAndClear 调 clearKeyCache 主动清除。
 */
export class SessionCryptoUtil {
  private static readonly KDF_ALG: string = 'PBKDF2|SHA256';
  private static readonly CIPHER_ALG: string = 'AES256|GCM';
  private static readonly SYM_KEY_ALG: string = 'AES256';
  private static readonly PBKDF2_ITERATIONS: number = 10000;
  private static readonly KEY_SIZE_BYTES: number = 32;
  /** GCM 随机 IV 长度（字节） */
  private static readonly IV_LEN_BYTES: number = 12;
  /** GCM 认证标签长度（字节），cryptoFramework 默认输出 16 */
  private static readonly TAG_LEN_BYTES: number = 16;
  /** 固定应用盐值：仅用于把 UID 映射到本应用专属的密钥空间，非保密常量 */
  private static readonly APP_KDF_SALT: string = 'helper_app_session_cloud_sync_salt_v1';
  /** GCM AAD：不加密但参与认证，绑定「本应用会话同步」语境 */
  private static readonly GCM_AAD: string = 'helper_app_chat_session_v1';

  private static cachedUid: string = '';
  private static cachedKey: cryptoFramework.SymKey | null = null;

  /**
   * 按 UID 派生（带缓存）AES-256 密钥。同一 UID 复用缓存；UID 变化时重新派生。
   */
  static async getDerivedKey(uid: string): Promise<cryptoFramework.SymKey> {
    if (SessionCryptoUtil.cachedKey && SessionCryptoUtil.cachedUid === uid) {
      return SessionCryptoUtil.cachedKey;
    }
    const saltBytes: Uint8Array = SessionCryptoUtil.utf8Bytes(SessionCryptoUtil.APP_KDF_SALT);
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: uid,
      salt: saltBytes,
      iterations: SessionCryptoUtil.PBKDF2_ITERATIONS,
      keySize: SessionCryptoUtil.KEY_SIZE_BYTES
    };
    const kdf = cryptoFramework.createKdf(SessionCryptoUtil.KDF_ALG);
    const secret = await kdf.generateSecret(spec);
    const generator = cryptoFramework.createSymKeyGenerator(SessionCryptoUtil.SYM_KEY_ALG);
    const keyBlob: cryptoFramework.DataBlob = { data: secret.data };
    const symKey = await generator.convertKey(keyBlob);
    SessionCryptoUtil.cachedUid = uid;
    SessionCryptoUtil.cachedKey = symKey;
    return symKey;
  }

  /**
   * 加密：返回 base64(IV ‖ cipherText ‖ authTag)。任何失败直接抛出，由调用方软降处理。
   */
  static async encrypt(uid: string, plainText: string): Promise<string> {
    const symKey = await SessionCryptoUtil.getDerivedKey(uid);
    const ivBytes: Uint8Array =
      cryptoFramework.createRandom().generateRandomSync(SessionCryptoUtil.IV_LEN_BYTES).data;
    const gcmParams: cryptoFramework.GcmParamsSpec = {
      iv: { data: ivBytes },
      aad: { data: SessionCryptoUtil.utf8Bytes(SessionCryptoUtil.GCM_AAD) },
      // 占位：GCM 加密时 authTag 从 doFinal 结果中获取并回填
      authTag: { data: new Uint8Array(SessionCryptoUtil.TAG_LEN_BYTES) },
      algName: 'GcmParamsSpec'
    };
    const cipher = cryptoFramework.createCipher(SessionCryptoUtil.CIPHER_ALG);
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, gcmParams);
    const plainBlob: cryptoFramework.DataBlob = { data: SessionCryptoUtil.utf8Bytes(plainText) };
    const updateResult = await cipher.update(plainBlob);
    const tagResult = await cipher.doFinal(null);
    if (!tagResult || !tagResult.data || tagResult.data.length !== SessionCryptoUtil.TAG_LEN_BYTES) {
      throw new Error('GCM encrypt: invalid authTag from doFinal');
    }
    const cipherLen = updateResult && updateResult.data ? updateResult.data.length : 0;
    const combined = new Uint8Array(
      SessionCryptoUtil.IV_LEN_BYTES + cipherLen + SessionCryptoUtil.TAG_LEN_BYTES
    );
    combined.set(ivBytes, 0);
    if (cipherLen > 0) {
      combined.set(updateResult.data, SessionCryptoUtil.IV_LEN_BYTES);
    }
    combined.set(tagResult.data, SessionCryptoUtil.IV_LEN_BYTES + cipherLen);
    return new util.Base64Helper().encodeToStringSync(combined);
  }

  /**
   * 解密 base64(IV ‖ cipherText ‖ authTag)：认证失败或格式非法时抛出异常，由调用方跳过该记录。
   */
  static async decrypt(uid: string, payloadB64: string): Promise<string> {
    const symKey = await SessionCryptoUtil.getDerivedKey(uid);
    const raw = new util.Base64Helper().decodeSync(payloadB64);
    const minLen = SessionCryptoUtil.IV_LEN_BYTES + SessionCryptoUtil.TAG_LEN_BYTES;
    if (!raw || raw.length <= minLen) {
      throw new Error('GCM decrypt: payload too short');
    }
    const ivBytes = raw.slice(0, SessionCryptoUtil.IV_LEN_BYTES);
    const tagBytes = raw.slice(raw.length - SessionCryptoUtil.TAG_LEN_BYTES);
    const cipherBytes = raw.slice(SessionCryptoUtil.IV_LEN_BYTES, raw.length - SessionCryptoUtil.TAG_LEN_BYTES);
    const gcmParams: cryptoFramework.GcmParamsSpec = {
      iv: { data: ivBytes },
      aad: { data: SessionCryptoUtil.utf8Bytes(SessionCryptoUtil.GCM_AAD) },
      authTag: { data: tagBytes },
      algName: 'GcmParamsSpec'
    };
    const decoder = cryptoFramework.createCipher(SessionCryptoUtil.CIPHER_ALG);
    await decoder.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, gcmParams);
    const updateResult = await decoder.update({ data: cipherBytes });
    await decoder.doFinal(null); // 校验 init 时传入的 authTag，失败抛出
    if (!updateResult || !updateResult.data) {
      return '';
    }
    return util.TextDecoder.create('utf-8').decodeToString(updateResult.data);
  }

  /** 清除静态密钥缓存（登出/注销/账号切换时调用） */
  static clearKeyCache(): void {
    SessionCryptoUtil.cachedUid = '';
    SessionCryptoUtil.cachedKey = null;
  }

  private static utf8Bytes(text: string): Uint8Array {
    return new util.TextEncoder().encodeInto(text);
  }
}
