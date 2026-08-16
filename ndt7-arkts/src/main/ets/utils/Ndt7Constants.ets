/**
 * Protocol and Client Constants for NDT7 HarmonyOS Library
 */

export class Ndt7Constants {
  // Protocol subprotocol
  public static readonly SUBPROTOCOL: string = 'net.measurementlab.ndt.v7';

  // Locate API Endpoints
  public static readonly DEFAULT_LOCATE_URL: string = 'https://locate.measurementlab.net/v2/nearest/ndt/ndt7';
  public static readonly PRIORITY_LOCATE_URL: string = 'https://locate.measurementlab.net/v2/priority/nearest/ndt/ndt7';

  // Test URL paths
  public static readonly DOWNLOAD_PATH: string = '/ndt/v7/download';
  public static readonly UPLOAD_PATH: string = '/ndt/v7/upload';

  // Test Timing (per ndt7-protocol.md)
  public static readonly DEFAULT_TEST_DURATION_MS: number = 10000;  // 10 seconds expected
  public static readonly DEFAULT_CONNECT_TIMEOUT_MS: number = 10000; // 10 seconds handshake
  public static readonly PROGRESS_INTERVAL_MS: number = 100;        // 10 progress updates / second

  // Dynamic Upload Binary Message Sizing (per ndt7-protocol.md appendix)
  public static readonly MIN_UPLOAD_CHUNK_SIZE: number = 1024;      // 1 KiB (1 << 10)
  public static readonly INITIAL_UPLOAD_CHUNK_SIZE: number = 8192;  // 8 KiB (1 << 13)
  public static readonly MAX_UPLOAD_CHUNK_SIZE: number = 16777216;  // 16 MiB (1 << 24)

  // Query String Limits
  public static readonly MAX_QUERY_STRING_LENGTH: number = 4096;

  // Client Identification
  public static readonly CLIENT_LIBRARY_NAME: string = 'ndt7-arkts';
  public static readonly CLIENT_LIBRARY_VERSION: string = '1.0.0';
  public static readonly USER_AGENT: string = 'ndt7-arkts/1.0.0 (HarmonyOS; ArkTS)';
}
