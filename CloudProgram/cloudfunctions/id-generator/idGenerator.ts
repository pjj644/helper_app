import * as crypto from 'crypto';

export class IdGenerator {
  randomUUID() {
    const uuid = crypto.randomUUID();
    console.info(`[IdGenerator] Generate random UUID: ${uuid}`);
    return { "uuid": uuid };
  }
}
