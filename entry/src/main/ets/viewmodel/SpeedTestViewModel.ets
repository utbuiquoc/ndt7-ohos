import {
  LocateServer,
  Ndt7AbortError,
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
const FALLBACK_ERROR_LABEL = 'Test failed. Please try again.';

/**
 * ViewModel orchestrating NDT7 tests for the wearable UI
 */
@ObservedV2
export class SpeedTestViewModel {
  @Trace public state: Ndt7State = Ndt7State.IDLE;
  @Trace public statusMessage: string = 'Ready';
  @Trace public downloadMbps: number = 0;
  @Trace public uploadMbps: number = 0;
  @Trace public serverName: string = 'Auto (Locate API)';
  @Trace public serverCity: string = '';
  @Trace public latencyMs: number = 0;
  @Trace public retransPercent: number = 0;
  @Trace public userAcceptedDataPolicy: boolean = false;
  public logs: string[] = [];

  private client: Ndt7Client = new Ndt7Client();
  private onUpdateCallback?: () => void;
  private context?: Context;

  /**
   * Allows tests to inject a stubbed Ndt7Client; production callers
   * keep using the parameterless constructor.
   */
  constructor(client?: Ndt7Client) {
    if (client) {
      this.client = client;
    }
  }

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

  public async revokePolicy(context: Context): Promise<void> {
    this.context = context;
    await ConsentPreferencesManager.getInstance().setPolicyAccepted(context, false);
    this.userAcceptedDataPolicy = false;
    if (this.isRunning()) {
      this.cancelSpeedTest();
    }
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
    this.logs = [newEntry, ...this.logs.slice(0, 49)];
    hilog.debug(DOMAIN, TAG, '%{public}s', msg);
    // Note: Do NOT call this.notify() here — logs are internal diagnostics and should not trigger UI re-renders
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
            if (state === Ndt7State.FAILED) {
              this.applyFriendlyError(msg ? msg : String(state));
            } else {
              // statusMessage must stay a string; internal errors must never leak to the UI
              this.statusMessage = msg ? msg : '';
            }
            this.notify();
          },
          onServerDiscovery: (url: string) => {
            this.addLog(`Discovering: ${url}`);
          },
          onServerChosen: (server: LocateServer) => {
            this.serverName = server.machine;
            const city = server.location ? (server.location.city || '') : '';
            const country = server.location ? (server.location.country || '') : '';
            this.serverCity = [city, country].filter((part: string) => part.length > 0).join(', ');
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
            this.applyFriendlyError(err.message);
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
      if (err instanceof Ndt7AbortError || this.client.getState() === Ndt7State.CANCELED || this.state === Ndt7State.CANCELED) {
        this.state = Ndt7State.CANCELED;
        this.statusMessage = this.resolveStatusLabel('status_canceled', 'Canceled');
        this.addLog('Speed test was canceled');
      } else {
        this.state = Ndt7State.FAILED;
        const errMsg = err instanceof Error ? err.message : String(err);
        this.applyFriendlyError(errMsg);
        this.addLog(`ERROR: ${errMsg}`);
      }
      await ScreenAwakeManager.setKeepScreenOn(this.context, false);
      this.notify();
    }
  }

  /**
   * Resolves a status label from resources with a hardcoded fallback,
   * mirroring the resolution pattern used by applyFriendlyError.
   */
  private resolveStatusLabel(key: string, fallback: string): string {
    if (this.context) {
      try {
        const label = this.context.resourceManager.getStringByNameSync(key);
        if (label.length > 0) {
          return label;
        }
      } catch (_e) {
        // Fall through to the hardcoded fallback
      }
    }
    return fallback;
  }

  /**
   * Maps raw technical error text to a short, user-friendly label resolved
   * from resources. Case-insensitive with priority: timeout before network.
   */
  private applyFriendlyError(raw: string): void {
    const m = raw.toLowerCase();
    let key = 'status_err_generic';
    if (m.includes('timed out') || m.includes('timeout')) {
      key = 'status_err_timeout';
    } else if (m.includes('policy') || m.includes('consent')) {
      key = 'status_err_consent';
    } else if (m.includes('cannot start') || m.includes('invalid_state') || m.includes('in progress')) {
      key = 'status_err_in_progress';
    } else if (m.includes('network error while contacting locate') || m.includes('offline')) {
      key = 'status_err_network';
    } else if (m.includes('locate') || m.includes('no measurement servers') || m.includes('no servers') || m.includes('all candidate servers failed')) {
      key = 'status_err_server';
    } else if (m.includes('network') || m.includes('connect') || m.includes('websocket') || m.includes('closed prematurely') || m.includes('socket')) {
      key = 'status_err_network';
    } else if (m.includes('abort') || m.includes('cancel')) {
      key = 'status_canceled';
    }

    let label: string = '';
    if (this.context) {
      try {
        label = this.context.resourceManager.getStringByNameSync(key);
      } catch (_e) {
        label = '';
      }
    }
    if (label.length === 0) {
      // Fallback if resourceManager is unavailable or key resolution failed
      if (this.context) {
        try {
          label = this.context.resourceManager.getStringByNameSync('status_err_generic');
        } catch (_e2) {
          label = FALLBACK_ERROR_LABEL;
        }
      } else {
        label = FALLBACK_ERROR_LABEL;
      }
    }
    this.statusMessage = label;
  }

  public cancelSpeedTest(): void {
    this.addLog('Aborting speed test...');
    this.client.abort();
    this.state = this.client.getState();
    ScreenAwakeManager.setKeepScreenOn(this.context, false).catch(() => {});
    this.notify();
  }
}