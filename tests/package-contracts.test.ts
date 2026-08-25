import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

type PackageManifest = {
  main?: string;
  types?: string;
  files?: string[];
  exports?: Record<string, unknown>;
  engines?: Record<string, string>;
  repository?: { type?: string; url?: string };
  bugs?: { url?: string };
  homepage?: string;
  scripts?: Record<string, string>;
};

const manifest = JSON.parse(
  readFileSync(resolve(process.cwd(), 'package.json'), 'utf8'),
) as PackageManifest;

describe('npm package contract', () => {
  test('publishes only runtime artifacts and operator assets', () => {
    expect(manifest.files).toEqual([
      'dist',
      'scripts',
      'skill',
      'README.md',
      'CHANGELOG.md',
      'LICENSE',
    ]);
  });

  test('declares an ESM entry point and TypeScript declarations', () => {
    expect(manifest.main).toBe('./dist/index.js');
    expect(manifest.types).toBe('./dist/index.d.ts');
    expect(manifest.exports).toEqual({
      '.': {
        types: './dist/index.d.ts',
        import: './dist/index.js',
        default: './dist/index.js',
      },
    });
  });

  test('builds before packing and exposes support metadata', () => {
    expect(manifest.scripts?.prepack).toBe('npm run build');
    expect(manifest.engines?.node).toBe('>=18');
    expect(manifest.repository).toEqual({
      type: 'git',
      url: 'git+https://github.com/Chiriri722/Freebuff_In_Termux.git',
    });
    expect(manifest.bugs?.url).toBe(
      'https://github.com/Chiriri722/Freebuff_In_Termux/issues',
    );
    expect(manifest.homepage).toBe(
      'https://github.com/Chiriri722/Freebuff_In_Termux#readme',
    );
  });

  test('defines an isolated packed-consumer smoke gate', () => {
    expect(manifest.scripts?.['test:package-consumer']).toBe(
      'node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand tests/package-consumer.test.ts',
    );
  });
});
