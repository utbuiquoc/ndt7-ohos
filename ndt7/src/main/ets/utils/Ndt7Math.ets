import { Ndt7Diagnostics, Ndt7SpeedSummary, Ndt7TCPInfo } from '../model/Ndt7Models';

/**
 * High precision calculations and formatting for NDT7 measurements
 */
export class Ndt7Math {
  /**
   * Calculates goodput bitrate and Mbps from byte count and elapsed microseconds
   * Formula: bps = (bytes * 8 * 1,000,000) / elapsedUs
   */
  public static calculateSpeed(bytes: number, elapsedUs: number, diagnostics?: Ndt7Diagnostics): Ndt7SpeedSummary {
    if (bytes <= 0 || elapsedUs <= 0 || isNaN(bytes) || isNaN(elapsedUs)) {
      const summary = new Ndt7SpeedSummary();
      summary.bytes = Math.max(0, bytes || 0);
      summary.elapsedUs = Math.max(0, elapsedUs || 0);
      summary.bps = 0;
      summary.mbps = 0;
      summary.diagnostics = diagnostics;
      return summary;
    }

    const bps = (bytes * 8.0 * 1000000.0) / elapsedUs;
    const mbps = bps / 1000000.0;

    const summary = new Ndt7SpeedSummary();
    summary.bytes = bytes;
    summary.elapsedUs = elapsedUs;
    summary.bps = bps;
    summary.mbps = Math.round(mbps * 100.0) / 100.0;
    summary.diagnostics = diagnostics;
    return summary;
  }

  /**
   * Extracts optional diagnostics from normative TCPInfo
   */
  public static extractDiagnostics(tcpInfo?: Ndt7TCPInfo): Ndt7Diagnostics | undefined {
    if (!tcpInfo) {
      return undefined;
    }

    let retransmissionRate: number | undefined = undefined;
    if (tcpInfo.BytesSent && tcpInfo.BytesSent > 0 && tcpInfo.BytesRetrans !== undefined) {
      retransmissionRate = Math.round((tcpInfo.BytesRetrans / tcpInfo.BytesSent) * 10000.0) / 100.0; // as % with 2 decimals
    }

    const diag = new Ndt7Diagnostics();
    diag.minRttUs = tcpInfo.MinRTT;
    diag.rttUs = tcpInfo.RTT;
    diag.rttVarUs = tcpInfo.RTTVar;
    diag.bytesSent = tcpInfo.BytesSent;
    diag.bytesRetrans = tcpInfo.BytesRetrans;
    diag.bytesAcked = tcpInfo.BytesAcked;
    diag.bytesReceived = tcpInfo.BytesReceived;
    diag.retransmissionRate = retransmissionRate;
    return diag;
  }

  /**
   * Formats Mbps speed into readable string
   */
  public static formatSpeed(mbps: number): string {
    if (isNaN(mbps) || mbps <= 0) {
      return '0.00 Mbps';
    }
    if (mbps >= 1000) {
      const gbps = mbps / 1000.0;
      return `${gbps.toFixed(2)} Gbps`;
    }
    if (mbps < 1.0) {
      const kbps = mbps * 1000.0;
      return `${kbps.toFixed(1)} Kbps`;
    }
    return `${mbps.toFixed(2)} Mbps`;
  }

  /**
   * Formats byte size into human readable string
   */
  public static formatBytes(bytes: number): string {
    if (isNaN(bytes) || bytes <= 0) {
      return '0 B';
    }
    const units = ['B', 'KB', 'MB', 'GB'];
    let size = bytes;
    let unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024.0;
      unitIndex++;
    }
    return `${size.toFixed(unitIndex === 0 ? 0 : 2)} ${units[unitIndex]}`;
  }
}
