import * as crypto from 'crypto';

export class IdGenerator {
  randomUUID() {
    const uuid = crypto.randomUUID();
    console.info(`Generate random UUID: ${uuid}`);
    return { "uuid": uuid };
  }
}
