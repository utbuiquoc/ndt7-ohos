import {
  LocateServer,
  Ndt7Client,
  Ndt7Measurement,
  Ndt7SpeedSummary,
  Ndt7State,
  Ndt7TestResult
} from '@mlab/ndt7-ohos';
import { ScreenAwakeManager } from '../utils/ScreenAwakeManager';
import { ConsentPreferencesManager } from '../utils/ConsentPreferencesManager';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xA11A;
const TAG = 'SpeedTestVM';

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
  public userAcceptedDataPolicy: boolean = false;

  private client: Ndt7Client = new Ndt7Client();
  private onUpdateCallback?: () => void;
  private context?: Context;

  public setContext(context: Context): void {
    this.context = context;
  }

  public setOnUpdate(callback?: () => void): void {
    this.onUpdateCallback = callback;
  }

  public setUserAcceptedDataPolicy(accepted: boolean): void {
    this.userAcceptedDataPolicy = accepted;
  }

  public async loadConsent(context: Context): Promise<boolean> {
    this.context = context;
    const accepted = await ConsentPreferencesManager.getInstance().isPolicyAccepted(context);
    this.userAcceptedDataPolicy = accepted;
    this.notify();
    return accepted;
  }

  public async acceptPolicy(context: Context): Promise<void> {
    this.context = context;
    await ConsentPreferencesManager.getInstance().setPolicyAccepted(context, true);
    this.userAcceptedDataPolicy = true;
    this.notify();
  }

  private notify(): void {
    if (this.onUpdateCallback) {
      try {
        this.onUpdateCallback();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'onUpdateCallback error: %{public}s', String(e));
      }
    }
  }

  public addLog(msg: string): void {
    const timestamp = new Date().toTimeString().split(' ')[0];
    const newEntry = `[${timestamp}] ${msg}`;
    // Replace array reference immutably so ArkUI state observers detect changes
    this.logs = [newEntry, ...this.logs.slice(0, 49)];
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
          userAcceptedDataPolicy: this.userAcceptedDataPolicy,
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
            ScreenAwakeManager.setKeepScreenOn(this.context, false).catch(() => {});
            this.notify();
          },
          onError: (err: Error) => {
            this.state = this.client.getState();
            this.addLog(`ERROR: ${err.message}`);
            ScreenAwakeManager.setKeepScreenOn(this.context, false).catch(() => {});
            this.notify();
          },
          onLog: (msg: string) => {
            this.addLog(msg);
          }
        }
      );
    } catch (err) {
      this.state = Ndt7State.FAILED;
      const errMsg = err instanceof Error ? err.message : String(err);
      this.statusMessage = errMsg;
      this.addLog(`ERROR: ${errMsg}`);
      await ScreenAwakeManager.setKeepScreenOn(this.context, false);
      this.notify();
    }
  }

  public cancelSpeedTest(): void {
    this.addLog('Aborting speed test...');
    this.client.abort();
    this.state = this.client.getState();
    ScreenAwakeManager.setKeepScreenOn(this.context, false).catch(() => {});
    this.notify();
  }
}
