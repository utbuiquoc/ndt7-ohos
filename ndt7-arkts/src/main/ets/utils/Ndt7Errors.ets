import { BusinessError } from '@kit.BasicServicesKit';

/**
 * Standard Ndt7Error extending JavaScript Error and conforming to HarmonyOS BusinessError
 */
export class Ndt7Error extends Error implements BusinessError {
  public code: number = 10001;
  public name: string = 'Ndt7Error';
  public errorCode: string = 'NDT7_ERROR';

  constructor(message: string, errorCode: string = 'NDT7_ERROR', code: number = 10001) {
    super(message);
    this.message = message;
    this.name = 'Ndt7Error';
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

  constructor(message: string, statusCode?: number, errorCode: string = 'LOCATE_ERROR', code: number = 10003) {
    super(message, errorCode, code);
    this.name = 'Ndt7LocateError';
    this.statusCode = statusCode;
  }
}

/**
 * Thrown when M-Lab has no measurement capacity (HTTP 204)
 */
export class Ndt7LocateCapacityError extends Ndt7LocateError {
  constructor(message: string = 'No measurement capacity currently available on M-Lab servers (HTTP 204)') {
    super(message, 204, 'LOCATE_NO_CAPACITY', 10008);
    this.name = 'Ndt7LocateCapacityError';
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

/**
 * Thrown on security policy violations (e.g. plaintext transport, insecure redirects, token leakage)
 */
export class Ndt7SecurityError extends Ndt7Error {
  constructor(message: string) {
    super(message, 'SECURITY_ERROR', 10009);
    this.name = 'Ndt7SecurityError';
  }
}
