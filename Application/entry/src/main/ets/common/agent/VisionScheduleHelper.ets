import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { AppConstants } from '../constants/AppConstants';

export interface VisionScheduleResult {
  title: string;
  date: string;
  startTime: string;
  endTime: string;
  location?: string;
  description?: string;
  type?: string;
  confidence?: number;
  rawAnalysis?: string;
}

export class VisionScheduleHelper {
  static async pickImage(): Promise<string | null> {
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;

      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const selectResult = await photoPicker.select(photoSelectOptions);

      if (selectResult && selectResult.photoUris && selectResult.photoUris.length > 0) {
        return selectResult.photoUris[0];
      }
      return null;
    } catch (e) {
      console.error('[VisionHelper] pickImage error:', JSON.stringify(e));
      return null;
    }
  }

  static async convertUriToBase64(uri: string): Promise<string | null> {
    try {
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);

      const base64Helper = new util.Base64Helper();
      const uint8Array = new Uint8Array(buffer);
      const base64Str = base64Helper.encodeToStringSync(uint8Array);
      return base64Str;
    } catch (e) {
      console.error('[VisionHelper] convertUriToBase64 error:', JSON.stringify(e));
      return null;
    }
  }

  static async parseScheduleFromImage(
    backendUrl: string,
    imageBase64: string,
    userHint?: string
  ): Promise<VisionScheduleResult | null> {
    const httpRequest = http.createHttp();
    try {
      const endpoint = `${backendUrl.replace(/\/+$/, '')}/api/vision/parse-schedule`;
      const bodyObj: Record<string, string> = {
        'image': imageBase64
      };
      if (userHint && userHint.length > 0) {
        bodyObj['hint'] = userHint;
      }

      const response = await httpRequest.request(endpoint, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'x-proxy-key': 'uestc-helper-proxy-key-change-me'
        },
        extraData: JSON.stringify(bodyObj),
        readTimeout: 45000,
        connectTimeout: 15000
      });

      if (response.responseCode === 200 && response.result) {
        let resultStr = response.result as string;
        if (typeof resultStr !== 'string') {
          resultStr = JSON.stringify(response.result);
        }
        const parsed = JSON.parse(resultStr) as Record<string, Object>;
        if (parsed['ok'] && parsed['data']) {
          return parsed['data'] as VisionScheduleResult;
        }
      }
      console.error('[VisionHelper] parseSchedule failed, code:', response.responseCode, response.result);
      return null;
    } catch (e) {
      console.error('[VisionHelper] parseSchedule request error:', JSON.stringify(e));
      return null;
    } finally {
      httpRequest.destroy();
    }
  }
}
