export class StringUtils {
  static isEmpty(str: string | null | undefined): boolean {
    return str === null || str === undefined || str.trim().length === 0;
  }

  static isNotEmpty(str: string | null | undefined): boolean {
    return !StringUtils.isEmpty(str);
  }

  static truncate(str: string, maxLength: number): string {
    if (StringUtils.isEmpty(str)) {
      return '';
    }
    if (str!.length <= maxLength) {
      return str!;
    }
    return str!.substring(0, maxLength) + '...';
  }

  static getFirstChar(str: string): string {
    if (StringUtils.isEmpty(str)) {
      return '';
    }
    return str!.charAt(0);
  }

  static formatPhone(phone: string): string {
    if (StringUtils.isEmpty(phone) || phone!.length !== 11) {
      return phone || '';
    }
    return `${phone!.substring(0, 3)}****${phone!.substring(7)}`;
  }

  static isValidPhone(phone: string): boolean {
    const phoneReg = /^1[3-9]\d{9}$/;
    return phoneReg.test(phone);
  }

  static isValidEmail(email: string): boolean {
    const emailReg = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
    return emailReg.test(email);
  }

  static isValidStudentId(studentId: string): boolean {
    const studentIdReg = /^\d{8,12}$/;
    return studentIdReg.test(studentId);
  }

  static generateId(): string {
    return `${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }

  static removeHtmlTags(str: string): string {
    if (StringUtils.isEmpty(str)) {
      return '';
    }
    return str!.replace(/<[^>]*>/g, '');
  }
}
