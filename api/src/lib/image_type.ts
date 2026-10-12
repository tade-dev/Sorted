import { ApiError } from './errors.js';

/** Formats the vision model can read. HEIC is not one of them. */
export type VisionMime = 'image/png' | 'image/jpeg' | 'image/webp' | 'image/gif';

/**
 * Works out an upload's real format from its first bytes. The multipart
 * Content-Type is only a guess made from the filename on the phone, so it is
 * not trusted.
 */
export function sniffImage(buf: Buffer): VisionMime | 'image/heic' | null {
  if (buf.length >= 4 && buf.readUInt32BE(0) === 0x89504e47) return 'image/png';
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length >= 12 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') {
    return 'image/webp';
  }
  if (buf.length >= 6 && /^GIF8[79]a$/.test(buf.toString('ascii', 0, 6))) return 'image/gif';
  if (buf.length >= 12 && buf.toString('ascii', 4, 8) === 'ftyp') {
    const brand = buf.toString('ascii', 8, 12);
    if (['heic', 'heix', 'hevc', 'heim', 'heis', 'mif1', 'msf1'].includes(brand)) return 'image/heic';
  }
  return null;
}

/** The mime to send to the model, or a 400 the app can show. */
export function visionMime(buf: Buffer): VisionMime {
  const kind = sniffImage(buf);
  if (kind === 'image/heic') {
    throw new ApiError(400, 'VALIDATION_FAILED', 'That photo is in HEIC format. Try again, or send a PNG or JPEG.');
  }
  if (!kind) throw new ApiError(400, 'VALIDATION_FAILED', 'That file is not an image Sorted can read.');
  return kind;
}

/** Multer filter: let anything image-like or unlabelled through; bytes decide. */
export function looksLikeUpload(mimetype: string): boolean {
  return mimetype.startsWith('image/') || mimetype === 'application/octet-stream';
}
