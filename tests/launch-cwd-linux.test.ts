import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { FreeBuffLauncher, ProotDistroManager } from '../src/index.js';
import type { CommandRunner } from '../src/types.js';

const linuxTest = process.platform === 'linux' ? test : test.skip;

linuxTest.each(['launcher', 'manager'])(
  '%s stops on missing CWD and preserves valid CWD/argv',
  (entrypoint) => {
    const root = mkdtempSync(join(tmpdir(), 'freebuff-cwd-'));
    const valid = join(root, 'space ";$ project');
    mkdirSync(valid);
    try {
      for (const cwd of [join(root, 'missing'), valid]) {
        const args = ['--help', 'a b', '";$(touch injected)', ''];
        let invocation: string[] = [];
        if (entrypoint === 'launcher') {
          [, invocation] = new FreeBuffLauncher().buildCommand(
            'ubuntu',
            cwd,
            args,
          );
        } else {
          const runner: CommandRunner = {
            exec: () => {
              throw new Error('unexpected shell interpolation');
            },
            execFile: (_command, argv) => {
              if (argv[0] === 'list')
                return { exitCode: 0, stdout: 'ubuntu\n', stderr: '' };
              invocation = argv;
              return { exitCode: 0, stdout: '', stderr: '' };
            },
          };
          new ProotDistroManager(runner).runFreeBuff('ubuntu', cwd, args);
        }
        const scriptIndex = invocation.indexOf('-c') + 1;
        // Mock only the executable sink; execute the emitted CWD/argv shell intact.
        const script =
          'exec() { printf "RAN\\0%s\\0" "$PWD"; printf "%s\\0" "$@"; }; ' +
          invocation[scriptIndex];
        const result = spawnSync(
          '/bin/bash',
          [
            '--norc',
            '--noprofile',
            '-c',
            script,
            ...invocation.slice(scriptIndex + 1),
          ],
          { cwd: root, encoding: 'utf8' },
        );
        if (cwd !== valid) {
          expect(result.status).not.toBe(0);
          expect(result.stdout).toBe('');
        } else {
          expect(result.status).toBe(0);
          expect(result.stdout.split('\0')).toEqual([
            'RAN',
            valid,
            '/opt/freebuff-termux/current-freebuff/bin/freebuff',
            ...args,
            '',
          ]);
        }
      }
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  },
);
