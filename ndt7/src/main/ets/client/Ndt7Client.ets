import { LocateClient } from '../discovery/LocateClient';
import {
  LocateResult,
  LocateServer,
  Ndt7Config,
  Ndt7EventCallbacks,
  Ndt7SpeedSummary,
  Ndt7State,
  Ndt7TestResult
} from '../model/Ndt7Models';
import { DownloadRunner } from '../transfer/DownloadRunner';
import { UploadRunner } from '../transfer/UploadRunner';
import { Ndt7Constants } from '../utils/Ndt7Constants';
import { Ndt7AbortError, Ndt7Error, Ndt7PolicyError, Ndt7SecurityError } from '../utils/Ndt7Errors';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xA11A;
const TAG = 'Ndt7Client';

/**
 * Public NDT7 Client Facade for HarmonyOS ArkTS
 */
export class Ndt7Client {
  private state: Ndt7State = Ndt7State.IDLE;
  private locateClient: LocateClient = new LocateClient();
  private downloadRunner?: DownloadRunner;
  private uploadRunner?: UploadRunner;
  private isAborted: boolean = false;
  private runGeneration: number = 0;

  public getState(): Ndt7State {
    return this.state;
  }

  private isRunningState(s: Ndt7State): boolean {
    return s === Ndt7State.DISCOVERING ||
      s === Ndt7State.DOWNLOAD_CONNECTING ||
      s === Ndt7State.DOWNLOAD_RUNNING ||
      s === Ndt7State.UPLOAD_CONNECTING ||
      s === Ndt7State.UPLOAD_RUNNING;
  }

  /**
   * Discovers nearest M-Lab servers via Locate API v2
   */
  public async discoverServers(config?: Ndt7Config): Promise<LocateResult> {
    const cfg = config || new Ndt7Config();
    return await this.locateClient.discover(cfg);
  }

  /**
   * Runs a complete NDT7 test sequence (Discovery -> Download -> Upload)
   */
  public async startTest(config?: Ndt7Config, callbacks?: Ndt7EventCallbacks): Promise<Ndt7TestResult> {
    if (this.isRunningState(this.state)) {
      throw new Ndt7Error(`Cannot start test while in state ${this.state}`, 'INVALID_STATE');
    }

    const currentGen = ++this.runGeneration;
    const cfg: Ndt7Config = config || new Ndt7Config();
    this.isAborted = false;
    const startTimeMs = Date.now();

    // 1. Strict M-Lab Data Policy Check
    this.validateDataPolicy(cfg);

    try {
      // 2. Discover / Select Server
      this.setState(Ndt7State.DISCOVERING, 'Discovering optimal M-Lab server', callbacks, currentGen);
      if (callbacks && callbacks.onServerDiscovery) {
        try {
          callbacks.onServerDiscovery(cfg.locateUrl || Ndt7Constants.DEFAULT_LOCATE_URL);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'onServerDiscovery callback error: %{public}s', String(e));
        }
      }

      const locateResult = await this.locateClient.discover(cfg);
      if (this.runGeneration !== currentGen) {
        throw new Ndt7AbortError();
      }

      if (!locateResult || !locateResult.results || locateResult.results.length === 0) {
        throw new Ndt7Error('No measurement servers found', 'NO_SERVERS');
      }

      // Try candidate servers in order of distance priority
      const candidateServers = locateResult.results;
      let lastCandidateError: Ndt7Error | undefined = undefined;
      let successfulResult: Ndt7TestResult | undefined = undefined;

      for (let sIdx = 0; sIdx < candidateServers.length; sIdx++) {
        if (this.runGeneration !== currentGen || this.isAborted) {
          throw new Ndt7AbortError();
        }

        const selectedServer = candidateServers[sIdx];
        if (sIdx > 0 && callbacks && callbacks.onLog) {
          try {
            callbacks.onLog(`[NDT7 Fallback] Retrying with backup server candidate: ${selectedServer.machine}`);
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'onLog callback error: %{public}s', String(e));
          }
        }

        if (callbacks && callbacks.onServerChosen) {
          try {
            callbacks.onServerChosen(selectedServer);
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'onServerChosen callback error: %{public}s', String(e));
          }
        }

