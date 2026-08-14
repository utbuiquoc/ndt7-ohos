import {
  LocateServer,
  Ndt7Client,
  Ndt7Measurement,
  Ndt7SpeedSummary,
  Ndt7State,
  Ndt7TestResult
} from '@mlab/ndt7-ohos';
import { ScreenAwakeManager } from '../utils/ScreenAwakeManager';

/**
 * ViewModel orchestrating NDT7 tests for the Wearable Test Harness UI
 */
export class SpeedTestViewModel {
  public state: Ndt7State = Ndt7State.IDLE;
  public statusMessage: string = 'Ready';
  public downloadMbps: number = 0;
  public uploadMbps: number = 0;
  public serverName: string = 'Auto (Locate API)';
  public serverCity: string = '';
  public latencyMs: number = 0;
  public retransPercent: number = 0;
  public logs: string[] = [];

  private client: Ndt7Client = new Ndt7Client();
  private onUpdateCallback?: () => void;
  private context?: Context;

  public setContext(context: Context): void {
    this.context = context;
  }

  public setOnUpdate(callback: () => void): void {
    this.onUpdateCallback = callback;
  }

  private notify(): void {
    if (this.onUpdateCallback) {
      this.onUpdateCallback();
    }
  }

  public addLog(msg: string): void {
    const timestamp = new Date().toTimeString().split(' ')[0];
    this.logs.unshift(`[${timestamp}] ${msg}`);
    if (this.logs.length > 50) {
      this.logs.pop();
    }
    this.notify();
  }

  public isRunning(): boolean {
    return this.state !== Ndt7State.IDLE &&
      this.state !== Ndt7State.COMPLETED &&
      this.state !== Ndt7State.CANCELED &&
      this.state !== Ndt7State.FAILED;
  }

  public async startSpeedTest(context?: Context): Promise<void> {
    if (this.isRunning()) {
      return;
    }

    if (context) {
      this.context = context;
    }

    // Keep screen awake during speed test
    await ScreenAwakeManager.setKeepScreenOn(this.context, true);

    this.downloadMbps = 0;
    this.uploadMbps = 0;
    this.latencyMs = 0;
    this.retransPercent = 0;
    this.logs = [];
    this.addLog('Starting NDT7 Speed Test...');

    try {
      await this.client.startTest(
        {
          userAcceptedDataPolicy: true, // App confirms user policy consent
          metadata: {
            'client_name': 'ndt7-wearable-harness',
            'client_version': '1.0.0'
          }
        },
        {
          onStateChange: (state: Ndt7State, msg?: string) => {
            this.state = state;
            this.statusMessage = msg || state;
            this.notify();
          },
          onServerDiscovery: (url: string) => {
            this.addLog(`Discovering: ${url}`);
          },
          onServerChosen: (server: LocateServer) => {
            this.serverName = server.machine;
            this.serverCity = server.location ? `${server.location.city || ''}, ${server.location.country || ''}` : '';
            this.addLog(`Selected Server: ${server.machine} (${this.serverCity})`);
          },
          onDownloadStart: (_url: string) => {
            this.addLog('WSS Download connected. Receiving bytes...');
          },
          onDownloadProgress: (summary: Ndt7SpeedSummary) => {
            this.downloadMbps = summary.mbps;
            if (summary.diagnostics) {
              if (summary.diagnostics.rttUs) {
                this.latencyMs = Math.round(summary.diagnostics.rttUs / 1000.0);
              }
              if (summary.diagnostics.retransmissionRate !== undefined) {
                this.retransPercent = summary.diagnostics.retransmissionRate;
              }
            }
            this.notify();
          },
          onDownloadComplete: (summary: Ndt7SpeedSummary) => {
            this.downloadMbps = summary.mbps;
            this.addLog(`Download Complete: ${summary.mbps.toFixed(2)} Mbps (${(summary.bytes / 1048576).toFixed(1)} MB)`);
          },
          onDownloadMeasurement: (m: Ndt7Measurement) => {
            if (m.TCPInfo && m.TCPInfo.RTT) {
              this.latencyMs = Math.round(m.TCPInfo.RTT / 1000.0);
            }
          },
          onUploadStart: (_url: string) => {
            this.addLog('WSS Upload connected. Sending bytes...');
          },
          onUploadProgress: (summary: Ndt7SpeedSummary) => {
            this.uploadMbps = summary.mbps;
            this.notify();
          },
          onUploadComplete: (summary: Ndt7SpeedSummary) => {
            this.uploadMbps = summary.mbps;
            this.addLog(`Upload Complete: ${summary.mbps.toFixed(2)} Mbps (${(summary.bytes / 1048576).toFixed(1)} MB)`);
          },
          onComplete: (result: Ndt7TestResult) => {
            this.state = this.client.getState();
            this.addLog(`Test Sequence Completed (${result.status})`);
            // Release screen lock on finish
            ScreenAwakeManager.setKeepScreenOn(this.context, false);
            this.notify();
          },
          onError: (err: Error) => {
            this.state = this.client.getState();
            this.addLog(`ERROR: ${err.message}`);
            // Release screen lock on error
            ScreenAwakeManager.setKeepScreenOn(this.context, false);
            this.notify();
          },
          onLog: (msg: string) => {
            this.addLog(msg);
          }
        }
      );
    } catch (_) {
      // Release screen lock on exception
      await ScreenAwakeManager.setKeepScreenOn(this.context, false);
    }
  }

  public cancelSpeedTest(): void {
    this.addLog('Aborting speed test...');
    this.client.abort();
    this.state = this.client.getState();
    // Release screen lock on abort
    ScreenAwakeManager.setKeepScreenOn(this.context, false);
    this.notify();
  }
}
