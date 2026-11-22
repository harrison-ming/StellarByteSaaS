import { sign, verify } from 'jsonwebtoken';
import { hashSync, compareSync } from 'bcrypt';
import crypto from 'crypto';
// @ts-ignore
import EVP_BytesToKey from 'evp_bytestokey';
const algorithm = 'aes-256-cbc';
const { keyLength, ivLength } = crypto.getCipherInfo(algorithm);

function deriveLegacyKeyIv(secret: string) {
  const { keyLength, ivLength } = crypto.getCipherInfo(algorithm); // 32, 16
  const pass = Buffer.isBuffer(secret) ? secret : Buffer.from(secret ?? '', 'utf8');

  // evp_bytestokey: key length in **bits**, IV length in **bytes**
  const { key, iv } = EVP_BytesToKey(pass, null, keyLength * 8, ivLength, 'md5');

  if (key.length !== keyLength || iv.length !== ivLength) {
    throw new Error(`Derived wrong sizes (key=${key.length}, iv=${iv.length})`);
  }
  return { key, iv };
}

export function decrypt_legacy_using_IV(hexCiphertext: string) {
  const { key, iv } = deriveLegacyKeyIv(process.env.JWT_SECRET);
  const decipher = crypto.createDecipheriv(algorithm, key, iv);
  const out = Buffer.concat([decipher.update(hexCiphertext, 'hex'), decipher.final()]);
  return out.toString('utf8');
}

export function encrypt_legacy_using_IV(utf8Plaintext: string) {
  const { key, iv } = deriveLegacyKeyIv(process.env.JWT_SECRET);
  const cipher = crypto.createCipheriv(algorithm, key, iv);
  const out = Buffer.concat([cipher.update(utf8Plaintext, 'utf8'), cipher.final()]);
  return out.toString('hex');
}
export class AuthService {
  static hashPassword(password: string) {
    return hashSync(password, 10);
  }
  static comparePassword(password: string, hash: string) {
    return compareSync(password, hash);
  }
  static signJWT(value: object) {
    return sign(value, process.env.JWT_SECRET!);
  }

  // Login sessions: expire, and carry a fingerprint of the password hash so
  // a password change (or reset) ends every session issued before it.
  static signSessionJWT(value: object, passwordHash?: string | null) {
    return sign(
      { ...value, sv: AuthService.sessionFingerprint(passwordHash) },
      process.env.JWT_SECRET!,
      { expiresIn: `${AuthService.SESSION_DAYS}d` }
    );
  }

  static SESSION_DAYS = 30;

  // id of the logged-in user behind a request (auth header or cookie), or
  // null; signature only, no database lookup
  static sessionUserId(req: { headers?: any; cookies?: any }): string | null {
    try {
      const token = req?.headers?.auth || req?.cookies?.auth;
      const payload = token ? (verify(token, process.env.JWT_SECRET!) as any) : null;
      return payload?.sv && typeof payload.id === 'string' ? payload.id : null;
    } catch {
      return null;
    }
  }

  static sessionFingerprint(passwordHash?: string | null) {
    return crypto
      .createHmac('sha256', process.env.JWT_SECRET!)
      .update(passwordHash || '')
      .digest('hex')
      .slice(0, 16);
  }
  static verifyJWT(token: string) {
    return verify(token, process.env.JWT_SECRET!);
  }

  static fixedEncryption(value: string) {
    return encrypt_legacy_using_IV(value);
  }

  static fixedDecryption(hash: string) {
    return decrypt_legacy_using_IV(hash);
  }
}
