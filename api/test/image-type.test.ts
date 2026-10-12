import { describe, expect, it } from 'vitest';
import { sniffImage, visionMime } from '../src/lib/image_type.js';

const hex = (h: string) => Buffer.from(h.replace(/ /g, ''), 'hex');
const ftyp = (brand: string) => Buffer.concat([hex('00000018'), Buffer.from('ftyp' + brand), Buffer.alloc(8)]);

describe('sniffImage', () => {
  it('reads the format from the bytes, not the label', () => {
    expect(sniffImage(hex('89504e470d0a1a0a'))).toBe('image/png');
    expect(sniffImage(hex('ffd8ffe000104a46'))).toBe('image/jpeg');
    expect(sniffImage(Buffer.from('RIFF\0\0\0\0WEBPVP8 '))).toBe('image/webp');
    expect(sniffImage(Buffer.from('GIF89a......'))).toBe('image/gif');
    expect(sniffImage(ftyp('heic'))).toBe('image/heic');
    expect(sniffImage(Buffer.from('hello world!'))).toBeNull();
  });

  it('turns HEIC and unknown files away with a readable 400', () => {
    expect(() => visionMime(ftyp('heic'))).toThrow(/HEIC/);
    expect(() => visionMime(Buffer.from('not an image'))).toThrow(/not an image/);
    expect(visionMime(hex('ffd8ffdb'))).toBe('image/jpeg');
  });
});
