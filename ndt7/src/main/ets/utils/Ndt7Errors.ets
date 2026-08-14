import { BusinessError } from '@kit.BasicServicesKit';

/**
 * Standard Ndt7Error conforming to HarmonyOS BusinessError
 */
export class Ndt7Error implements BusinessError {
  public code: number = 10001;
  public name: string = 'Ndt7Error';
  public message: string = '';
  public stack?: string;
  public errorCode: string = 'NDT7_ERROR';

  constructor(message: string, errorCode: string = 'NDT7_ERROR', code: number = 10001) {
    this.message = message;
    this.errorCode = errorCode;
    this.code = code;
  }
}

/**
 * Thrown when M-Lab data policy consent requirement is violated
 */
export class Ndt7PolicyError extends Ndt7Error {
  constructor(message: string = 'M-Lab Data Policy consent required (userAcceptedDataPolicy must be true unless mlabDataPolicyInapplicable is true)') {
    super(message, 'POLICY_CONSENT_REQUIRED', 10002);
    this.name = 'Ndt7PolicyError';
  }
}

/**
 * Thrown during server discovery (Locate API)
 */
export class Ndt7LocateError extends Ndt7Error {
  public statusCode?: number;

  constructor(message: string, statusCode?: number) {
    super(message, 'LOCATE_ERROR', 10003);
    this.name = 'Ndt7LocateError';
    this.statusCode = statusCode;
  }
}

/**
 * Thrown when M-Lab has no measurement capacity (HTTP 204)
 */
export class Ndt7LocateCapacityError extends Ndt7LocateError {
  constructor(message: string = 'No measurement capacity currently available on M-Lab servers (HTTP 204)') {
    super(message, 204);
    this.name = 'Ndt7LocateCapacityError';
    this.errorCode = 'LOCATE_NO_CAPACITY';
    this.code = 204;
  }
}

/**
 * Thrown on WebSocket network connection failures
 */
export class Ndt7ConnectionError extends Ndt7Error {
  constructor(message: string) {
    super(message, 'CONNECTION_ERROR', 10004);
    this.name = 'Ndt7ConnectionError';
  }
}

/**
 * Thrown when protocol expectations are violated
 */
export class Ndt7ProtocolError extends Ndt7Error {
  constructor(message: string) {
    super(message, 'PROTOCOL_ERROR', 10005);
    this.name = 'Ndt7ProtocolError';
  }
}

/**
 * Thrown on handshake or hard watchdog timeouts
 */
export class Ndt7TimeoutError extends Ndt7Error {
  constructor(message: string) {
    super(message, 'TIMEOUT_ERROR', 10006);
    this.name = 'Ndt7TimeoutError';
  }
}

/**
 * Thrown when test is cancelled by the user/caller
 */
export class Ndt7AbortError extends Ndt7Error {
  constructor(message: string = 'NDT7 speed test was aborted') {
    super(message, 'ABORTED', 10007);
    this.name = 'Ndt7AbortError';
  }
}
