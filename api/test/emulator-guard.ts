import net from 'node:net';

/**
 * firebase-admin retries a dead emulator for minutes, and vitest waits on
 * those open handles, so `npx vitest run` looks hung. Fail in under a second
 * with the actual cause instead.
 */
export function requireEmulator(port = 8080): Promise<void> {
  const message =
    `Firestore emulator is not running on 127.0.0.1:${port}. ` +
    'Start it with `npm run emulators` from the repo root. ' +
    'Without it, firebase-admin keeps retrying and vitest does not exit.';

  return new Promise((resolve, reject) => {
    let settled = false;
    const socket = net.connect({ host: '127.0.0.1', port });
    const fail = () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      socket.destroy();
      reject(new Error(message));
    };
    const timer = setTimeout(fail, 500);
    socket.once('connect', () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      socket.end();
      resolve();
    });
    socket.once('error', fail);
  });
}
