import { Ndt7AppInfo, Ndt7ConnectionInfo, Ndt7Diagnostics, Ndt7EventCallbacks, Ndt7Measurement, Ndt7SpeedSummary, Ndt7TCPInfo } from '../model/Ndt7Models';
import { Ndt7WebSocketTransport, WebSocketTransportCallbacks } from '../protocol/Ndt7WebSocketTransport';
import { Ndt7Constants } from '../utils/Ndt7Constants';
import { Ndt7AbortError, Ndt7ConnectionError, Ndt7Error, Ndt7SecurityError } from '../utils/Ndt7Errors';
import { Ndt7Math } from '../utils/Ndt7Math';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xA11A;
const TAG = 'UploadRunner';

/**
 * Upload Test Runner for NDT7 Protocol (Upload goodput measurement with dynamic sizing)
 */
export class UploadRunner {
  private transport?: Ndt7WebSocketTransport;
  private isRunning: boolean = false;
  private isAborted: boolean = false;
  private testDurationTimerId: number = -1;
  private watchdogTimerId: number = -1;
  private progressTimerId: number = -1;
  private pendingFail?: (reason: Ndt7Error) => void;

  private static sanitizeNonNegative(value: number | undefined): number | undefined {
    return (value !== undefined && Number.isFinite(value) && value >= 0) ? value : undefined;
  }

