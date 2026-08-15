import { describe, it, expect } from '@ohos/hypium';
import { Ndt7Constants } from '../main/ets/utils/Ndt7Constants';
import { Ndt7Math } from '../main/ets/utils/Ndt7Math';
import {
  Ndt7AbortError,
  Ndt7ConnectionError,
  Ndt7Error,
  Ndt7LocateCapacityError,
  Ndt7LocateError,
  Ndt7PolicyError,
  Ndt7ProtocolError,
  Ndt7SecurityError,
  Ndt7TimeoutError
} from '../main/ets/utils/Ndt7Errors';
import { LocateClient } from '../main/ets/discovery/LocateClient';
import { Ndt7Client } from '../main/ets/client/Ndt7Client';
import { Ndt7AppInfo, Ndt7Measurement, Ndt7TCPInfo, Ndt7TestResult } from '../main/ets/model/Ndt7Models';

export default function localUnitTest() {
  describe('NDT7ProtocolAndMathTests', () => {

    it('verifiesProtocolConstants', 0, () => {
      expect(Ndt7Constants.SUBPROTOCOL).assertEqual('net.measurementlab.ndt.v7');
      expect(Ndt7Constants.DOWNLOAD_PATH).assertEqual('/ndt/v7/download');
      expect(Ndt7Constants.UPLOAD_PATH).assertEqual('/ndt/v7/upload');
      expect(Ndt7Constants.INITIAL_UPLOAD_CHUNK_SIZE).assertEqual(8192);
      expect(Ndt7Constants.MAX_UPLOAD_CHUNK_SIZE).assertEqual(16777216); // 16 MiB (1 << 24)
      expect(Ndt7Constants.DEFAULT_TEST_DURATION_MS).assertEqual(10000);
      expect(Ndt7Constants.HARD_WATCHDOG_TIMEOUT_MS).assertEqual(13000);
    });

    it('calculatesSpeedAccurately', 0, () => {
      // 12,500,000 bytes in 1,000,000 microseconds (1 sec) = 100,000,000 bps = 100 Mbps
      const summary = Ndt7Math.calculateSpeed(12500000, 1000000);
      expect(summary.bytes).assertEqual(12500000);
      expect(summary.elapsedUs).assertEqual(1000000);
      expect(summary.bps).assertEqual(100000000);
      expect(summary.mbps).assertEqual(100);
    });

    it('handlesZeroAndNegativeAndNonFiniteSpeedInputsSafely', 0, () => {
      const zeroBytes = Ndt7Math.calculateSpeed(0, 1000000);
      expect(zeroBytes.mbps).assertEqual(0);
      expect(zeroBytes.bps).assertEqual(0);

      const zeroTime = Ndt7Math.calculateSpeed(1000, 0);
      expect(zeroTime.mbps).assertEqual(0);

      const negativeTime = Ndt7Math.calculateSpeed(1000, -500);
      expect(negativeTime.mbps).assertEqual(0);

      const nanBytes = Ndt7Math.calculateSpeed(NaN, 1000000);
      expect(nanBytes.mbps).assertEqual(0);

      const infBytes = Ndt7Math.calculateSpeed(Infinity, 1000000);
      expect(infBytes.mbps).assertEqual(0);
    });

    it('formatsSpeedStringsCorrectly', 0, () => {
      expect(Ndt7Math.formatSpeed(0)).assertEqual('0.00 Mbps');
      expect(Ndt7Math.formatSpeed(-5)).assertEqual('0.00 Mbps');
      expect(Ndt7Math.formatSpeed(NaN)).assertEqual('0.00 Mbps');
      expect(Ndt7Math.formatSpeed(0.5)).assertEqual('500.0 Kbps');
      expect(Ndt7Math.formatSpeed(45.678)).assertEqual('45.68 Mbps');
      expect(Ndt7Math.formatSpeed(1250.4)).assertEqual('1.25 Gbps');
    });

    it('formatsByteSizesCorrectly', 0, () => {
      expect(Ndt7Math.formatBytes(0)).assertEqual('0 B');
      expect(Ndt7Math.formatBytes(-100)).assertEqual('0 B');
      expect(Ndt7Math.formatBytes(NaN)).assertEqual('0 B');
      expect(Ndt7Math.formatBytes(1024)).assertEqual('1.00 KB');
      expect(Ndt7Math.formatBytes(1048576)).assertEqual('1.00 MB');
      expect(Ndt7Math.formatBytes(15728640)).assertEqual('15.00 MB');
    });

    it('extractsNormativeDiagnosticsFromTCPInfo', 0, () => {
      const tcpInfo = new Ndt7TCPInfo();
      tcpInfo.MinRTT = 15000;     // 15ms in us
      tcpInfo.RTT = 20000;        // 20ms in us
      tcpInfo.RTTVar = 2000;
      tcpInfo.BytesSent = 100000;
      tcpInfo.BytesRetrans = 500;
      tcpInfo.BytesAcked = 99500;
      tcpInfo.BytesReceived = 50000;
      tcpInfo.ElapsedTime = 5000000;
      tcpInfo.BusyTime = 4000000;
      tcpInfo.RWndLimited = 1000;
      tcpInfo.SndBufLimited = 2000;

      const diagnostics = Ndt7Math.extractDiagnostics(tcpInfo);
      expect(diagnostics !== undefined).assertTrue();
      if (diagnostics) {
        expect(diagnostics.minRttUs).assertEqual(15000);
        expect(diagnostics.rttUs).assertEqual(20000);
        expect(diagnostics.bytesSent).assertEqual(100000);
        expect(diagnostics.bytesRetrans).assertEqual(500);
        expect(diagnostics.bytesReceived).assertEqual(50000);
        expect(diagnostics.retransmissionRate).assertEqual(0.5); // 500 / 100000 = 0.5%
      }
    });

    it('simulatesDynamicUploadMessageScalingPerSpec', 0, () => {
      let messageSize = Ndt7Constants.INITIAL_UPLOAD_CHUNK_SIZE; // 8 KiB = 8192
      let totalSent = 0;
      const observedSizes: number[] = [];

      while (totalSent < 300000000) { // simulate ~300 MB upload
        totalSent += messageSize;
        if (!observedSizes.includes(messageSize)) {
          observedSizes.push(messageSize);
        }

        if (messageSize < Ndt7Constants.MAX_UPLOAD_CHUNK_SIZE && messageSize < Math.floor(totalSent / 16)) {
          messageSize *= 2;
          if (messageSize > Ndt7Constants.MAX_UPLOAD_CHUNK_SIZE) {
            messageSize = Ndt7Constants.MAX_UPLOAD_CHUNK_SIZE;
          }
        }
      }

      // Should have scaled progressively: 8KB -> 16KB -> 32KB -> 64KB -> 128KB -> ... -> 16MB
      expect(observedSizes[0]).assertEqual(8192);
      expect(observedSizes[1]).assertEqual(16384);
      expect(observedSizes[2]).assertEqual(32768);
      expect(observedSizes.includes(16777216)).assertTrue(); // reached 16 MiB max
      expect(messageSize <= Ndt7Constants.MAX_UPLOAD_CHUNK_SIZE).assertTrue();
    });

    it('preservesExistingTokensAndAppendsMetadataToUrls', 0, () => {
      const rawUrl = 'wss://mlab1-ord01.measurement-lab.org/ndt/v7/download?access_token=xyz123';
      const metadata: Record<string, string> = {};
      metadata['client_name'] = 'watch-app';
      metadata['client_version'] = '2.0.0';
      const finalUrl = LocateClient.appendMetadata(rawUrl, metadata);

      expect(finalUrl.includes('access_token=xyz123')).assertTrue();
      expect(finalUrl.includes('client_library_name=ndt7-ohos')).assertTrue();
      expect(finalUrl.includes('client_library_version=1.0.0')).assertTrue();
      expect(finalUrl.includes('client_name=watch-app')).assertTrue();
      expect(finalUrl.includes('client_version=2.0.0')).assertTrue();
    });

    it('enforcesStrictDataPolicyRequirement', 0, async () => {
      const client = new Ndt7Client();
      let threwPolicyError = false;

      try {
        await client.startTest({
          server: 'test.example.com',
          userAcceptedDataPolicy: false,
          mlabDataPolicyInapplicable: false
        });
      } catch (e) {
        if (e instanceof Ndt7PolicyError) {
          threwPolicyError = true;
        }
      }

      expect(threwPolicyError).assertTrue();
    });

    it('enforcesSecureSchemeOnStandaloneDownloadAndUpload', 0, async () => {
      const client = new Ndt7Client();
      let threwSecurityErrorDownload = false;
      let threwSecurityErrorUpload = false;

      try {
        await client.startDownload('ws://insecure.example.com/ndt/v7/download');
      } catch (e) {
        if (e instanceof Ndt7SecurityError) {
          threwSecurityErrorDownload = true;
        }
      }

      try {
        await client.startUpload('ws://insecure.example.com/ndt/v7/upload');
      } catch (e) {
        if (e instanceof Ndt7SecurityError) {
          threwSecurityErrorUpload = true;
        }
      }

      expect(threwSecurityErrorDownload).assertTrue();
      expect(threwSecurityErrorUpload).assertTrue();
    });

    it('parsesNormativeMeasurementJsonProperly', 0, () => {
      const sampleServerJson = '{"AppInfo":{"ElapsedTime":5000000,"NumBytes":25000000},"Origin":"server","Test":"download","TCPInfo":{"MinRTT":12000,"RTT":18000,"BytesSent":25050000,"BytesRetrans":1200,"BytesReceived":0,"BusyTime":4800000}}';
      const parsed = JSON.parse(sampleServerJson) as Record<string, Object>;

      const rawAppInfo = parsed['AppInfo'] as Record<string, number> | undefined;
      const rawTcpInfo = parsed['TCPInfo'] as Record<string, number> | undefined;

      const measurement = new Ndt7Measurement();
      measurement.rawJson = sampleServerJson;
      measurement.Origin = parsed['Origin'] as 'client' | 'server' | undefined;
      measurement.Test = parsed['Test'] as 'download' | 'upload' | undefined;

      if (rawAppInfo) {
        measurement.AppInfo = new Ndt7AppInfo(rawAppInfo['ElapsedTime'], rawAppInfo['NumBytes']);
      }

      if (rawTcpInfo) {
        const tcpInfo = new Ndt7TCPInfo();
        tcpInfo.MinRTT = rawTcpInfo['MinRTT'];
        tcpInfo.RTT = rawTcpInfo['RTT'];
        tcpInfo.BytesRetrans = rawTcpInfo['BytesRetrans'];
        measurement.TCPInfo = tcpInfo;
      }

      expect(measurement.Origin).assertEqual('server');
      expect(measurement.Test).assertEqual('download');
      expect(measurement.AppInfo?.NumBytes).assertEqual(25000000);
      expect(measurement.TCPInfo?.MinRTT).assertEqual(12000);
      expect(measurement.TCPInfo?.BytesRetrans).assertEqual(1200);
    });

    it('verifiesErrorHierarchyAndStatusCodes', 0, () => {
      const capacityError = new Ndt7LocateCapacityError();
      expect(capacityError instanceof Error).assertTrue();
      expect(capacityError instanceof Ndt7Error).assertTrue();
      expect(capacityError.statusCode).assertEqual(204);
      expect(capacityError.code).assertEqual(10008);
      expect(capacityError.errorCode).assertEqual('LOCATE_NO_CAPACITY');

      const timeoutError = new Ndt7TimeoutError('Timed out');
      expect(timeoutError.errorCode).assertEqual('TIMEOUT_ERROR');
      expect(timeoutError.code).assertEqual(10006);

      const connError = new Ndt7ConnectionError('Refused');
      expect(connError.errorCode).assertEqual('CONNECTION_ERROR');
      expect(connError.code).assertEqual(10004);

      const protoError = new Ndt7ProtocolError('Invalid frame');
      expect(protoError.errorCode).assertEqual('PROTOCOL_ERROR');
      expect(protoError.code).assertEqual(10005);

      const secError = new Ndt7SecurityError('Insecure scheme');
      expect(secError.errorCode).assertEqual('SECURITY_ERROR');
      expect(secError.code).assertEqual(10009);

      const abortError = new Ndt7AbortError();
      expect(abortError.errorCode).assertEqual('ABORTED');
      expect(abortError.code).assertEqual(10007);

      const defaultResult = new Ndt7TestResult();
      expect(defaultResult.status).assertEqual('failed');
    });

  });
}
