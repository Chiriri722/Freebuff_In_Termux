import { readFileSync } from 'node:fs';

const read = (path: string): string =>
  readFileSync(new URL(path, import.meta.url), 'utf8');

const readme = read('../README.md');
const hermes = read('../skill/freebuff-hermes-integration/SKILL.md');
const api = read(
  '../skill/freebuff-hermes-integration/references/freebuff_termux_api.md',
);
const architecture = read('../docs/ARCHITECTURE.md');
const compatibility = read('../docs/ANDROID_COMPATIBILITY.md');
const evidenceTemplate = read('../docs/termux-evidence/TEMPLATE.md');

describe('documentation contracts', () => {
  test('documents immutable installation without mutable main curl pipes', () => {
    expect(readme).not.toContain('/main/scripts/remote-install.sh | bash');
    expect(readme).toContain('FREEBUFF_TERMUX_REF');
    expect(readme).toContain('FREEBUFF_TERMUX_EXPECTED_COMMIT');
    expect(readme).toContain('scripts/install.sh');
    expect(readme).toContain('FREEBUFF_PROOT_IMAGE');
  });

  test('documents lifecycle, JSON doctor, and storage opt-in', () => {
    expect(readme).toContain('freebuff-termux doctor --json');
    expect(readme).toContain('freebuff-termux repair');
    expect(readme).toContain('freebuff-termux uninstall');
    expect(readme).toContain('FREEBUFF_STORAGE_BIND=1');
    expect(readme).toContain('--isolated --shared-home');
    expect(readme).toMatch(/evidence/i);
  });

  test('Hermes guidance handles unknown OOM and configured distro', () => {
    expect(hermes).toContain("oom.level === 'unknown'");
    expect(hermes).toContain('freebuff-termux doctor --json');
    expect(hermes).toContain('storageBind: true');
  });

  test('API reference matches structured runner and current config types', () => {
    expect(api).toContain('execFile(command, args');
    expect(api).toContain('storageBind?: boolean');
    expect(api).toContain("'unknown' | 'safe' | 'caution' | 'danger'");
    expect(api).toContain('BindMountError');
    expect(api).toContain('createNodeSpawner');
    expect(api).not.toContain('execSync');
  });

  test('active architecture and compatibility docs are evidence-based', () => {
    expect(architecture).toContain('--isolated --shared-home');
    expect(architecture).toContain('digest-pinned');
    expect(architecture).not.toContain('Bun runtime');
    expect(compatibility).toContain('실제 Termux 기기 evidence');
    expect(compatibility).not.toContain('✅');
  });

  test('ships a pending, redacted Termux evidence template', () => {
    expect(evidenceTemplate).toContain('status: pending');
    expect(evidenceTemplate).toContain('status: passed');
    expect(evidenceTemplate).toMatch(/Never record tokens, login URLs/);
    expect(evidenceTemplate).toContain('exact tested runtime `commit`');
    expect(evidenceTemplate).toContain('evidence-only commit');
    expect(evidenceTemplate).toContain('only path changed');
  });
});
