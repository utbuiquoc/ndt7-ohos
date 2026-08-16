# M-Lab NDT7 Client for HarmonyOS (ArkTS / Stage Model)

[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-API%2018%2B%20(5.1.0--6.0.1%2B)-blue.svg)](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/application-dev-guide-V5)
[![Language](https://img.shields.io/badge/Language-ArkTS%20Stage%20Model-orange.svg)](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/arkts-get-started-V5)
[![Protocol](https://img.shields.io/badge/Protocol-NDT7%20v0.11.0-green.svg)](https://github.com/m-lab/ndt-server/blob/main/spec/ndt7-protocol.md)
[![License](https://img.shields.io/badge/License-Apache%202.0-lightgrey.svg)](LICENSE)

An idiomatic, high-performance HarmonyOS ArkTS library implementing the **Measurement Lab (M-Lab) NDT7** speed test protocol ([NDT7 Protocol Specification v0.11.0](https://github.com/m-lab/ndt-server/blob/main/spec/ndt7-protocol.md)).

Designed as a standalone **HarmonyOS HAR library** (`@mlab/ndt7-ohos`) with zero UI dependencies, built entirely using HarmonyOS Network Kit (`@kit.NetworkKit`). Includes a sample Wearable validation test harness app (`entry`).

---

## Features

- **Protocol Compliant**: Fully implements the authoritative NDT7 v0.11.0 specification.
- **Server Discovery**: Automatic discovery of the nearest M-Lab server via M-Lab Locate API v2 with support for HTTP 200, 204 (No Capacity), and 3xx Redirects.
- **WebSocket Transport**: Pure ArkTS implementation using `@kit.NetworkKit` with `net.measurementlab.ndt.v7` subprotocol negotiation.
- **Download Goodput Test**: Real-time throughput measurement with ~100ms interval progress emissions and a dynamic hard watchdog (1.3× test duration).
- **Upload Goodput Test**: Dynamic chunk scaling starting at 8 KiB (`1 << 13`), scaling by $2\times$ up to 16 MiB (`1 << 24`) per spec appendix, with single-buffer memory reuse.
- **Normative TCP Diagnostics**: Ingests TCPInfo metrics including MinRTT, RTT, retransmission rate, and byte counters.
- **Strict Data Policy Consent**: Enforces `userAcceptedDataPolicy === true` unless explicit `mlabDataPolicyInapplicable` is set.
- **Cancellation / Abort**: Full cooperative cancellation support with instantaneous socket cleanup and state reset.
- **Wearable-First Sample App**: The bundled `entry` app targets smartwatches (circular 466x466, wearable-only `deviceTypes`); the library itself is device-agnostic and runs on phones, tablets, 2-in-1, and wearables.

---

## Project Structure

```
ndt7-ohos/
├── ndt7/                                   # Standalone HAR Library (@mlab/ndt7-ohos)
│   ├── index.ets                           # Public barrel export
│   └── src/
│       ├── main/ets/
│       │   ├── client/
│       │   │   └── Ndt7Client.ets          # Client facade & state orchestration
│       │   ├── discovery/
│       │   │   └── LocateClient.ets        # Locate API v2 discovery & URL builder
│       │   ├── protocol/
│       │   │   └── Ndt7WebSocketTransport.ets # NetworkKit WebSocket wrapper
│       │   ├── transfer/
│       │   │   ├── DownloadRunner.ets      # Download measurement runner
│       │   │   └── UploadRunner.ets        # Upload runner with dynamic scaling
│       │   ├── model/
│       │   │   └── Ndt7Models.ets          # Normative DTOs & state enums
│       │   └── utils/
│       │       ├── Ndt7Constants.ets       # Protocol limits & constants
│       │       ├── Ndt7Errors.ets          # BusinessError-compliant error hierarchy
│       │       └── Ndt7Math.ets            # Bitrate math & formatting utilities
│       └── test/
│           └── LocalUnit.test.ets          # Hypium unit test suite
├── entry/                                  # Wearable Speed Test App (HAP)
│   └── src/main/ets/
│       ├── entryability/EntryAbility.ets
│       ├── viewmodel/SpeedTestViewModel.ets
│       ├── utils/
│       │   ├── ConsentPreferencesManager.ets  # M-Lab policy consent persistence
│       │   └── ScreenAwakeManager.ets         # Keep-screen-on during tests
│       └── pages/
│           ├── MainPage.ets                # Circular dashboard + swipe pager + consent screen
│           └── LegalInfoView.ets           # Privacy / About / License subpages
└── build-profile.json5
```

---

## Installation

Add the dependency to your project's `oh-package.json5`:

```json5
{
  "dependencies": {
    "@mlab/ndt7-ohos": "file:../ndt7"
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
import { Ndt7Client, Ndt7Config, Ndt7Error, Ndt7State, Ndt7SpeedSummary, Ndt7TestResult } from '@mlab/ndt7-ohos';

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
ohpm install

# Run automated Hypium unit tests
hvigorw test --no-daemon

# Build standalone HAR library
hvigorw --mode module -p module=ndt7@default assembleHar --no-daemon

# Build test harness HAP
hvigorw --mode module -p module=entry@default assembleHap --no-daemon

# Install and run on connected device/emulator via HDC
hdc install -r entry\build\default\outputs\default\entry-default-unsigned.hap
hdc shell aa start -a EntryAbility -b com.kuni.ndt7st
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

```
Copyright 2026 Quoc Bui and ndt7-ohos contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

### M-Lab Data Policy & Trademarks

- **Measurement Lab (M-Lab)** is a collaborative research initiative. NDT (Network Diagnostic Tool) measurements conducted against M-Lab servers are subject to the [M-Lab Acceptable Use Policy and Data Policy](https://www.measurementlab.net/privacy/).
- Clients connecting to official M-Lab infrastructure must obtain user consent (`userAcceptedDataPolicy: true`), as measurement data and client IP addresses are collected and published to the public domain for Internet performance research.
- "Measurement Lab" and "M-Lab" are trademarks of their respective owners.

