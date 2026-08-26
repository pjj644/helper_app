import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { AgentEndpointConfig } from './AgentEndpointConfig';

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

export interface VisionCourseItem {
  name: string;
  teacher?: string;
  room?: string;
  dayOfWeek: number;
  startSection: number;
  duration: number;
  validWeeks: string;
  confidence?: number;
}

export interface VisionCourseTableResult {
  courses: VisionCourseItem[];
  semester?: string;
  confidence?: number;
  rawAnalysis?: string;
}

export interface VisionGradeItem {
  courseName: string;
  courseCode?: string;
  credit: number;
  score: string;
  gradePoint: number;
  semester?: string;
  courseCategory?: string;
  confidence?: number;
}

export interface VisionGradeReportResult {
  grades: VisionGradeItem[];
  gpa?: number;
  totalCredits?: number;
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
      fs.closeSync(file.fd);

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
    context: Context,
    imageBase64: string,
    userHint?: string
  ): Promise<VisionScheduleResult | null> {
    const agentEndpoint = await AgentEndpointConfig.resolve(context);
    if (!AgentEndpointConfig.isReady(agentEndpoint)) {
      console.error('[VisionHelper] parseSchedule skipped:', AgentEndpointConfig.missingHint(agentEndpoint));
      return null;
    }

    const httpRequest = http.createHttp();
    try {
      const requestUrl = AgentEndpointConfig.joinUrl(agentEndpoint, 'api/vision/parse-schedule');
      const bodyObj: Record<string, string> = {
        'image': imageBase64,
        'mode': 'schedule'
      };
      if (userHint && userHint.length > 0) {
        bodyObj['hint'] = userHint;
      }

      const response = await httpRequest.request(requestUrl, {
        method: http.RequestMethod.POST,
        header: AgentEndpointConfig.buildHeaders(agentEndpoint),
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

  static async parseCourseTableFromImage(
    context: Context,
    imageBase64: string,
    userHint?: string
  ): Promise<VisionCourseTableResult | null> {
    const agentEndpoint = await AgentEndpointConfig.resolve(context);
    if (!AgentEndpointConfig.isReady(agentEndpoint)) {
      console.error('[VisionHelper] parseCourseTable skipped:', AgentEndpointConfig.missingHint(agentEndpoint));
      return null;
    }

    const httpRequest = http.createHttp();
    try {
      const requestUrl = AgentEndpointConfig.joinUrl(agentEndpoint, 'api/vision/parse-schedule');
      const bodyObj: Record<string, string> = {
        'image': imageBase64,
        'mode': 'course_table'
      };
      if (userHint && userHint.length > 0) {
        bodyObj['hint'] = userHint;
      }

      const response = await httpRequest.request(requestUrl, {
        method: http.RequestMethod.POST,
        header: AgentEndpointConfig.buildHeaders(agentEndpoint),
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
          return parsed['data'] as VisionCourseTableResult;
        }
      }
      console.error('[VisionHelper] parseCourseTable failed, code:', response.responseCode, response.result);
      return null;
    } catch (e) {
      console.error('[VisionHelper] parseCourseTable request error:', JSON.stringify(e));
      return null;
    } finally {
      httpRequest.destroy();
    }
  }

  static async parseGradeReportFromImage(
    context: Context,
    imageBase64: string,
    userHint?: string
  ): Promise<VisionGradeReportResult | null> {
    const agentEndpoint = await AgentEndpointConfig.resolve(context);
    if (!AgentEndpointConfig.isReady(agentEndpoint)) {
      console.error('[VisionHelper] parseGradeReport skipped:', AgentEndpointConfig.missingHint(agentEndpoint));
      return null;
    }

    const httpRequest = http.createHttp();
    try {
      const requestUrl = AgentEndpointConfig.joinUrl(agentEndpoint, 'api/vision/parse-schedule');
      const bodyObj: Record<string, string> = {
        'image': imageBase64,
        'mode': 'grade_report'
      };
      if (userHint && userHint.length > 0) {
        bodyObj['hint'] = userHint;
      }

      const response = await httpRequest.request(requestUrl, {
        method: http.RequestMethod.POST,
        header: AgentEndpointConfig.buildHeaders(agentEndpoint),
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
          return parsed['data'] as VisionGradeReportResult;
        }
      }
      console.error('[VisionHelper] parseGradeReport failed, code:', response.responseCode, response.result);
      return null;
    } catch (e) {
      console.error('[VisionHelper] parseGradeReport request error:', JSON.stringify(e));
      return null;
    } finally {
      httpRequest.destroy();
    }
  }
}
