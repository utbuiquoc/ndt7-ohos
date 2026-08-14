import { Ndt7AppInfo, Ndt7ConnectionInfo, Ndt7Diagnostics, Ndt7EventCallbacks, Ndt7Measurement, Ndt7SpeedSummary, Ndt7TCPInfo } from '../model/Ndt7Models';
import { Ndt7WebSocketTransport, WebSocketTransportCallbacks } from '../protocol/Ndt7WebSocketTransport';
import { Ndt7Constants } from '../utils/Ndt7Constants';
import { Ndt7AbortError, Ndt7Error, Ndt7TimeoutError } from '../utils/Ndt7Errors';
import { Ndt7Math } from '../utils/Ndt7Math';

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

  public async run(
    uploadUrl: string,
    callbacks?: Ndt7EventCallbacks,
    testDurationMs: number = Ndt7Constants.DEFAULT_TEST_DURATION_MS,
    connectTimeoutMs: number = Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS
  ): Promise<Ndt7SpeedSummary> {
    if (this.isRunning) {
      throw new Ndt7Error('UploadRunner is already running', 'ALREADY_RUNNING');
    }

    this.isRunning = true;
    this.isAborted = false;

    let totalBytesSent = 0;
    let startTimeUs = 0;
    let latestDiagnostics: Ndt7Diagnostics | undefined = undefined;
    let serverReportedBytes: number | undefined = undefined;

    return new Promise<Ndt7SpeedSummary>((resolve: (value: Ndt7SpeedSummary) => void, reject: (reason?: Ndt7Error) => void) => {
      let settled = false;

      const finish = (finalSummary: Ndt7SpeedSummary): void => {
        if (!settled) {
          settled = true;
          this.cleanup();
          if (callbacks && callbacks.onUploadComplete) {
            callbacks.onUploadComplete(finalSummary);
          }
          resolve(finalSummary);
        }
      };

      const fail = (error: Ndt7Error): void => {
        if (!settled) {
          settled = true;
          this.cleanup();
          if (callbacks && callbacks.onError) {
            callbacks.onError(error);
          }
          reject(error);
        }
      };

      this.transport = new Ndt7WebSocketTransport();

      const wsCallbacks = new WebSocketTransportCallbacks();

      wsCallbacks.onOpen = () => {
        startTimeUs = Date.now() * 1000;
        if (callbacks && callbacks.onUploadStart) {
          callbacks.onUploadStart(uploadUrl);
        }
        if (callbacks && callbacks.onLog) {
          callbacks.onLog(`[NDT7] Upload connected: ${uploadUrl}`);
        }

        // Periodic progress emitter (~100ms)
        this.progressTimerId = setInterval(() => {
          if (!this.isRunning || settled) {
            return;
          }
          const nowUs = Date.now() * 1000;
          const elapsedUs = Math.max(1, nowUs - startTimeUs);
          const effectiveBytes = serverReportedBytes !== undefined ? serverReportedBytes : totalBytesSent;
          const currentSummary = Ndt7Math.calculateSpeed(effectiveBytes, elapsedUs, latestDiagnostics);
          if (callbacks && callbacks.onUploadProgress) {
            callbacks.onUploadProgress(currentSummary);
          }
        }, Ndt7Constants.PROGRESS_INTERVAL_MS);

        // 10s Expected duration timer
        this.testDurationTimerId = setTimeout(() => {
          if (callbacks && callbacks.onLog) {
            callbacks.onLog('[NDT7] 10s upload test duration elapsed. Closing connection.');
          }
          const nowUs = Date.now() * 1000;
          const elapsedUs = Math.max(1, nowUs - startTimeUs);
          const effectiveBytes = serverReportedBytes !== undefined ? serverReportedBytes : totalBytesSent;
          const finalSummary = Ndt7Math.calculateSpeed(effectiveBytes, elapsedUs, latestDiagnostics);
          this.transport?.close(1000, 'Normal 10s test completion');
          finish(finalSummary);
        }, testDurationMs);

        // 13s Hard watchdog timer
        this.watchdogTimerId = setTimeout(() => {
          if (!settled) {
            if (callbacks && callbacks.onLog) {
              callbacks.onLog('[NDT7] Upload 13s hard watchdog triggered.');
            }
            this.transport?.close(1000, 'Watchdog timeout');
            const nowUs = Date.now() * 1000;
            const elapsedUs = Math.max(1, nowUs - startTimeUs);
            const effectiveBytes = serverReportedBytes !== undefined ? serverReportedBytes : totalBytesSent;
            const finalSummary = Ndt7Math.calculateSpeed(effectiveBytes, elapsedUs, latestDiagnostics);
            finish(finalSummary);
          }
        }, Ndt7Constants.HARD_WATCHDOG_TIMEOUT_MS);

        // Start active upload transmission loop
        this.startUploadLoop((sentBytes: number) => {
          totalBytesSent += sentBytes;
        }).catch((err: Object) => {
          if (!settled && this.isRunning) {
            const uploadErr = err instanceof Ndt7Error ? err : new Ndt7Error(String(err));
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
            measurement.AppInfo = new Ndt7AppInfo(rawAppInfo['ElapsedTime'], rawAppInfo['NumBytes']);
            if (rawAppInfo['NumBytes'] !== undefined) {
              serverReportedBytes = rawAppInfo['NumBytes'];
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
            tcpInfo.MinRTT = rawTcpInfo['MinRTT'];
            tcpInfo.RTT = rawTcpInfo['RTT'];
            tcpInfo.RTTVar = rawTcpInfo['RTTVar'];
            tcpInfo.BytesRetrans = rawTcpInfo['BytesRetrans'];
            tcpInfo.BytesSent = rawTcpInfo['BytesSent'];
            tcpInfo.BytesAcked = rawTcpInfo['BytesAcked'];
            tcpInfo.BytesReceived = rawTcpInfo['BytesReceived'];
            tcpInfo.ElapsedTime = rawTcpInfo['ElapsedTime'];
            tcpInfo.BusyTime = rawTcpInfo['BusyTime'];
            tcpInfo.RWndLimited = rawTcpInfo['RWndLimited'];
            tcpInfo.SndBufLimited = rawTcpInfo['SndBufLimited'];
            measurement.TCPInfo = tcpInfo;
            latestDiagnostics = Ndt7Math.extractDiagnostics(tcpInfo);
          }

          if (callbacks && callbacks.onUploadMeasurement) {
            callbacks.onUploadMeasurement(measurement);
          }
        } catch (_) {
          // Non-fatal JSON parse error
        }
      };

      wsCallbacks.onClose = (code: number, reason: string) => {
        if (callbacks && callbacks.onLog) {
          callbacks.onLog(`[NDT7] Upload closed: code=${code}, reason=${reason}`);
        }
        if (this.isAborted) {
          fail(new Ndt7AbortError());
          return;
        }
        const nowUs = Date.now() * 1000;
        const elapsedUs = Math.max(1, nowUs - (startTimeUs || nowUs));
        const effectiveBytes = serverReportedBytes !== undefined ? serverReportedBytes : totalBytesSent;
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

      this.transport.connect(uploadUrl, connectTimeoutMs).catch((err: Ndt7Error) => {
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

  /**
   * Helper to allocate an ArrayBuffer with non-zero bytes to prevent compression
   */
  private createPayloadBuffer(size: number): ArrayBuffer {
    const buffer = new ArrayBuffer(size);
    const view = new Uint8Array(buffer);
    for (let i = 0; i < size; i += 16) {
      view[i] = (i & 0xFF) || 0xAA;
    }
    return buffer;
  }

  public abort(): void {
    this.isAborted = true;
    this.cleanup();
    if (this.transport) {
      this.transport.close(1000, 'Aborted by user');
      this.transport.destroy();
      this.transport = undefined;
    }
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
