const SAFE_IDENTIFIER_PATTERN = /^[a-z0-9][a-z0-9._-]{0,63}$/i;
const PINNED_IMAGE_PATTERN = /^[a-z0-9][a-z0-9._:/-]*@sha256:[0-9a-f]{64}$/;

export const FREEBUFF_EXECUTABLE =
  '/opt/freebuff-termux/current-freebuff/bin/freebuff';
export const FREEBUFF_RUNTIME_PATH =
  '/opt/freebuff-termux/current-freebuff/bin:/opt/freebuff-termux/current-node/bin:/usr/local/bin:/usr/bin:/bin';

/**
 * proot-distro가 옵션 또는 경로로 재해석할 수 없는 식별자인지 검증한다.
 */
export function assertSafeIdentifier(
  value: string,
  kind: 'distro' | 'user',
): void {
  if (!SAFE_IDENTIFIER_PATTERN.test(value) || value === '.' || value === '..') {
    throw new Error(
      `Unsafe ${kind} identifier: expected 1-64 letters, numbers, dots, underscores, or hyphens`,
    );
  }
}

/** OCI image가 mutable tag가 아니라 SHA-256 digest에 고정됐는지 검증한다. */
export function assertPinnedImageReference(value: string): void {
  if (value.length > 512 || !PINNED_IMAGE_PATTERN.test(value)) {
    throw new Error(
      'Unsafe PRoot image: expected an OCI reference pinned with @sha256:<64 lowercase hex characters>',
    );
  }
}
