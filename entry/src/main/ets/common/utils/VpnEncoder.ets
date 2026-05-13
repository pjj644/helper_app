import { AppConstants } from '../constants/AppConstants';

class Aes128Cfb {
  private static readonly S_BOX: number[] = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
  ];

  private static readonly R_CON: number[] = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36];

  private static xtime(a: number): number {
    return ((a << 1) ^ (((a >> 7) & 1) * 0x1b)) & 0xff;
  }

  private static subBytes(state: number[]): void {
    for (let i = 0; i < 16; i++) {
      state[i] = Aes128Cfb.S_BOX[state[i]];
    }
  }

  private static shiftRows(state: number[]): void {
    let t: number;
    t = state[1]; state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = t;
    t = state[2]; state[2] = state[10]; state[10] = t;
    t = state[6]; state[6] = state[14]; state[14] = t;
    t = state[3]; state[3] = state[15]; state[15] = state[11]; state[11] = state[7]; state[7] = t;
  }

  private static mixColumns(state: number[]): void {
    for (let i = 0; i < 4; i++) {
      const s0 = state[i * 4];
      const s1 = state[i * 4 + 1];
      const s2 = state[i * 4 + 2];
      const s3 = state[i * 4 + 3];
      state[i * 4] = Aes128Cfb.xtime(s0 ^ s1) ^ s1 ^ s2 ^ s3;
      state[i * 4 + 1] = s0 ^ Aes128Cfb.xtime(s1 ^ s2) ^ s2 ^ s3;
      state[i * 4 + 2] = s0 ^ s1 ^ Aes128Cfb.xtime(s2 ^ s3) ^ s3;
      state[i * 4 + 3] = Aes128Cfb.xtime(s0 ^ s3) ^ s0 ^ s1 ^ s2;
    }
  }

  private static addRoundKey(state: number[], roundKey: number[]): void {
    for (let i = 0; i < 16; i++) {
      state[i] ^= roundKey[i];
    }
  }

  private static keyExpansion(key: number[]): number[] {
    const w: number[] = new Array(176);
    for (let i = 0; i < 16; i++) {
      w[i] = key[i];
    }
    for (let i = 4; i < 44; i++) {
      let temp = [w[(i - 1) * 4], w[(i - 1) * 4 + 1], w[(i - 1) * 4 + 2], w[(i - 1) * 4 + 3]];
      if (i % 4 === 0) {
        temp = [
          Aes128Cfb.S_BOX[temp[1]] ^ Aes128Cfb.R_CON[i / 4 - 1],
          Aes128Cfb.S_BOX[temp[2]],
          Aes128Cfb.S_BOX[temp[3]],
          Aes128Cfb.S_BOX[temp[0]]
        ];
      }
      for (let j = 0; j < 4; j++) {
        w[i * 4 + j] = w[(i - 4) * 4 + j] ^ temp[j];
      }
    }
    return w;
  }

  private static encryptBlock(block: number[], roundKeys: number[]): number[] {
    const state = block.slice();
    Aes128Cfb.addRoundKey(state, roundKeys.slice(0, 16));
    for (let round = 1; round <= 9; round++) {
      Aes128Cfb.subBytes(state);
      Aes128Cfb.shiftRows(state);
      Aes128Cfb.mixColumns(state);
      Aes128Cfb.addRoundKey(state, roundKeys.slice(round * 16, round * 16 + 16));
    }
    Aes128Cfb.subBytes(state);
    Aes128Cfb.shiftRows(state);
    Aes128Cfb.addRoundKey(state, roundKeys.slice(160, 176));
    return state;
  }

  static encrypt(key: number[], iv: number[], plaintext: number[]): number[] {
    const roundKeys = Aes128Cfb.keyExpansion(key);
    const result: number[] = [];
    let feedback = iv.slice();
    for (let i = 0; i < plaintext.length; i += 16) {
      const encrypted = Aes128Cfb.encryptBlock(feedback, roundKeys);
      const chunk: number[] = [];
      for (let j = 0; j < 16 && i + j < plaintext.length; j++) {
        chunk.push(encrypted[j] ^ plaintext[i + j]);
      }
      result.push(...chunk);
      feedback = chunk.length === 16 ? chunk.slice() : encrypted.slice(0, chunk.length);
    }
    return result;
  }
}

export class VpnEncoder {
  private static readonly VPN_KEY: string = 'wrdvpnisthebest!';
  private static readonly VPN_IV: string = 'wrdvpnisthebest!';
  private static hostCache: Record<string, string> = {};