  public async run(
    uploadUrl: string,
    callbacks?: Ndt7EventCallbacks,
    testDurationMs: number = Ndt7Constants.DEFAULT_TEST_DURATION_MS,
    connectTimeoutMs: number = Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS,
    allowInsecureTransport: boolean = false
  ): Promise<Ndt7SpeedSummary> {
    if (this.isRunning) {
      throw new Ndt7Error('UploadRunner is already running', 'ALREADY_RUNNING');
    }

    if (!uploadUrl || (!uploadUrl.startsWith('wss://') && (!allowInsecureTransport || !uploadUrl.startsWith('ws://')))) {
      throw new Ndt7SecurityError(`Insecure or invalid upload URL rejected: "${uploadUrl}". wss:// (or ws:// when insecure transport is allowed) is required.`);
    }

    const durationMs = Math.max(1000, Number.isFinite(testDurationMs) ? testDurationMs : Ndt7Constants.DEFAULT_TEST_DURATION_MS);
    const timeoutMs = Math.max(1000, Number.isFinite(connectTimeoutMs) ? connectTimeoutMs : Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS);
    const watchdogMs = Math.max(durationMs + 3000, Math.floor(durationMs * 1.3));

    this.isRunning = true;
    this.isAborted = false;

    let totalBytesSent = 0;
    let startTimeUs = 0;
    let latestDiagnostics: Ndt7Diagnostics | undefined = undefined;
    let serverReportedBytes: number | undefined = undefined;
    let isDurationCompleted = false;

    return new Promise<Ndt7SpeedSummary>((resolve: (value: Ndt7SpeedSummary) => void, reject: (reason?: Ndt7Error) => void) => {
      let settled = false;

      const finish = (finalSummary: Ndt7SpeedSummary): void => {
        if (!settled) {
          settled = true;
          this.pendingFail = undefined;
          this.cleanup();
          if (callbacks && callbacks.onUploadComplete) {
            try {
              callbacks.onUploadComplete(finalSummary);
            } catch (e) {
              hilog.warn(DOMAIN, TAG, 'onUploadComplete callback error: %{public}s', String(e));
            }
          }
          resolve(finalSummary);
        }
      };

      const fail = (error: Ndt7Error): void => {
        if (!settled) {
          settled = true;
          this.pendingFail = undefined;
          this.cleanup();
          if (callbacks && callbacks.onError) {
            try {
              callbacks.onError(error);
            } catch (e) {
              hilog.warn(DOMAIN, TAG, 'onError callback error: %{public}s', String(e));
            }
          }
          reject(error);
        }
      };

      this.pendingFail = fail;
      this.transport = new Ndt7WebSocketTransport();

      const wsCallbacks = new WebSocketTransportCallbacks();

      wsCallbacks.onOpen = () => {
        if (this.isAborted || settled) {
          return;
        }
        startTimeUs = Date.now() * 1000;
        if (callbacks && callbacks.onUploadStart) {
          try {
            callbacks.onUploadStart(uploadUrl);
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'onUploadStart callback error: %{public}s', String(e));
          }
        }
        if (callbacks && callbacks.onLog) {
          try {
            callbacks.onLog(`[NDT7] Upload connected: ${uploadUrl}`);
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'onLog callback error: %{public}s', String(e));
          }
        }

        // Periodic progress emitter (~100ms)
        this.progressTimerId = setInterval(() => {
          if (!this.isRunning || settled) {
            return;
          }
          const nowUs = Date.now() * 1000;
          const elapsedUs = Math.max(1, nowUs - startTimeUs);
          const effectiveBytes = (serverReportedBytes !== undefined && serverReportedBytes > 0) ? serverReportedBytes : totalBytesSent;
          const currentSummary = Ndt7Math.calculateSpeed(effectiveBytes, elapsedUs, latestDiagnostics);
          if (callbacks && callbacks.onUploadProgress) {
            try {
              callbacks.onUploadProgress(currentSummary);
            } catch (e) {
              hilog.warn(DOMAIN, TAG, 'onUploadProgress callback error: %{public}s', String(e));
            }
          }
        }, Ndt7Constants.PROGRESS_INTERVAL_MS);

        // Expected test duration timer
        this.testDurationTimerId = setTimeout(() => {
          isDurationCompleted = true;
          if (callbacks && callbacks.onLog) {
            try {
              callbacks.onLog(`[NDT7] ${durationMs}ms upload test duration elapsed. Closing connection.`);
            } catch (_) {}
          }
          const nowUs = Date.now() * 1000;
          const elapsedUs = Math.max(1, nowUs - startTimeUs);
          const effectiveBytes = (serverReportedBytes !== undefined && serverReportedBytes > 0) ? serverReportedBytes : totalBytesSent;
          const finalSummary = Ndt7Math.calculateSpeed(effectiveBytes, elapsedUs, latestDiagnostics);
          this.transport?.close(1000, 'Normal test completion');
          finish(finalSummary);
        }, durationMs);

        // Dynamic Hard watchdog timer
        this.watchdogTimerId = setTimeout(() => {
          if (!settled) {
            if (callbacks && callbacks.onLog) {
              try {
                callbacks.onLog(`[NDT7] Upload hard watchdog triggered after ${watchdogMs}ms.`);
              } catch (_) {}
            }
            this.transport?.close(1000, 'Watchdog timeout');
            const nowUs = Date.now() * 1000;
            const elapsedUs = Math.max(1, nowUs - startTimeUs);
            const effectiveBytes = (serverReportedBytes !== undefined && serverReportedBytes > 0) ? serverReportedBytes : totalBytesSent;
            const finalSummary = Ndt7Math.calculateSpeed(effectiveBytes, elapsedUs, latestDiagnostics);
            finish(finalSummary);
          }
        }, watchdogMs);

        // Start active upload transmission loop
        this.startUploadLoop((sentBytes: number) => {
          totalBytesSent += sentBytes;
        }).catch((err: Object) => {
          if (!settled && this.isRunning) {
            const uploadErr = err instanceof Ndt7Error ? (err as Ndt7Error) : new Ndt7Error(String(err));
            fail(uploadErr);
          }
        });
      };

      wsCallbacks.onTextMessage = (text: string) => {
        if (!this.isRunning || settled) {
          return;
        }
        try {
          const parsed = JSON.parse(text) as Record<string, Object>;
          const measurement = new Ndt7Measurement();
          measurement.rawJson = text;
          measurement.Origin = parsed['Origin'] as 'client' | 'server' | undefined;
          measurement.Test = parsed['Test'] as 'download' | 'upload' | undefined;

          const rawAppInfo = parsed['AppInfo'] as Record<string, number> | undefined;
          if (rawAppInfo) {
            const validElapsed = UploadRunner.sanitizeNonNegative(rawAppInfo['ElapsedTime']);
            const validNumBytes = UploadRunner.sanitizeNonNegative(rawAppInfo['NumBytes']);
            measurement.AppInfo = new Ndt7AppInfo(validElapsed, validNumBytes);

            if (validNumBytes !== undefined) {
              serverReportedBytes = validNumBytes;
            }
          }

          const rawConnInfo = parsed['ConnectionInfo'] as Record<string, string> | undefined;
          if (rawConnInfo) {
            measurement.ConnectionInfo = new Ndt7ConnectionInfo(
              rawConnInfo['Client'],
              rawConnInfo['Server'],
              rawConnInfo['UUID'],
              rawConnInfo['StartTime']
            );
          }

          const rawTcpInfo = parsed['TCPInfo'] as Record<string, number> | undefined;
          if (rawTcpInfo) {
            const tcpInfo = new Ndt7TCPInfo();
            tcpInfo.MinRTT = UploadRunner.sanitizeNonNegative(rawTcpInfo['MinRTT']);
            tcpInfo.RTT = UploadRunner.sanitizeNonNegative(rawTcpInfo['RTT']);
            tcpInfo.RTTVar = UploadRunner.sanitizeNonNegative(rawTcpInfo['RTTVar']);
            tcpInfo.BytesRetrans = UploadRunner.sanitizeNonNegative(rawTcpInfo['BytesRetrans']);
            tcpInfo.BytesSent = UploadRunner.sanitizeNonNegative(rawTcpInfo['BytesSent']);
            tcpInfo.BytesAcked = UploadRunner.sanitizeNonNegative(rawTcpInfo['BytesAcked']);
            tcpInfo.BytesReceived = UploadRunner.sanitizeNonNegative(rawTcpInfo['BytesReceived']);
            tcpInfo.ElapsedTime = UploadRunner.sanitizeNonNegative(rawTcpInfo['ElapsedTime']);
            tcpInfo.BusyTime = UploadRunner.sanitizeNonNegative(rawTcpInfo['BusyTime']);
            tcpInfo.RWndLimited = UploadRunner.sanitizeNonNegative(rawTcpInfo['RWndLimited']);
            tcpInfo.SndBufLimited = UploadRunner.sanitizeNonNegative(rawTcpInfo['SndBufLimited']);
            measurement.TCPInfo = tcpInfo;
            latestDiagnostics = Ndt7Math.extractDiagnostics(tcpInfo);
          }

          if (callbacks && callbacks.onUploadMeasurement) {
            try {
              callbacks.onUploadMeasurement(measurement);
            } catch (e) {
              hilog.warn(DOMAIN, TAG, 'onUploadMeasurement callback error: %{public}s', String(e));
            }
          }
        } catch (_) {
          // Non-fatal JSON parse error
        }
      };

      wsCallbacks.onClose = (code: number, reason: string) => {
        if (callbacks && callbacks.onLog) {
          try {
            callbacks.onLog(`[NDT7] Upload closed: code=${code}, reason=${reason}`);
          } catch (_) {}
        }
        if (this.isAborted) {
          fail(new Ndt7AbortError());
          return;
        }

        // If closed abnormally before duration completed, treat as failure
        if (code !== 1000 && code !== 1001 && code !== 1005 && !isDurationCompleted) {
          fail(new Ndt7ConnectionError(`WebSocket closed prematurely or abnormally: code=${code}, reason=${reason}`));
          return;
        }

        const nowUs = Date.now() * 1000;
        const elapsedUs = Math.max(1, nowUs - (startTimeUs || nowUs));
        const effectiveBytes = (serverReportedBytes !== undefined && serverReportedBytes > 0) ? serverReportedBytes : totalBytesSent;
        const finalSummary = Ndt7Math.calculateSpeed(effectiveBytes, elapsedUs, latestDiagnostics);
        finish(finalSummary);
      };

      wsCallbacks.onError = (error: Ndt7Error) => {
        if (this.isAborted) {
          fail(new Ndt7AbortError());
        } else {
          fail(error);
        }
      };

      this.transport.setCallbacks(wsCallbacks);

      this.transport.connect(uploadUrl, timeoutMs, allowInsecureTransport).catch((err: Ndt7Error) => {
        fail(err);
      });
    });
  }

  /**
   * Upload transmission loop implementing NDT7 v0.11.0 dynamic message sizing:
   * Starts at 8 KiB (1 << 13), doubles when messageSize < 16 MiB (1 << 24) && messageSize < totalSent / 16.
   * Single active buffer is reused and only reallocated on size step-up.
   */
  private async startUploadLoop(onChunkSent: (size: number) => void): Promise<void> {
    let messageSize = Ndt7Constants.INITIAL_UPLOAD_CHUNK_SIZE; // 8 KiB
    let totalSent = 0;

    // Single active buffer allocation
    let currentBuffer = this.createPayloadBuffer(messageSize);

    while (this.isRunning && this.transport) {
      const ok = await this.transport.send(currentBuffer);
      if (!ok || !this.isRunning) {
        break;
      }

      totalSent += messageSize;
      onChunkSent(messageSize);

      // Check dynamic scaling per NDT7 spec appendix
      if (messageSize < Ndt7Constants.MAX_UPLOAD_CHUNK_SIZE && messageSize < Math.floor(totalSent / 16)) {
        messageSize *= 2;
        if (messageSize > Ndt7Constants.MAX_UPLOAD_CHUNK_SIZE) {
          messageSize = Ndt7Constants.MAX_UPLOAD_CHUNK_SIZE;
        }
        // Allocate next buffer and release old reference
        currentBuffer = this.createPayloadBuffer(messageSize);
      }
    }
  }

  private static readonly SEED_BLOCK_SIZE: number = 65536; // 64 KiB
  private static seedBlock?: Uint8Array;

  private static getSeedBlock(): Uint8Array {
    if (!UploadRunner.seedBlock) {
      const block = new Uint8Array(UploadRunner.SEED_BLOCK_SIZE);
      // Fast linear congruential generator (LCG) to fill with non-zero pseudo-random bytes
      let state = 0x12345678;
      for (let i = 0; i < UploadRunner.SEED_BLOCK_SIZE; i++) {
        state = (state * 1664525 + 1013904223) >>> 0;
        block[i] = (state & 0xFF) || 0xAA;
      }
      UploadRunner.seedBlock = block;
    }
    return UploadRunner.seedBlock;
  }

  /**
   * Helper to allocate an ArrayBuffer filled 100% with non-zero pseudo-random bytes
   * to prevent compression by middleboxes or proxies.
   */
  private createPayloadBuffer(size: number): ArrayBuffer {
    const buffer = new ArrayBuffer(size);
    const view = new Uint8Array(buffer);
    const seed = UploadRunner.getSeedBlock();
    let offset = 0;
    while (offset < size) {
      const chunkLen = Math.min(seed.byteLength, size - offset);
      if (chunkLen === seed.byteLength) {
        view.set(seed, offset);
      } else {
        view.set(seed.subarray(0, chunkLen), offset);
      }
      offset += chunkLen;
    }
    return buffer;
  }

  public abort(): void {
    this.isAborted = true;
    if (this.pendingFail) {
      const failFn = this.pendingFail;
      this.pendingFail = undefined;
      failFn(new Ndt7AbortError());
    }
    this.cleanup();
  }

  private cleanup(): void {
    this.isRunning = false;
    if (this.testDurationTimerId !== -1) {
      clearTimeout(this.testDurationTimerId);
      this.testDurationTimerId = -1;
    }
    if (this.watchdogTimerId !== -1) {
      clearTimeout(this.watchdogTimerId);
      this.watchdogTimerId = -1;
    }
    if (this.progressTimerId !== -1) {
      clearInterval(this.progressTimerId);
      this.progressTimerId = -1;
    }
    if (this.transport) {
      this.transport.destroy();
      this.transport = undefined;
    }
  }
}