        try {
          // Resolve Download and Upload URLs with token and metadata
          const rawDownloadUrl = this.resolveUrl(selectedServer, cfg, 'download');
          const rawUploadUrl = this.resolveUrl(selectedServer, cfg, 'upload');

          const downloadUrl = LocateClient.appendMetadata(rawDownloadUrl, cfg.metadata);
          const uploadUrl = LocateClient.appendMetadata(rawUploadUrl, cfg.metadata);

          // 3. Run Download Test
          this.setState(Ndt7State.DOWNLOAD_CONNECTING, `Connecting to download server (${selectedServer.machine})`, callbacks, currentGen);
          const downloadRunnerInstance = new DownloadRunner();
          this.downloadRunner = downloadRunnerInstance;

          this.setState(Ndt7State.DOWNLOAD_RUNNING, 'Running download test', callbacks, currentGen);
          const downloadSummary = await downloadRunnerInstance.run(
            downloadUrl,
            callbacks,
            cfg.testDurationMs || Ndt7Constants.DEFAULT_TEST_DURATION_MS,
            cfg.timeoutMs || Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS,
            cfg.allowInsecureTransport === true
          );
          if (this.runGeneration === currentGen) {
            this.downloadRunner = undefined;
          }

          if (this.runGeneration !== currentGen || this.isAborted) {
            throw new Ndt7AbortError();
          }

          // 4. Run Upload Test
          this.setState(Ndt7State.UPLOAD_CONNECTING, `Connecting to upload server (${selectedServer.machine})`, callbacks, currentGen);
          const uploadRunnerInstance = new UploadRunner();
          this.uploadRunner = uploadRunnerInstance;

          this.setState(Ndt7State.UPLOAD_RUNNING, 'Running upload test', callbacks, currentGen);
          const uploadSummary = await uploadRunnerInstance.run(
            uploadUrl,
            callbacks,
            cfg.testDurationMs || Ndt7Constants.DEFAULT_TEST_DURATION_MS,
            cfg.timeoutMs || Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS,
            cfg.allowInsecureTransport === true
          );
          if (this.runGeneration === currentGen) {
            this.uploadRunner = undefined;
          }

          if (this.runGeneration !== currentGen || this.isAborted) {
            throw new Ndt7AbortError();
          }

          // 5. Complete
          const endTimeMs = Date.now();
          const testResult = new Ndt7TestResult();
          testResult.server = selectedServer;
          testResult.download = downloadSummary;
          testResult.upload = uploadSummary;
          testResult.startTimeMs = startTimeMs;
          testResult.endTimeMs = endTimeMs;
          testResult.status = 'completed';

          this.setState(Ndt7State.COMPLETED, 'NDT7 speed test completed successfully', callbacks, currentGen);
          if (callbacks && callbacks.onComplete) {
            try {
              callbacks.onComplete(testResult);
            } catch (e) {
              hilog.warn(DOMAIN, TAG, 'onComplete callback error: %{public}s', String(e));
            }
          }

          successfulResult = testResult;
          break; // Succeeded! Exit candidate loop

        } catch (candidateErr) {
          if (this.runGeneration === currentGen) {
            this.downloadRunner = undefined;
            this.uploadRunner = undefined;
          }

          if (this.isAborted || candidateErr instanceof Ndt7AbortError || this.runGeneration !== currentGen) {
            throw new Ndt7AbortError();
          }

          const typedErr: Ndt7Error = candidateErr instanceof Ndt7Error ? (candidateErr as Ndt7Error) : new Ndt7Error(String(candidateErr));
          lastCandidateError = typedErr;
          if (sIdx < candidateServers.length - 1 && (cfg.server === undefined && cfg.downloadUrl === undefined)) {
            if (callbacks && callbacks.onLog) {
              try {
                callbacks.onLog(`[NDT7 Notice] Connection to ${selectedServer.machine} failed (${typedErr.message}). Attempting next candidate.`);
              } catch (e) {
                hilog.warn(DOMAIN, TAG, 'onLog callback error: %{public}s', String(e));
              }
            }
            continue; // Fallback to next candidate
          }
          throw typedErr;
        }
      }

      if (!successfulResult) {
        if (lastCandidateError) {
          throw lastCandidateError;
        }
        throw new Ndt7Error('All candidate servers failed', 'ALL_SERVERS_FAILED');
      }

      return successfulResult;

    } catch (err) {
      if (this.runGeneration === currentGen) {
        this.downloadRunner = undefined;
        this.uploadRunner = undefined;
      }

      const error: Ndt7Error = err instanceof Ndt7Error ? (err as Ndt7Error) : new Ndt7Error(String(err));

      if (this.isAborted || error instanceof Ndt7AbortError || this.runGeneration !== currentGen) {
        this.setState(Ndt7State.CANCELED, 'Test was aborted', callbacks, currentGen);
        const canceledResult = new Ndt7TestResult();
        canceledResult.startTimeMs = startTimeMs;
        canceledResult.endTimeMs = Date.now();
        canceledResult.status = 'canceled';
        canceledResult.errorMessage = 'Aborted by user';
        return canceledResult;
      }

      this.setState(Ndt7State.FAILED, error.message, callbacks, currentGen);
      if (callbacks && callbacks.onError) {
        try {
          callbacks.onError(error);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'onError callback error: %{public}s', String(e));
        }
      }

      const failedResult = new Ndt7TestResult();
      failedResult.startTimeMs = startTimeMs;
      failedResult.endTimeMs = Date.now();
      failedResult.status = 'failed';
      failedResult.errorMessage = error.message;
      return failedResult;
    }
  }

  /**
   * Runs standalone download test against a specific URL or config
   */
  public async startDownload(urlOrConfig: string | Ndt7Config, callbacks?: Ndt7EventCallbacks): Promise<Ndt7SpeedSummary> {
    if (this.isRunningState(this.state)) {
      throw new Ndt7Error(`Cannot start download while in state ${this.state}`, 'INVALID_STATE');
    }

    const currentGen = ++this.runGeneration;
    this.isAborted = false;
    let url: string;
    let duration = Ndt7Constants.DEFAULT_TEST_DURATION_MS;
    let timeout = Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS;
    let allowInsecure = false;

    try {
      if (typeof urlOrConfig === 'string') {
        url = urlOrConfig;
        if (!url.startsWith('wss://')) {
          throw new Ndt7SecurityError(`Insecure URL rejected: "${url}". wss:// is required.`);
        }
      } else {
        this.validateDataPolicy(urlOrConfig);
        allowInsecure = urlOrConfig.allowInsecureTransport === true;
        this.setState(Ndt7State.DISCOVERING, 'Discovering download server', callbacks, currentGen);
        const locateResult = await this.locateClient.discover(urlOrConfig);
        if (this.runGeneration !== currentGen) {
          throw new Ndt7AbortError();
        }
        if (!locateResult || !locateResult.results || locateResult.results.length === 0) {
          throw new Ndt7Error('No measurement servers found', 'NO_SERVERS');
        }
        const selectedServer = locateResult.results[0];
        const rawUrl = this.resolveUrl(selectedServer, urlOrConfig, 'download');
        url = LocateClient.appendMetadata(rawUrl, urlOrConfig.metadata);
        duration = urlOrConfig.testDurationMs || duration;
        timeout = urlOrConfig.timeoutMs || timeout;
      }

      this.setState(Ndt7State.DOWNLOAD_RUNNING, 'Running download test', callbacks, currentGen);
      const downloadRunnerInstance = new DownloadRunner();
      this.downloadRunner = downloadRunnerInstance;
      const summary = await downloadRunnerInstance.run(url, callbacks, duration, timeout, allowInsecure);
      if (this.runGeneration === currentGen) {
        this.downloadRunner = undefined;
      }
      this.setState(Ndt7State.COMPLETED, 'Download completed', callbacks, currentGen);
      return summary;
    } catch (err) {
      if (this.runGeneration === currentGen) {
        this.downloadRunner = undefined;
      }
      const error: Ndt7Error = err instanceof Ndt7Error ? (err as Ndt7Error) : new Ndt7Error(String(err));
      if (this.isAborted || error instanceof Ndt7AbortError || this.runGeneration !== currentGen) {
        this.setState(Ndt7State.CANCELED, 'Download aborted', callbacks, currentGen);
      } else {
        this.setState(Ndt7State.FAILED, error.message, callbacks, currentGen);
      }
      throw error;
    }
  }

  /**
   * Runs standalone upload test against a specific URL or config
   */
  public async startUpload(urlOrConfig: string | Ndt7Config, callbacks?: Ndt7EventCallbacks): Promise<Ndt7SpeedSummary> {
    if (this.isRunningState(this.state)) {
      throw new Ndt7Error(`Cannot start upload while in state ${this.state}`, 'INVALID_STATE');
    }

    const currentGen = ++this.runGeneration;
    this.isAborted = false;
    let url: string;
    let duration = Ndt7Constants.DEFAULT_TEST_DURATION_MS;
    let timeout = Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS;
    let allowInsecure = false;

    try {
      if (typeof urlOrConfig === 'string') {
        url = urlOrConfig;
        if (!url.startsWith('wss://')) {
          throw new Ndt7SecurityError(`Insecure URL rejected: "${url}". wss:// is required.`);
        }
      } else {
        this.validateDataPolicy(urlOrConfig);
        allowInsecure = urlOrConfig.allowInsecureTransport === true;
        this.setState(Ndt7State.DISCOVERING, 'Discovering upload server', callbacks, currentGen);
        const locateResult = await this.locateClient.discover(urlOrConfig);
        if (this.runGeneration !== currentGen) {
          throw new Ndt7AbortError();
        }
        if (!locateResult || !locateResult.results || locateResult.results.length === 0) {
          throw new Ndt7Error('No measurement servers found', 'NO_SERVERS');
        }
        const selectedServer = locateResult.results[0];
        const rawUrl = this.resolveUrl(selectedServer, urlOrConfig, 'upload');
        url = LocateClient.appendMetadata(rawUrl, urlOrConfig.metadata);
        duration = urlOrConfig.testDurationMs || duration;
        timeout = urlOrConfig.timeoutMs || timeout;
      }

      this.setState(Ndt7State.UPLOAD_RUNNING, 'Running upload test', callbacks, currentGen);
      const uploadRunnerInstance = new UploadRunner();
      this.uploadRunner = uploadRunnerInstance;
      const summary = await uploadRunnerInstance.run(url, callbacks, duration, timeout, allowInsecure);
      if (this.runGeneration === currentGen) {
        this.uploadRunner = undefined;
      }
      this.setState(Ndt7State.COMPLETED, 'Upload completed', callbacks, currentGen);
      return summary;
    } catch (err) {
      if (this.runGeneration === currentGen) {
        this.uploadRunner = undefined;
      }
      const error: Ndt7Error = err instanceof Ndt7Error ? (err as Ndt7Error) : new Ndt7Error(String(err));
      if (this.isAborted || error instanceof Ndt7AbortError || this.runGeneration !== currentGen) {
        this.setState(Ndt7State.CANCELED, 'Upload aborted', callbacks, currentGen);
      } else {
        this.setState(Ndt7State.FAILED, error.message, callbacks, currentGen);
      }
      throw error;
    }
  }

  /**
   * Cancels any currently active speed test
   */
  public abort(): void {
    if (!this.isRunningState(this.state)) {
      return;
    }
    this.isAborted = true;
    this.runGeneration++;
    if (this.downloadRunner) {
      this.downloadRunner.abort();
      this.downloadRunner = undefined;
    }
    if (this.uploadRunner) {
      this.uploadRunner.abort();
      this.uploadRunner = undefined;
    }
    this.setState(Ndt7State.CANCELED, 'Aborted by user');
  }

  private validateDataPolicy(config?: Ndt7Config): void {
    if (!config?.userAcceptedDataPolicy && !config?.mlabDataPolicyInapplicable) {
      throw new Ndt7PolicyError();
    }
  }

  private resolveUrl(server: LocateServer, config: Ndt7Config, type: 'download' | 'upload'): string {
    const keyPrefix = type === 'download' ? '/ndt/v7/download' : '/ndt/v7/upload';
    if (server.urls) {
      const keys = Object.keys(server.urls);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        if (k.includes(keyPrefix)) {
          const matchedUrl = server.urls[k];
          if (config.allowInsecureTransport || matchedUrl.startsWith('wss://')) {
            return matchedUrl;
          }
        }
      }
    }

    const proto = (config.protocol === 'ws' && config.allowInsecureTransport) ? 'ws' : 'wss';
    return `${proto}://${server.machine}${keyPrefix}`;
  }

  private setState(state: Ndt7State, message?: string, callbacks?: Ndt7EventCallbacks, generation?: number): void {
    if (generation !== undefined && generation !== this.runGeneration) {
      return;
    }
    this.state = state;
    if (callbacks && callbacks.onStateChange) {
      try {
        callbacks.onStateChange(state, message);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'onStateChange callback error: %{public}s', String(e));
      }
    }
    if (callbacks && callbacks.onLog && message) {
      try {
        callbacks.onLog(`[NDT7 State] ${state}: ${message}`);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'onLog callback error: %{public}s', String(e));
      }
    }
  }
}