  static buildVpnEamsUrl(path: string): string {
    return `${AppConstants.WEBVPN_BASE_URL}/https/${VpnEncoder.encodeHost(AppConstants.WEBVPN_EAMS_DOMAIN)}${path}`;
  }

  static buildVpnCourseTableUrl(): string {
    return VpnEncoder.buildVpnEamsUrl('/eams/courseTableForStd.action');
  }

  static buildVpnEamsPortalUrl(): string {
    return VpnEncoder.buildVpnEamsUrl('/eams/home!childmenus.action?menu.id=844');
  }

  static buildVpnExamMenuUrl(): string {
    return VpnEncoder.buildVpnEamsUrl('/eams/home!childmenus.action?menu.id=844');
  }

  static buildVpnExamTableUrl(semesterId: number, examTypeId: number): string {
    return VpnEncoder.buildVpnEamsUrl(
      `/eams/stdExamTable!examTable.action?semester.id=${semesterId}&examType.id=${examTypeId}`
    );
  }

  static buildVpnGradeUrl(semesterId: number): string {
    return VpnEncoder.buildVpnEamsUrl(
      `/eams/teach/grade/course/person!search.action?semesterId=${semesterId}&projectType=`
    );
  }

  static buildVpnHomeUrl(): string {
    return VpnEncoder.buildVpnEamsUrl('/eams/home!index.action');
  }

  static isVpnEamsUrl(url: string): boolean {
    return url.includes(VpnEncoder.encodeHost(AppConstants.WEBVPN_EAMS_DOMAIN)) && url.includes('/eams/');
  }

  static isWebvpnPortal(url: string): boolean {
    return url.includes('webvpn.uestc.edu.cn') &&
      !url.includes(VpnEncoder.encodeHost(AppConstants.WEBVPN_EAMS_DOMAIN)) &&
      !url.includes('authserver/login');
  }

  static isLoginPage(url: string): boolean {
    return url.includes('authserver/login') || url.includes('idas.uestc.edu.cn');
  }

  static isVpnLoginPage(url: string): boolean {
    return url.includes('webvpn.uestc.edu.cn') && url.includes('authserver/login');
  }

  static buildVpnUrlFromOriginal(originalUrl: string): string {
    if (!originalUrl) {
      return AppConstants.WEBVPN_LOGIN_URL;
    }

    if (originalUrl.includes('webvpn.uestc.edu.cn')) {
      return originalUrl;
    }

    const httpsPattern = /^https:\/\//;
    const httpPattern = /^http:\/\//;

    let protocol = 'https';
    let urlWithoutProtocol = originalUrl;

    if (httpPattern.test(originalUrl)) {
      protocol = 'http';
      urlWithoutProtocol = originalUrl.replace(httpPattern, '');
    } else if (httpsPattern.test(originalUrl)) {
      urlWithoutProtocol = originalUrl.replace(httpsPattern, '');
    }

    const pathIndex = urlWithoutProtocol.indexOf('/');
    let host = urlWithoutProtocol;
    let path = '';

    if (pathIndex !== -1) {
      host = urlWithoutProtocol.substring(0, pathIndex);
      path = urlWithoutProtocol.substring(pathIndex);
    }

    const hostEncoded = VpnEncoder.encodeHost(host);

    return `${AppConstants.WEBVPN_BASE_URL}/${protocol}/${hostEncoded}${path}`;
  }

  static encodeHost(host: string): string {
    if (VpnEncoder.hostCache[host]) {
      return VpnEncoder.hostCache[host];
    }

    const keyBytes: number[] = [];
    const ivBytes: number[] = [];
    for (let i = 0; i < 16; i++) {
      keyBytes.push(VpnEncoder.VPN_KEY.charCodeAt(i));
      ivBytes.push(VpnEncoder.VPN_IV.charCodeAt(i));
    }

    const segmentSize = 16;
    const appendLength = segmentSize - (host.length % segmentSize);
    const paddedHost = host.padEnd(host.length + appendLength, '0');

    const plaintext: number[] = [];
    for (let i = 0; i < paddedHost.length; i++) {
      plaintext.push(paddedHost.charCodeAt(i));
    }

    const encrypted = Aes128Cfb.encrypt(keyBytes, ivBytes, plaintext);

    const ivHex = ivBytes.map(b => b.toString(16).padStart(2, '0')).join('');
    const encHex = encrypted.map(b => b.toString(16).padStart(2, '0')).join('');

    const result = ivHex + encHex.slice(0, host.length * 2);
    VpnEncoder.hostCache[host] = result;
    return result;
  }
}
