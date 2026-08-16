import { Ndt7AppInfo, Ndt7ConnectionInfo, Ndt7Diagnostics, Ndt7EventCallbacks, Ndt7Measurement, Ndt7SpeedSummary, Ndt7TCPInfo } from '../model/Ndt7Models';
import { Ndt7WebSocketTransport, WebSocketTransportCallbacks } from '../protocol/Ndt7WebSocketTransport';
import { Ndt7Constants } from '../utils/Ndt7Constants';
import { Ndt7AbortError, Ndt7ConnectionError, Ndt7Error, Ndt7SecurityError } from '../utils/Ndt7Errors';
import { Ndt7Math } from '../utils/Ndt7Math';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xA11A;
const TAG = 'DownloadRunner';

/**
 * Download Test Runner for NDT7 Protocol (Download goodput measurement)
 */
export class DownloadRunner {
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
    downloadUrl: string,
    callbacks?: Ndt7EventCallbacks,
    testDurationMs: number = Ndt7Constants.DEFAULT_TEST_DURATION_MS,
    connectTimeoutMs: number = Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS,
    allowInsecureTransport: boolean = false
  ): Promise<Ndt7SpeedSummary> {
    if (this.isRunning) {
      throw new Ndt7Error('DownloadRunner is already running', 'ALREADY_RUNNING');
    }

    if (!downloadUrl || (!downloadUrl.startsWith('wss://') && (!allowInsecureTransport || !downloadUrl.startsWith('ws://')))) {
      throw new Ndt7SecurityError(`Insecure or invalid download URL rejected: "${downloadUrl}". wss:// (or ws:// when insecure transport is allowed) is required.`);
    }

    const durationMs = Math.max(1000, Number.isFinite(testDurationMs) ? testDurationMs : Ndt7Constants.DEFAULT_TEST_DURATION_MS);
    const timeoutMs = Math.max(1000, Number.isFinite(connectTimeoutMs) ? connectTimeoutMs : Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS);
    const watchdogMs = Math.max(durationMs + 3000, Math.floor(durationMs * 1.3));

    this.isRunning = true;
    this.isAborted = false;

    let totalBytesReceived = 0;
    let startTimeUs = 0;
    let latestDiagnostics: Ndt7Diagnostics | undefined = undefined;
    let isDurationCompleted = false;

    return new Promise<Ndt7SpeedSummary>((resolve: (value: Ndt7SpeedSummary) => void, reject: (reason?: Ndt7Error) => void) => {
      let settled = false;

      const finish = (finalSummary: Ndt7SpeedSummary): void => {
        if (!settled) {
          settled = true;
          this.pendingFail = undefined;
          this.cleanup();
          if (callbacks && callbacks.onDownloadComplete) {
            try {
              callbacks.onDownloadComplete(finalSummary);
            } catch (e) {
              hilog.warn(DOMAIN, TAG, 'onDownloadComplete callback error: %{public}s', String(e));
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
        if (callbacks && callbacks.onDownloadStart) {
          try {
            callbacks.onDownloadStart(downloadUrl);
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'onDownloadStart callback error: %{public}s', String(e));
          }
        }
        if (callbacks && callbacks.onLog) {
          try {
            callbacks.onLog(`[NDT7] Download connected: ${downloadUrl}`);
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
          const currentSummary = Ndt7Math.calculateSpeed(totalBytesReceived, elapsedUs, latestDiagnostics);
          if (callbacks && callbacks.onDownloadProgress) {
            try {
              callbacks.onDownloadProgress(currentSummary);
            } catch (e) {
              hilog.warn(DOMAIN, TAG, 'onDownloadProgress callback error: %{public}s', String(e));
            }
          }
        }, Ndt7Constants.PROGRESS_INTERVAL_MS);

        // Expected test duration timer
        this.testDurationTimerId = setTimeout(() => {
          isDurationCompleted = true;
          if (callbacks && callbacks.onLog) {
            try {
              callbacks.onLog(`[NDT7] ${durationMs}ms download test duration elapsed. Closing connection.`);
            } catch (_) {}
          }
          const nowUs = Date.now() * 1000;
          const elapsedUs = Math.max(1, nowUs - startTimeUs);
          const finalSummary = Ndt7Math.calculateSpeed(totalBytesReceived, elapsedUs, latestDiagnostics);
          this.transport?.close(1000, 'Normal test completion');
          finish(finalSummary);
        }, durationMs);

        // Dynamic Hard watchdog timer
        this.watchdogTimerId = setTimeout(() => {
          if (!settled) {
            if (callbacks && callbacks.onLog) {
              try {
                callbacks.onLog(`[NDT7] Download hard watchdog triggered after ${watchdogMs}ms.`);
              } catch (_) {}
            }
            this.transport?.close(1000, 'Watchdog timeout');
            const nowUs = Date.now() * 1000;
            const elapsedUs = Math.max(1, nowUs - startTimeUs);
            const finalSummary = Ndt7Math.calculateSpeed(totalBytesReceived, elapsedUs, latestDiagnostics);
            finish(finalSummary);
          }
        }, watchdogMs);
      };

      wsCallbacks.onBinaryMessage = (buffer: ArrayBuffer) => {
        if (!this.isRunning || settled) {
          return;
        }
        totalBytesReceived += buffer.byteLength;
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
            const validElapsed = DownloadRunner.sanitizeNonNegative(rawAppInfo['ElapsedTime']);
            const validNumBytes = DownloadRunner.sanitizeNonNegative(rawAppInfo['NumBytes']);
            measurement.AppInfo = new Ndt7AppInfo(validElapsed, validNumBytes);
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
            tcpInfo.MinRTT = DownloadRunner.sanitizeNonNegative(rawTcpInfo['MinRTT']);
            tcpInfo.RTT = DownloadRunner.sanitizeNonNegative(rawTcpInfo['RTT']);
            tcpInfo.RTTVar = DownloadRunner.sanitizeNonNegative(rawTcpInfo['RTTVar']);
            tcpInfo.BytesRetrans = DownloadRunner.sanitizeNonNegative(rawTcpInfo['BytesRetrans']);
            tcpInfo.BytesSent = DownloadRunner.sanitizeNonNegative(rawTcpInfo['BytesSent']);
            tcpInfo.BytesAcked = DownloadRunner.sanitizeNonNegative(rawTcpInfo['BytesAcked']);
            tcpInfo.BytesReceived = DownloadRunner.sanitizeNonNegative(rawTcpInfo['BytesReceived']);
            tcpInfo.ElapsedTime = DownloadRunner.sanitizeNonNegative(rawTcpInfo['ElapsedTime']);
            tcpInfo.BusyTime = DownloadRunner.sanitizeNonNegative(rawTcpInfo['BusyTime']);
            tcpInfo.RWndLimited = DownloadRunner.sanitizeNonNegative(rawTcpInfo['RWndLimited']);
            tcpInfo.SndBufLimited = DownloadRunner.sanitizeNonNegative(rawTcpInfo['SndBufLimited']);
            measurement.TCPInfo = tcpInfo;
            latestDiagnostics = Ndt7Math.extractDiagnostics(tcpInfo);
          }

          if (callbacks && callbacks.onDownloadMeasurement) {
            try {
              callbacks.onDownloadMeasurement(measurement);
            } catch (e) {
              hilog.warn(DOMAIN, TAG, 'onDownloadMeasurement callback error: %{public}s', String(e));
            }
          }
        } catch (_) {
          // Ignore non-fatal JSON parse errors on extension messages
        }
      };

      wsCallbacks.onClose = (code: number, reason: string) => {
        if (callbacks && callbacks.onLog) {
          try {
            callbacks.onLog(`[NDT7] Download closed: code=${code}, reason=${reason}`);
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
        const finalSummary = Ndt7Math.calculateSpeed(totalBytesReceived, elapsedUs, latestDiagnostics);
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

      this.transport.connect(downloadUrl, timeoutMs, allowInsecureTransport).catch((err: Ndt7Error) => {
        fail(err);
      });
    });
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
