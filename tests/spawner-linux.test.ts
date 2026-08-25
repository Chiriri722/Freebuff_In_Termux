import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { createNodeSpawner } from '../src/index.js';

const linuxTest = process.platform === 'linux' ? test : test.skip;

const processExists = (pid: number): boolean => {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code !== 'ESRCH';
  }
};

const waitForProcessExit = async (pid: number): Promise<boolean> => {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    if (!processExists(pid)) return true;
    await delay(25);
  }
  return !processExists(pid);
};

describe('createNodeSpawner Linux process contracts', () => {
  linuxTest(
    'enforces one aggregate stdout/stderr byte budget on a real process',
    async () => {
      const result = await createNodeSpawner().spawn(
        process.execPath,
        [
          '-e',
          [
            "process.on('SIGTERM', () => {});",
            "process.stdout.write('abc');",
            "process.stderr.write('defgh');",
            'setInterval(() => {}, 1000);',
          ].join(''),
        ],
        { stdio: 'pipe', maxOutputBytes: 6, killGraceMs: 25 },
      );

      expect(
        Buffer.byteLength(result.stdout) + Buffer.byteLength(result.stderr),
      ).toBe(6);
      expect(result).toMatchObject({
        outputTruncated: true,
        terminationReason: 'output-limit',
      });
    },
    10_000,
  );

  linuxTest(
    'escalates timeout across the real process group and leaves no grandchild',
    async () => {
      const fixture = mkdtempSync(join(tmpdir(), 'freebuff-spawner-linux-'));
      const pidFile = join(fixture, 'grandchild.pid');
      const sentinel = join(fixture, 'orphan-sentinel');
      let grandchildPid = 0;

      const grandchildSource = [
        "const fs=require('node:fs');",
        "process.on('SIGTERM',()=>{});",
        `fs.writeFileSync(${JSON.stringify(pidFile)},String(process.pid));`,
        `setTimeout(()=>fs.writeFileSync(${JSON.stringify(sentinel)},'orphan'),1200);`,
        'setInterval(()=>{},1000);',
      ].join('');
      const parentSource = [
        "const {spawn}=require('node:child_process');",
        "process.on('SIGTERM',()=>{});",
        `spawn(process.execPath,['-e',${JSON.stringify(grandchildSource)}],{stdio:'ignore'});`,
        'setInterval(()=>{},1000);',
      ].join('');

      try {
        const result = await createNodeSpawner().spawn(
          process.execPath,
          ['-e', parentSource],
          { stdio: 'pipe', timeout: 500, killGraceMs: 100 },
        );
        expect(result.terminationReason).toBe('timeout');
        expect(existsSync(pidFile)).toBe(true);
        grandchildPid = Number.parseInt(readFileSync(pidFile, 'utf8'), 10);
        expect(Number.isSafeInteger(grandchildPid)).toBe(true);
        expect(await waitForProcessExit(grandchildPid)).toBe(true);
        await delay(700);
        expect(existsSync(sentinel)).toBe(false);
      } finally {
        if (grandchildPid > 0 && processExists(grandchildPid)) {
          try {
            process.kill(grandchildPid, 'SIGKILL');
          } catch {
            // The process may exit between the probe and cleanup signal.
          }
        }
        rmSync(fixture, { recursive: true, force: true });
      }
    },
    10_000,
  );

  linuxTest(
    'applies AbortSignal to the real process group',
    async () => {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 100);
      try {
        const result = await createNodeSpawner().spawn(
          process.execPath,
          ['-e', "process.on('SIGTERM',()=>{});setInterval(()=>{},1000);"],
          {
            stdio: 'pipe',
            signal: controller.signal,
            killGraceMs: 25,
          },
        );
        expect(result.terminationReason).toBe('abort');
      } finally {
        clearTimeout(timer);
      }
    },
    10_000,
  );
});
