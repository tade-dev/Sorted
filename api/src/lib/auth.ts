import type { RequestHandler } from 'express';
import { ApiError } from './errors.js';

export type TokenVerifier = (token: string) => Promise<{ uid: string }>;

declare global {
  namespace Express {
    interface Request {
      sellerId?: string;
    }
  }
}

export function requireSeller(verify: TokenVerifier): RequestHandler {
  return async (req, _res, next) => {
    const header = req.get('authorization') ?? '';
    // RFC 7235: the scheme is case-insensitive, and clients vary in spacing.
    const token = /^\s*bearer\s+(\S+)\s*$/i.exec(header)?.[1];
    if (!token) {
      next(new ApiError(401, 'UNAUTHENTICATED', 'A bearer token is required.'));
      return;
    }
    try {
      const { uid } = await verify(token);
      req.sellerId = uid;
      next();
    } catch {
      // Deliberately opaque: never echo the provider's message back.
      next(new ApiError(401, 'UNAUTHENTICATED', 'Your session has expired.'));
    }
  };
}
