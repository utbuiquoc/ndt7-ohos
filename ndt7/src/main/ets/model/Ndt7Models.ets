import { Ndt7Error } from '../utils/Ndt7Errors';

/**
 * M-Lab NDT7 Protocol Data Models (v0.11.0 Normative)
 * HarmonyOS ArkTS Stage Model (API 18+)
 */

export class Ndt7AppInfo {
  public ElapsedTime?: number; // Microseconds since test start
  public NumBytes?: number;    // Bytes transferred at application level

  constructor(elapsedTime?: number, numBytes?: number) {
    this.ElapsedTime = elapsedTime;
    this.NumBytes = numBytes;
  }
}

export class Ndt7ConnectionInfo {
  public Client?: string;
  public Server?: string;
  public UUID?: string;
  public StartTime?: string;

  constructor(client?: string, server?: string, uuid?: string, startTime?: string) {
    this.Client = client;
    this.Server = server;
    this.UUID = uuid;
    this.StartTime = startTime;
  }
}

export class Ndt7TCPInfo {
  public MinRTT?: number;
  public RTT?: number;
  public RTTVar?: number;
  public BytesRetrans?: number;
  public BytesSent?: number;
  public BytesAcked?: number;
  public BytesReceived?: number;
  public ElapsedTime?: number;
  public BusyTime?: number;
  public RWndLimited?: number;
  public SndBufLimited?: number;
}

export class Ndt7Measurement {
  public AppInfo?: Ndt7AppInfo;
  public ConnectionInfo?: Ndt7ConnectionInfo;
  public Origin?: 'client' | 'server';
  public Test?: 'download' | 'upload';
  public TCPInfo?: Ndt7TCPInfo;
  public rawJson?: string;
}

export class Ndt7Diagnostics {
  public minRttUs?: number;
  public rttUs?: number;
  public rttVarUs?: number;
  public bytesSent?: number;
  public bytesRetrans?: number;
  public bytesAcked?: number;
  public bytesReceived?: number;
  public retransmissionRate?: number;
}

export class Ndt7SpeedSummary {
  public bytes: number = 0;
  public elapsedUs: number = 0;
  public bps: number = 0;
  public mbps: number = 0;
  public diagnostics?: Ndt7Diagnostics;

  constructor(bytes: number = 0, elapsedUs: number = 0, bps: number = 0, mbps: number = 0, diagnostics?: Ndt7Diagnostics) {
    this.bytes = bytes;
    this.elapsedUs = elapsedUs;
    this.bps = bps;
    this.mbps = mbps;
    this.diagnostics = diagnostics;
  }
}

export class LocateLocation {
  public city?: string;
  public country?: string;
  public metro?: string;
  public region?: string;
}

export class LocateServer {
  public machine: string = '';
  public location?: LocateLocation;
  public urls: Record<string, string> = {};
  public rawJson?: string;

  constructor(machine: string = '', location?: LocateLocation, urls: Record<string, string> = {}, rawJson?: string) {
    this.machine = machine;
    this.location = location;
    this.urls = urls;
    this.rawJson = rawJson;
  }
}

export class LocateResult {
  public results: LocateServer[] = [];

  constructor(results: LocateServer[] = []) {
    this.results = results;
  }
}

export enum Ndt7State {
  IDLE = 'IDLE',
  DISCOVERING = 'DISCOVERING',
  DOWNLOAD_CONNECTING = 'DOWNLOAD_CONNECTING',
  DOWNLOAD_RUNNING = 'DOWNLOAD_RUNNING',
  UPLOAD_CONNECTING = 'UPLOAD_CONNECTING',
  UPLOAD_RUNNING = 'UPLOAD_RUNNING',
  COMPLETED = 'COMPLETED',
  CANCELED = 'CANCELED',
  FAILED = 'FAILED'
}

export class Ndt7Config {
  public server?: string;
  public protocol?: 'wss' | 'ws';
  public downloadUrl?: string;
  public uploadUrl?: string;
  public locateUrl?: string;
  public clientRegistrationToken?: string;
  public timeoutMs?: number;
  public testDurationMs?: number;
  public metadata?: Record<string, string>;
  public userAcceptedDataPolicy?: boolean;
  public mlabDataPolicyInapplicable?: boolean;
}

export class Ndt7TestResult {
  public server?: LocateServer;
  public download?: Ndt7SpeedSummary;
  public upload?: Ndt7SpeedSummary;
  public startTimeMs: number = 0;
  public endTimeMs: number = 0;
  public status: 'completed' | 'canceled' | 'failed' = 'completed';
  public errorMessage?: string;
}

export class Ndt7EventCallbacks {
  public onStateChange?: (state: Ndt7State, message?: string) => void;
  public onServerDiscovery?: (loadbalancerUrl: string) => void;
  public onServerChosen?: (server: LocateServer) => void;
  public onDownloadStart?: (url: string) => void;
  public onDownloadMeasurement?: (measurement: Ndt7Measurement) => void;
  public onDownloadProgress?: (summary: Ndt7SpeedSummary) => void;
  public onDownloadComplete?: (summary: Ndt7SpeedSummary) => void;
  public onUploadStart?: (url: string) => void;
  public onUploadMeasurement?: (measurement: Ndt7Measurement) => void;
  public onUploadProgress?: (summary: Ndt7SpeedSummary) => void;
  public onUploadComplete?: (summary: Ndt7SpeedSummary) => void;
  public onComplete?: (result: Ndt7TestResult) => void;
  public onError?: (error: Ndt7Error) => void;
  public onLog?: (message: string) => void;
}
