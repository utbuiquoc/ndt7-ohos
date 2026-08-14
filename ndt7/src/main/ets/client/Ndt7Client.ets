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
import { Ndt7AbortError, Ndt7Error, Ndt7PolicyError } from '../utils/Ndt7Errors';

/**
 * Public NDT7 Client Facade for HarmonyOS ArkTS
 */
export class Ndt7Client {
  private state: Ndt7State = Ndt7State.IDLE;
  private locateClient: LocateClient = new LocateClient();
  private downloadRunner?: DownloadRunner;
  private uploadRunner?: UploadRunner;
  private isAborted: boolean = false;

  public getState(): Ndt7State {
    return this.state;
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
    if (this.state !== Ndt7State.IDLE && this.state !== Ndt7State.COMPLETED && this.state !== Ndt7State.CANCELED && this.state !== Ndt7State.FAILED) {
      throw new Ndt7Error(`Cannot start test while in state ${this.state}`, 'INVALID_STATE');
    }

    const cfg: Ndt7Config = config || new Ndt7Config();
    this.isAborted = false;
    const startTimeMs = Date.now();

    // 1. Strict M-Lab Data Policy Check
    this.validateDataPolicy(cfg);

    try {
      // 2. Discover / Select Server
      this.setState(Ndt7State.DISCOVERING, 'Discovering optimal M-Lab server', callbacks);
      if (callbacks && callbacks.onServerDiscovery) {
        callbacks.onServerDiscovery(cfg.locateUrl || Ndt7Constants.DEFAULT_LOCATE_URL);
      }

      const locateResult = await this.locateClient.discover(cfg);
      if (!locateResult.results || locateResult.results.length === 0) {
        throw new Ndt7Error('No measurement servers found', 'NO_SERVERS');
      }

      // Try candidate servers in order of distance priority
      const candidateServers = locateResult.results;
      let lastCandidateError: Error | undefined = undefined;
      let successfulResult: Ndt7TestResult | undefined = undefined;

      for (let sIdx = 0; sIdx < candidateServers.length; sIdx++) {
        const selectedServer = candidateServers[sIdx];
        if (sIdx > 0 && callbacks && callbacks.onLog) {
          callbacks.onLog(`[NDT7 Fallback] Retrying with backup server candidate: ${selectedServer.machine}`);
        }

        if (callbacks && callbacks.onServerChosen) {
          callbacks.onServerChosen(selectedServer);
        }

        if (this.isAborted) {
          throw new Ndt7AbortError();
        }

        try {
          // Resolve Download and Upload URLs with token and metadata
          const rawDownloadUrl = this.resolveUrl(selectedServer, cfg, 'download');
          const rawUploadUrl = this.resolveUrl(selectedServer, cfg, 'upload');

          const downloadUrl = LocateClient.appendMetadata(rawDownloadUrl, cfg.metadata);
          const uploadUrl = LocateClient.appendMetadata(rawUploadUrl, cfg.metadata);

          // 3. Run Download Test
          this.setState(Ndt7State.DOWNLOAD_CONNECTING, `Connecting to download server (${selectedServer.machine})`, callbacks);
          this.downloadRunner = new DownloadRunner();

          this.setState(Ndt7State.DOWNLOAD_RUNNING, 'Running download test', callbacks);
          const downloadSummary = await this.downloadRunner.run(
            downloadUrl,
            callbacks,
            cfg.testDurationMs || Ndt7Constants.DEFAULT_TEST_DURATION_MS,
            cfg.timeoutMs || Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS
          );
          this.downloadRunner = undefined;

          if (this.isAborted) {
            throw new Ndt7AbortError();
          }

          // 4. Run Upload Test
          this.setState(Ndt7State.UPLOAD_CONNECTING, `Connecting to upload server (${selectedServer.machine})`, callbacks);
          this.uploadRunner = new UploadRunner();

          this.setState(Ndt7State.UPLOAD_RUNNING, 'Running upload test', callbacks);
          const uploadSummary = await this.uploadRunner.run(
            uploadUrl,
            callbacks,
            cfg.testDurationMs || Ndt7Constants.DEFAULT_TEST_DURATION_MS,
            cfg.timeoutMs || Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS
          );
          this.uploadRunner = undefined;

          // 5. Complete
          const endTimeMs = Date.now();
          const testResult = new Ndt7TestResult();
          testResult.server = selectedServer;
          testResult.download = downloadSummary;
          testResult.upload = uploadSummary;
          testResult.startTimeMs = startTimeMs;
          testResult.endTimeMs = endTimeMs;
          testResult.status = 'completed';

          this.setState(Ndt7State.COMPLETED, 'NDT7 speed test completed successfully', callbacks);
          if (callbacks && callbacks.onComplete) {
            callbacks.onComplete(testResult);
          }

          successfulResult = testResult;
          break; // Succeeded! Exit candidate loop

        } catch (candidateErr) {
          this.downloadRunner = undefined;
          this.uploadRunner = undefined;

          if (this.isAborted || candidateErr instanceof Ndt7AbortError) {
            throw new Ndt7AbortError();
          }

          const typedErr = candidateErr instanceof Ndt7Error ? candidateErr : new Ndt7Error(String(candidateErr));
          lastCandidateError = typedErr;
          if (sIdx < candidateServers.length - 1 && (cfg.server === undefined && cfg.downloadUrl === undefined)) {
            if (callbacks && callbacks.onLog) {
              callbacks.onLog(`[NDT7 Notice] Connection to ${selectedServer.machine} failed (${typedErr.message}). Attempting next candidate.`);
            }
            continue; // Fallback to next candidate
          }
          throw typedErr;
        }
      }

      if (!successfulResult) {
        throw (lastCandidateError instanceof Ndt7Error ? lastCandidateError : new Ndt7Error('All candidate servers failed', 'ALL_SERVERS_FAILED'));
      }

      return successfulResult;

    } catch (err) {
      const error = err instanceof Ndt7Error ? err : new Ndt7Error(String(err));
      this.downloadRunner = undefined;
      this.uploadRunner = undefined;

      if (this.isAborted || error instanceof Ndt7AbortError) {
        this.setState(Ndt7State.CANCELED, 'Test was aborted', callbacks);
        const canceledResult = new Ndt7TestResult();
        canceledResult.startTimeMs = startTimeMs;
        canceledResult.endTimeMs = Date.now();
        canceledResult.status = 'canceled';
        canceledResult.errorMessage = 'Aborted by user';
        return canceledResult;
      }

      this.setState(Ndt7State.FAILED, error.message, callbacks);
      if (callbacks && callbacks.onError) {
        callbacks.onError(error);
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
    if (this.state !== Ndt7State.IDLE && this.state !== Ndt7State.COMPLETED && this.state !== Ndt7State.CANCELED && this.state !== Ndt7State.FAILED) {
      throw new Ndt7Error(`Cannot start download while in state ${this.state}`, 'INVALID_STATE');
    }

    this.isAborted = false;
    let url: string;
    let duration = Ndt7Constants.DEFAULT_TEST_DURATION_MS;
    let timeout = Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS;

    if (typeof urlOrConfig === 'string') {
      url = urlOrConfig;
    } else {
      this.validateDataPolicy(urlOrConfig);
      const locateResult = await this.locateClient.discover(urlOrConfig);
      const selectedServer = locateResult.results[0];
      const rawUrl = this.resolveUrl(selectedServer, urlOrConfig, 'download');
      url = LocateClient.appendMetadata(rawUrl, urlOrConfig.metadata);
      duration = urlOrConfig.testDurationMs || duration;
      timeout = urlOrConfig.timeoutMs || timeout;
    }

    this.setState(Ndt7State.DOWNLOAD_RUNNING, 'Running download test', callbacks);
    this.downloadRunner = new DownloadRunner();
    try {
      const summary = await this.downloadRunner.run(url, callbacks, duration, timeout);
      this.setState(Ndt7State.COMPLETED, 'Download completed', callbacks);
      return summary;
    } catch (err) {
      this.downloadRunner = undefined;
      const error = err instanceof Ndt7Error ? err : new Ndt7Error(String(err));
      if (this.isAborted || error instanceof Ndt7AbortError) {
        this.setState(Ndt7State.CANCELED, 'Download aborted', callbacks);
      } else {
        this.setState(Ndt7State.FAILED, error.message, callbacks);
      }
      throw error;
    }
  }

  /**
   * Runs standalone upload test against a specific URL or config
   */
  public async startUpload(urlOrConfig: string | Ndt7Config, callbacks?: Ndt7EventCallbacks): Promise<Ndt7SpeedSummary> {
    if (this.state !== Ndt7State.IDLE && this.state !== Ndt7State.COMPLETED && this.state !== Ndt7State.CANCELED && this.state !== Ndt7State.FAILED) {
      throw new Ndt7Error(`Cannot start upload while in state ${this.state}`, 'INVALID_STATE');
    }

    this.isAborted = false;
    let url: string;
    let duration = Ndt7Constants.DEFAULT_TEST_DURATION_MS;
    let timeout = Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS;

    if (typeof urlOrConfig === 'string') {
      url = urlOrConfig;
    } else {
      this.validateDataPolicy(urlOrConfig);
      const locateResult = await this.locateClient.discover(urlOrConfig);
      const selectedServer = locateResult.results[0];
      const rawUrl = this.resolveUrl(selectedServer, urlOrConfig, 'upload');
      url = LocateClient.appendMetadata(rawUrl, urlOrConfig.metadata);
      duration = urlOrConfig.testDurationMs || duration;
      timeout = urlOrConfig.timeoutMs || timeout;
    }

    this.setState(Ndt7State.UPLOAD_RUNNING, 'Running upload test', callbacks);
    this.uploadRunner = new UploadRunner();
    try {
      const summary = await this.uploadRunner.run(url, callbacks, duration, timeout);
      this.setState(Ndt7State.COMPLETED, 'Upload completed', callbacks);
      return summary;
    } catch (err) {
      this.uploadRunner = undefined;
      const error = err instanceof Ndt7Error ? err : new Ndt7Error(String(err));
      if (this.isAborted || error instanceof Ndt7AbortError) {
        this.setState(Ndt7State.CANCELED, 'Upload aborted', callbacks);
      } else {
        this.setState(Ndt7State.FAILED, error.message, callbacks);
      }
      throw error;
    }
  }

  /**
   * Cancels any currently active speed test
   */
  public abort(): void {
    this.isAborted = true;
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
          return server.urls[k];
        }
      }
    }

    const proto = config.protocol === 'ws' ? 'ws' : 'wss';
    return `${proto}://${server.machine}${keyPrefix}`;
  }

  private setState(state: Ndt7State, message?: string, callbacks?: Ndt7EventCallbacks): void {
    this.state = state;
    if (callbacks && callbacks.onStateChange) {
      callbacks.onStateChange(state, message);
    }
    if (callbacks && callbacks.onLog && message) {
      callbacks.onLog(`[NDT7 State] ${state}: ${message}`);
    }
  }
}
