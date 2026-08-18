import { speechRecognizer } from '@kit.CoreSpeechKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';

export class SpeechRecognizerHelper {
  private asrEngine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private sessionId: string = '';
  private isListening: boolean = false;

  async requestMicrophonePermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const authResults = await atManager.requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
      for (let i = 0; i < authResults.authResults.length; i++) {
        if (authResults.authResults[i] !== 0) {
          return false;
        }
      }
      return true;
    } catch (e) {
      console.error('[SpeechRecognizer] request permission failed:', JSON.stringify(e));
      return false;
    }
  }

  async initEngine(): Promise<boolean> {
    if (this.asrEngine) {
      return true;
    }
    try {
      const extraParams: Record<string, Object> = { 'locate': 'CN', 'recognizerMode': 'short' };
      const initParamsInfo: speechRecognizer.CreateEngineParams = {
        language: 'zh-CN',
        online: 1,
        extraParams: extraParams
      };
      this.asrEngine = await speechRecognizer.createEngine(initParamsInfo);
      return true;
    } catch (e) {
      console.error('[SpeechRecognizer] createEngine failed:', JSON.stringify(e));
      return false;
    }
  }

  async startListening(
    context: common.UIAbilityContext,
    onResult: (text: string, isLast: boolean) => void,
    onError: (err: string) => void
  ): Promise<boolean> {
    const hasPerm = await this.requestMicrophonePermission(context);
    if (!hasPerm) {
      onError('麦克风权限未授予，请在设置中开启');
      return false;
    }

    const inited = await this.initEngine();
    if (!inited || !this.asrEngine) {
      onError('语音识别引擎不可用，请使用键盘输入');
      return false;
    }

    try {
      this.sessionId = 'session_' + Date.now();
      const listener: speechRecognizer.RecognitionListener = {
        onStart(sessionId: string, eventMessage: string) {
          console.info(`[SpeechRecognizer] onStart: ${sessionId}, msg: ${eventMessage}`);
        },
        onEvent(sessionId: string, eventCode: number, eventMessage: string) {
          console.info(`[SpeechRecognizer] onEvent: ${sessionId}, code: ${eventCode}`);
        },
        onResult(sessionId: string, result: speechRecognizer.SpeechRecognitionResult) {
          const text = result ? result.result : '';
          const isLast = result ? result.isLast : false;
          onResult(text, isLast);
        },
        onComplete(sessionId: string, eventMessage: string) {
          console.info(`[SpeechRecognizer] onComplete: ${sessionId}`);
          onResult('', true);
        },
        onError(sessionId: string, errorCode: number, errorMessage: string) {
          console.error(`[SpeechRecognizer] onError: ${sessionId}, code: ${errorCode}, msg: ${errorMessage}`);
          onError(errorMessage || `识别错误: ${errorCode}`);
        }
      };

      this.asrEngine.setListener(listener);

      const recognizerParams: speechRecognizer.StartParams = {
        sessionId: this.sessionId,
        audioInfo: {
          audioType: 'pcm',
          sampleRate: 16000,
          soundChannel: 1,
          sampleBit: 16
        },
        extraParams: {
          'recognitionMode': 0
        }
      };

      this.asrEngine.startListening(recognizerParams);
      this.isListening = true;
      return true;
    } catch (e) {
      console.error('[SpeechRecognizer] startListening error:', JSON.stringify(e));
      onError('启动录音失败: ' + String(e));
      return false;
    }
  }

  async stopListening(): Promise<void> {
    if (this.asrEngine && this.isListening) {
      try {
        await this.asrEngine.finish(this.sessionId);
      } catch (e) {
        // ignore
      }
      this.isListening = false;
    }
  }

  async release(): Promise<void> {
    if (this.asrEngine) {
      try {
        await this.asrEngine.shutdown();
      } catch (e) {}
      this.asrEngine = null;
      this.isListening = false;
    }
  }
}
