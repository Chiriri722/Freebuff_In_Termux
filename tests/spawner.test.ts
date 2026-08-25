import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import type { ChildProcess, spawn as nodeSpawn } from 'node:child_process';
import { jest } from '@jest/globals';
import { createNodeSpawner } from '../src/index.js';

const createFakeProcess = () => {
  const emitter = new EventEmitter();
  const stdout = new PassThrough();
  const stderr = new PassThrough();
  const kill = jest.fn(() => true);
  const child = Object.assign(emitter, {
    pid: 4242,
    stdout,
    stderr,
    kill,
  }) as unknown as ChildProcess;
  return { child, stdout, stderr, kill, emitter };
};

const createSpawnHarness = () => {
  const process = createFakeProcess();
  const calls: unknown[][] = [];
  const spawn = ((...args: unknown[]) => {
    calls.push(args);
    return process.child;
  }) as unknown as typeof nodeSpawn;
  return { ...process, spawn, calls };
};

describe('createNodeSpawner', () => {
  afterEach(() => {
    jest.useRealTimers();
  });

  test('caps total piped output and returns a structured termination reason', async () => {
    const harness = createSpawnHarness();
    const spawner = createNodeSpawner(harness.spawn, 'win32');
    const resultPromise = spawner.spawn('command', [], {
      stdio: 'pipe',
      maxOutputBytes: 4,
    });

    harness.stdout.write(Buffer.from('12345'));
    expect(harness.kill).toHaveBeenCalledWith('SIGTERM');
    harness.emitter.emit('close', null, 'SIGTERM');

    await expect(resultPromise).resolves.toMatchObject({
      stdout: '1234',
      outputTruncated: true,
      terminationReason: 'output-limit',
    });
  });

  test('escalates timeout from TERM to KILL after the grace period', async () => {
    jest.useFakeTimers();
    const harness = createSpawnHarness();
    const spawner = createNodeSpawner(harness.spawn, 'win32');
    const resultPromise = spawner.spawn('command', [], {
      stdio: 'pipe',
      timeout: 100,
      killGraceMs: 50,
    });

    await jest.advanceTimersByTimeAsync(100);
    expect(harness.kill).toHaveBeenCalledWith('SIGTERM');
    await jest.advanceTimersByTimeAsync(50);
    expect(harness.kill).toHaveBeenCalledWith('SIGKILL');
    harness.emitter.emit('close', null, 'SIGKILL');

    await expect(resultPromise).resolves.toMatchObject({
      terminationReason: 'timeout',
    });
  });

  test('honors AbortSignal and removes abort listeners after close', async () => {
    const harness = createSpawnHarness();
    const spawner = createNodeSpawner(harness.spawn, 'win32');
    const controller = new AbortController();
    const removeEventListener = jest.spyOn(
      controller.signal,
      'removeEventListener',
    );
    const resultPromise = spawner.spawn('command', [], {
      stdio: 'pipe',
      signal: controller.signal,
    });

    controller.abort();
    expect(harness.kill).toHaveBeenCalledWith('SIGTERM');
    harness.emitter.emit('close', null, 'SIGTERM');

    await expect(resultPromise).resolves.toMatchObject({
      terminationReason: 'abort',
    });
    expect(removeEventListener).toHaveBeenCalled();
  });

  test('does not lose an abort that races with process creation', async () => {
    const harness = createSpawnHarness();
    const controller = new AbortController();
    const spawn = ((...args: unknown[]) => {
      harness.calls.push(args);
      controller.abort();
      return harness.child;
    }) as unknown as typeof nodeSpawn;
    const resultPromise = createNodeSpawner(spawn, 'win32').spawn(
      'command',
      [],
      { signal: controller.signal },
    );

    expect(harness.kill).toHaveBeenCalledWith('SIGTERM');
    harness.emitter.emit('close', null, 'SIGTERM');
    await expect(resultPromise).resolves.toMatchObject({
      terminationReason: 'abort',
    });
  });

  test('signals the detached process group on Linux', async () => {
    const harness = createSpawnHarness();
    const killProcess = jest.fn(() => true);
    const spawner = createNodeSpawner(harness.spawn, 'linux', killProcess);
    const controller = new AbortController();
    const resultPromise = spawner.spawn('command', [], {
      signal: controller.signal,
    });

    controller.abort();
    expect(killProcess).toHaveBeenCalledWith(-4242, 'SIGTERM');
    expect(harness.calls[0][2]).toMatchObject({ detached: true, shell: false });
    harness.emitter.emit('close', null, 'SIGTERM');
    await resultPromise;
  });

  test('maps host SIGINT and SIGTERM events to the exact child signal', async () => {
    const harness = createSpawnHarness();
    const signalTarget = new EventEmitter();
    const spawner = createNodeSpawner(
      harness.spawn,
      'win32',
      process.kill,
      signalTarget,
    );
    const resultPromise = spawner.spawn('command', []);

    signalTarget.emit('SIGINT');
    signalTarget.emit('SIGTERM');

    expect(harness.kill).toHaveBeenNthCalledWith(1, 'SIGINT');
    expect(harness.kill).toHaveBeenNthCalledWith(2, 'SIGTERM');
    harness.emitter.emit('close', null, 'SIGTERM');
    await resultPromise;
    expect(signalTarget.listenerCount('SIGINT')).toBe(0);
    expect(signalTarget.listenerCount('SIGTERM')).toBe(0);
  });

  test('escalates a forwarded host signal when the child does not exit', async () => {
    jest.useFakeTimers();
    const harness = createSpawnHarness();
    const signalTarget = new EventEmitter();
    const spawner = createNodeSpawner(
      harness.spawn,
      'win32',
      process.kill,
      signalTarget,
    );
    const resultPromise = spawner.spawn('command', [], { killGraceMs: 25 });

    signalTarget.emit('SIGTERM');
    expect(harness.kill).toHaveBeenCalledWith('SIGTERM');
    await jest.advanceTimersByTimeAsync(25);
    expect(harness.kill).toHaveBeenCalledWith('SIGKILL');

    harness.emitter.emit('close', null, 'SIGKILL');
    await resultPromise;
  });
});
