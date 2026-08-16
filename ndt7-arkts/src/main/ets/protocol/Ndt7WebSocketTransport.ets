import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Ndt7Constants } from '../utils/Ndt7Constants';
import { Ndt7ConnectionError, Ndt7Error, Ndt7SecurityError, Ndt7TimeoutError } from '../utils/Ndt7Errors';

const DOMAIN = 0xA11A;
const TAG = 'Ndt7Transport';

export class WebSocketTransportCallbacks {
  public onOpen?: () => void;
  public onBinaryMessage?: (buffer: ArrayBuffer) => void;
  public onTextMessage?: (text: string) => void;
  public onClose?: (code: number, reason: string) => void;
  public onError?: (error: Ndt7Error) => void;
}

/**
 * Idiomatic HarmonyOS NetworkKit WebSocket Transport for NDT7 Protocol
 */
export class Ndt7WebSocketTransport {
  private ws: webSocket.WebSocket;
  private isConnected: boolean = false;
  private isClosed: boolean = false;
  private isLocallyClosed: boolean = false;
  private callbacks: WebSocketTransportCallbacks = new WebSocketTransportCallbacks();
  private connectTimerId: number = -1;

  constructor() {
    this.ws = webSocket.createWebSocket();
  }

  public setCallbacks(callbacks: WebSocketTransportCallbacks): void {
    this.callbacks = callbacks;
  }

  private detachListeners(): void {
    try {
      this.ws.off('open');
      this.ws.off('message');
      this.ws.off('close');
      this.ws.off('error');
    } catch (_) {
      // Ignore cleanup error
    }
  }

  /**
   * Connects to the NDT7 WebSocket endpoint with the mandatory subprotocol header
   */
  public connect(url: string, timeoutMs: number = Ndt7Constants.DEFAULT_CONNECT_TIMEOUT_MS, allowInsecureTransport: boolean = false): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (reason?: Ndt7Error) => void) => {
      // 1. Enforce secure transport
      if (!url || (!url.startsWith('wss://') && (!allowInsecureTransport || !url.startsWith('ws://')))) {
        const secErr = new Ndt7SecurityError(`Insecure or invalid WebSocket URL rejected: "${url}". wss:// is required.`);
        reject(secErr);
        return;
      }

      this.isClosed = false;
      this.isLocallyClosed = false;
      this.isConnected = false;
      let settled = false;

      const cleanupConnectTimer = (): void => {
        if (this.connectTimerId !== -1) {
          clearTimeout(this.connectTimerId);
          this.connectTimerId = -1;
        }
      };

      this.connectTimerId = setTimeout(() => {
        if (!settled) {
          settled = true;
          this.close(1000, 'Handshake Timeout');
          const timeoutErr = new Ndt7TimeoutError(`WebSocket connect/handshake timed out after ${timeoutMs}ms`);
          reject(timeoutErr);
        }
      }, timeoutMs);

      // Clean any previously registered listeners to avoid duplicate callbacks
      this.detachListeners();

      // 2. Listen for open event
      this.ws.on('open', (_err: BusinessError, _value: Object) => {
        if (this.isClosed || settled) {
          return;
        }
        this.isConnected = true;
        settled = true;
        cleanupConnectTimer();
        if (this.callbacks.onOpen) {
          try {
            this.callbacks.onOpen();
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'onOpen callback error: %{public}s', String(e));
          }
        }
        resolve();
      });

      // 3. Listen for messages (binary and text)
      this.ws.on('message', (_err: BusinessError, value: string | ArrayBuffer) => {
        if (this.isClosed) {
          return;
        }
        if (typeof value === 'string') {
          if (this.callbacks.onTextMessage) {
            try {
              this.callbacks.onTextMessage(value);
            } catch (e) {
              hilog.warn(DOMAIN, TAG, 'onTextMessage callback error: %{public}s', String(e));
            }
          }
        } else if (value instanceof ArrayBuffer) {
          if (this.callbacks.onBinaryMessage) {
            try {
              this.callbacks.onBinaryMessage(value);
            } catch (e) {
              hilog.warn(DOMAIN, TAG, 'onBinaryMessage callback error: %{public}s', String(e));
            }
          }
        }
      });

      // 4. Listen for close event
      this.ws.on('close', (_err: BusinessError, value: webSocket.CloseResult) => {
        this.isConnected = false;
        cleanupConnectTimer();
        const code = value ? value.code : 1000;
        const reason = value ? value.reason : 'Normal Closure';

        if (!settled) {
          settled = true;
          const connErr = new Ndt7ConnectionError(`WebSocket closed before handshake completed: code=${code}, reason=${reason}`);
          reject(connErr);
        } else if (this.callbacks.onClose && !this.isLocallyClosed) {
          try {
            this.callbacks.onClose(code, reason);
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'onClose callback error: %{public}s', String(e));
          }
        }
      });

      // 5. Listen for error event
      this.ws.on('error', (err: BusinessError) => {
        cleanupConnectTimer();
        const errMsg = err ? `code=${err.code}, msg=${err.message}` : 'WebSocket error';
        const connectionError = new Ndt7ConnectionError(`WebSocket error: ${errMsg}`);
        if (!settled) {
          settled = true;
          reject(connectionError);
        } else if (this.callbacks.onError && !this.isClosed) {
          try {
            this.callbacks.onError(connectionError);
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'onError callback error: %{public}s', String(e));
          }
        }
      });

      // 6. Initiate connection with subprotocol configuration
      const headers: Record<string, string> = {};
      headers['User-Agent'] = Ndt7Constants.USER_AGENT;

      const connectOptions: webSocket.WebSocketRequestOptions = {
        header: headers,
        protocol: Ndt7Constants.SUBPROTOCOL
      };

      this.ws.connect(url, connectOptions, (err: BusinessError, success: boolean) => {
        if (err && !success) {
          if (!settled) {
            settled = true;
            cleanupConnectTimer();
            const connErr = new Ndt7ConnectionError(`WebSocket connect call rejected: code=${err.code}, msg=${err.message}`);
            reject(connErr);
          }
        }
      });
    });
  }

  /**
   * Sends binary or string frame over WebSocket
   */
  public async send(data: string | ArrayBuffer): Promise<boolean> {
    if (!this.isConnected || this.isClosed) {
      return false;
    }
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      this.ws.send(data, (err: BusinessError, success: boolean) => {
        if (err || !success) {
          resolve(false);
        } else {
          resolve(true);
        }
      });
    });
  }

  /**
   * Closes the WebSocket connection
   */
  public close(code: number = 1000, reason: string = 'Normal Closure'): void {
    if (this.isClosed) {
      return;
    }
    this.isClosed = true;
    this.isLocallyClosed = true;
    this.isConnected = false;
    if (this.connectTimerId !== -1) {
      clearTimeout(this.connectTimerId);
      this.connectTimerId = -1;
    }
    try {
      const closeOptions: webSocket.WebSocketCloseOptions = {
        code: code,
        reason: reason
      };
      this.ws.close(closeOptions, () => {});
    } catch (_) {
      // Ignored
    }
  }

  /**
   * Releases and destroys WebSocket instance
   */
  public destroy(): void {
    this.close();
    this.detachListeners();
  }
}
