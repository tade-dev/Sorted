import { describe, expect, it } from 'vitest';
import { requireEmulator } from './emulator-guard.js';

describe('requireEmulator', () => {
  it('fails in under a second when nothing is listening', async () => {
    const started = Date.now();
    await expect(requireEmulator(1)).rejects.toThrow(/Firestore emulator is not running/);
    expect(Date.now() - started).toBeLessThan(1_000);
  });
});
