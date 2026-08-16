# ndt7-arkts — M-Lab NDT7 Client Library for HarmonyOS

[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-API%2018%2B%20(5.1.0--6.0.1%2B)-blue.svg)](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/application-dev-guide-V5)
[![Language](https://img.shields.io/badge/Language-ArkTS%20Stage%20Model-orange.svg)](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/arkts-get-started-V5)
[![Protocol](https://img.shields.io/badge/Protocol-NDT7%20v0.11.0-green.svg)](https://github.com/m-lab/ndt-server/blob/main/spec/ndt7-protocol.md)
[![License](https://img.shields.io/badge/License-Apache%202.0-lightgrey.svg)](LICENSE)

An idiomatic HarmonyOS ArkTS library implementing the **Measurement Lab (M-Lab) NDT7** speed test protocol ([NDT7 Protocol Specification v0.11.0](https://github.com/m-lab/ndt-server/blob/main/spec/ndt7-protocol.md)).

A standalone **HarmonyOS HAR library** with zero UI dependencies, built entirely on HarmonyOS Network Kit (`@kit.NetworkKit`). Runs on wearables, phones, tablets, and 2-in-1 devices.

> Looking for the sample wearable app? See [ndt7-hosw-client](https://github.com/utbuiquoc/ndt7-hosw-client) — a smartwatch speed test app built on this library.

---

## Features

- **Protocol Compliant**: Fully implements the authoritative NDT7 v0.11.0 specification.
- **Server Discovery**: Automatic discovery of the nearest M-Lab server via M-Lab Locate API v2 with support for HTTP 200, 204 (No Capacity), and 3xx redirects, plus multi-server candidate fallback.
- **WebSocket Transport**: Pure ArkTS implementation using `@kit.NetworkKit` with `net.measurementlab.ndt.v7` subprotocol negotiation, enforced `wss://` transport, and connect timeout protection.
- **Download Goodput Test**: Real-time throughput measurement with ~100ms interval progress emissions and a dynamic hard watchdog (1.3× test duration).
- **Upload Goodput Test**: Dynamic chunk scaling starting at 8 KiB (`1 << 13`), scaling by $2\times$ up to 16 MiB (`1 << 24`) per spec appendix, with single-buffer memory reuse.
- **Normative TCP Diagnostics**: Ingests TCPInfo metrics including MinRTT, RTT, retransmission rate, and byte counters.
- **Strict Data Policy Consent**: Enforces `userAcceptedDataPolicy === true` unless explicit `mlabDataPolicyInapplicable` is set.
- **Cancellation / Abort**: Full cooperative cancellation support with instantaneous socket cleanup and state reset.

---

## Project Structure

```
ndt7-arkts/
├── ndt7-arkts/                             # HAR library module
│   ├── index.ets                           # Public barrel export
│   └── src/
│       ├── main/ets/
│       │   ├── client/Ndt7Client.ets       # Client facade & state orchestration
│       │   ├── discovery/LocateClient.ets  # Locate API v2 discovery & URL builder
│       │   ├── protocol/Ndt7WebSocketTransport.ets
│       │   ├── transfer/DownloadRunner.ets
│       │   ├── transfer/UploadRunner.ets
│       │   ├── model/Ndt7Models.ets        # Normative DTOs & state enums
│       │   └── utils/                      # Constants, errors, math
│       └── test/LocalUnit.test.ets         # Hypium unit test suite
└── build-profile.json5
```

---

## Installation

**From the OHPM registry:**

```bash
ohpm install ndt7-arkts
```

**From source** (clone this repository, then in your app's `oh-package.json5`):

```json5
{
  "dependencies": {
    "ndt7-arkts": "file:../path/to/ndt7-arkts/ndt7-arkts"
  }
}
```

Ensure `ohos.permission.INTERNET` is declared in your application's `module.json5`:

```json5
{
  "module": {
    "requestPermissions": [
      {
        "name": "ohos.permission.INTERNET"
      }
    ]
  }
}
```

---

## Usage Guide

### Complete Test Sequence (Discovery $\rightarrow$ Download $\rightarrow$ Upload)

`startTest` resolves with an `Ndt7TestResult` (`status: 'completed'`) on success and **throws** an `Ndt7Error` subtype on failure or abortion (`Ndt7AbortError` after `client.abort()`). Always wrap the call:

```typescript
import { Ndt7Client, Ndt7Config, Ndt7Error, Ndt7State, Ndt7SpeedSummary, Ndt7TestResult } from 'ndt7-arkts';

const client = new Ndt7Client();

const config = new Ndt7Config();
config.userAcceptedDataPolicy = true; // Required by M-Lab data policy
config.metadata = {
  client_name: 'my-harmonyos-app',
  client_version: '1.0.0'
};

try {
  const result: Ndt7TestResult = await client.startTest(config, {
    onStateChange: (state: Ndt7State, message?: string) => {
      console.info(`[NDT7 State] ${state}: ${message}`);
    },
    onServerChosen: (server) => {
      console.info(`Connected to: ${server.machine}`);
    },
    onDownloadProgress: (summary: Ndt7SpeedSummary) => {
      console.info(`Download speed: ${summary.mbps} Mbps`);
    },
    onDownloadComplete: (summary: Ndt7SpeedSummary) => {
      console.info(`Download completed: ${summary.mbps} Mbps`);
    },
    onUploadProgress: (summary: Ndt7SpeedSummary) => {
      console.info(`Upload speed: ${summary.mbps} Mbps`);
    },
    onUploadComplete: (summary: Ndt7SpeedSummary) => {
      console.info(`Upload completed: ${summary.mbps} Mbps`);
    },
    onComplete: (res: Ndt7TestResult) => {
      console.info(`Test complete: ↓ ${res.download?.mbps} Mbps, ↑ ${res.upload?.mbps} Mbps`);
    }
  });
  console.info(`Final status: ${result.status}`);
} catch (error) {
  // Ndt7Error subtype; Ndt7AbortError is thrown when the test was aborted via client.abort()
  const err = error as Ndt7Error;
  console.error(`Test failed: ${err.errorCode}: ${err.message}`);
}
```

### Standalone Download or Upload Test

`startDownload` / `startUpload` follow the same contract: they resolve with an `Ndt7SpeedSummary` on success and throw an `Ndt7Error` on failure, so wrap them in try/catch as shown above.

```typescript
// Run only download test against a specific M-Lab WSS endpoint
const downloadSummary = await client.startDownload('wss://mlab1-ord01.measurement-lab.org/ndt/v7/download', {
  onDownloadProgress: (summary) => {
    console.info(`Live Download: ${summary.mbps} Mbps`);
  }
});

// Run only upload test
const uploadSummary = await client.startUpload('wss://mlab1-ord01.measurement-lab.org/ndt/v7/upload', {
  onUploadProgress: (summary) => {
    console.info(`Live Upload: ${summary.mbps} Mbps`);
  }
});
```

### Canceling / Aborting an Active Test

```typescript
client.abort();
```

---

## Build & Test Commands

```powershell
# Install OHPM dependencies
ohpm install --all

# Run automated Hypium unit tests
hvigorw --mode module -p module=ndt7arkts@default test --no-daemon

# Build the HAR library
hvigorw --mode module -p module=ndt7arkts@default assembleHar --no-daemon
```

---

## Publishing to OHPM

This library is published as `ndt7-arkts` on the [OHPM registry](https://ohpm.openharmony.cn).

```powershell
# One-time: log in with your OHPM account (create one at ohpm.openharmony.cn)
ohpm login

# Build and publish from the module directory
cd ndt7-arkts
ohpm publish
```

---

## References

- [M-Lab NDT7 Protocol Specification](https://github.com/m-lab/ndt-server/blob/main/spec/ndt7-protocol.md)
- [Official M-Lab ndt7-js Client Reference](https://github.com/m-lab/ndt7-js)
- [Official M-Lab ndt7-client-go Reference](https://github.com/m-lab/ndt7-client-go)
- [HarmonyOS Network Kit Documentation](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/net-websocket-connection-V5)

---

## License & Attribution

This project is open-sourced under the **Apache License, Version 2.0**. See the [LICENSE](LICENSE) file for full license terms and [NOTICE](NOTICE) for attributions.

### M-Lab Data Policy & Trademarks

- **Measurement Lab (M-Lab)** is a collaborative research initiative. NDT (Network Diagnostic Tool) measurements conducted against M-Lab servers are subject to the [M-Lab Acceptable Use Policy and Data Policy](https://www.measurementlab.net/privacy/).
- Clients connecting to official M-Lab infrastructure must obtain user consent (`userAcceptedDataPolicy: true`), as measurement data and client IP addresses are collected and published to the public domain for Internet performance research.
- "Measurement Lab" and "M-Lab" are trademarks of their respective owners.
