import { SpeedTestViewModel } from '../viewmodel/SpeedTestViewModel';
import { Ndt7State } from '@mlab/ndt7-ohos';
import { ScreenAwakeManager } from '../utils/ScreenAwakeManager';
import {
  ArcButton,
  ArcButtonOptions,
  ArcButtonPosition,
  ArcButtonStyleMode,
  ColorMetrics
} from '@kit.ArkUI';

@Entry
@Component
struct MainPage {
  @State viewModel: SpeedTestViewModel = new SpeedTestViewModel();
  @State refreshTrigger: number = 0;

  aboutToAppear(): void {
    this.viewModel.setContext(getContext(this));
    this.viewModel.setOnUpdate(() => {
      this.refreshTrigger++;
    });
  }

  aboutToDisappear(): void {
    if (this.viewModel.isRunning()) {
      this.viewModel.cancelSpeedTest();
    }
    ScreenAwakeManager.setKeepScreenOn(getContext(this), false);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // Main Center Content
      Column() {
        // 1. App Title
        Text('NDT7 SPEEDTEST')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .margin({ top: 26, bottom: 4 })

        // 2. Status Capsule Badge
        Text(this.getStatusLabel())
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getStateColor(this.viewModel.state))
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .backgroundColor('#1A1A1E')
          .borderRadius(12)
          .margin({ bottom: 10 })

        // 3. Main Speed Dual Card
        Row() {
          // Download Column
          Column() {
            Row() {
              Text('↓')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor('#00E5FF')
                .margin({ right: 2 })
              Text('DOWNLOAD')
                .fontSize(9)
                .fontWeight(FontWeight.Medium)
                .fontColor('#8E8E93')
            }

            Text(`${this.viewModel.downloadMbps.toFixed(1)}`)
              .fontSize(22)
              .fontWeight(FontWeight.Bolder)
              .fontColor(this.viewModel.state === Ndt7State.DOWNLOAD_RUNNING ? '#00E5FF' : '#FFFFFF')
              .margin({ top: 2, bottom: 1 })

            Text('Mbps')
              .fontSize(9)
              .fontColor('#8E8E93')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)

          // Vertical Divider
          Divider()
            .vertical(true)
            .height(44)
            .color('#2C2C2E')

          // Upload Column
          Column() {
            Row() {
              Text('↑')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor('#00E676')
                .margin({ right: 2 })
              Text('UPLOAD')
                .fontSize(9)
                .fontWeight(FontWeight.Medium)
                .fontColor('#8E8E93')
            }

            Text(`${this.viewModel.uploadMbps.toFixed(1)}`)
              .fontSize(22)
              .fontWeight(FontWeight.Bolder)
              .fontColor(this.viewModel.state === Ndt7State.UPLOAD_RUNNING ? '#00E676' : '#FFFFFF')
              .margin({ top: 2, bottom: 1 })

            Text('Mbps')
              .fontSize(9)
              .fontColor('#8E8E93')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }
        .width('82%')
        .padding({ top: 8, bottom: 8, left: 6, right: 6 })
        .backgroundColor('#141416')
        .borderRadius(16)
        .margin({ bottom: 8 })

        // 4. Latency & Retransmission Diagnostics
        Row() {
          Row() {
            Text('RTT')
              .fontSize(9)
              .fontColor('#8E8E93')
              .margin({ right: 4 })
            Text(this.viewModel.latencyMs > 0 ? `${this.viewModel.latencyMs} ms` : '--')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
          }
          .margin({ right: 14 })

          Row() {
            Text('Loss')
              .fontSize(9)
              .fontColor('#8E8E93')
              .margin({ right: 4 })
            Text(this.viewModel.retransPercent > 0 ? `${this.viewModel.retransPercent}%` : '0%')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
          }
        }
        .margin({ bottom: 4 })

        // 5. Server Info
        Text(this.getServerDisplay())
          .fontSize(9)
          .fontColor('#636366')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('72%')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Start)

      // 6. ArcButton attached cleanly to the circular bottom edge
      if (this.viewModel.isRunning()) {
        ArcButton({
          options: new ArcButtonOptions({
            position: ArcButtonPosition.BOTTOM_EDGE,
            styleMode: ArcButtonStyleMode.CUSTOM,
            backgroundColor: ColorMetrics.resourceColor('#D50000'),
            fontColor: ColorMetrics.resourceColor('#FFFFFF'),
            label: 'CANCEL',
            onClick: () => {
              this.viewModel.cancelSpeedTest();
            }
          })
        })
      } else {
        ArcButton({
          options: new ArcButtonOptions({
            position: ArcButtonPosition.BOTTOM_EDGE,
            styleMode: ArcButtonStyleMode.CUSTOM,
            backgroundColor: ColorMetrics.resourceColor('#00E5FF'),
            fontColor: ColorMetrics.resourceColor('#000000'),
            label: 'START TEST',
            onClick: () => {
              this.viewModel.startSpeedTest(getContext(this));
            }
          })
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }

  private getStatusLabel(): string {
    switch (this.viewModel.state) {
      case Ndt7State.IDLE:
        return 'Ready';
      case Ndt7State.DISCOVERING:
        return 'Finding Server...';
      case Ndt7State.DOWNLOAD_CONNECTING:
        return 'Connecting Download...';
      case Ndt7State.DOWNLOAD_RUNNING:
        return 'Testing Download...';
      case Ndt7State.UPLOAD_CONNECTING:
        return 'Connecting Upload...';
      case Ndt7State.UPLOAD_RUNNING:
        return 'Testing Upload...';
      case Ndt7State.COMPLETED:
        return 'Test Completed';
      case Ndt7State.CANCELED:
        return 'Canceled';
      case Ndt7State.FAILED:
        return 'Test Failed';
      default:
        return this.viewModel.state;
    }
  }

  private getServerDisplay(): string {
    if (this.viewModel.serverCity) {
      return `Server: ${this.viewModel.serverCity}`;
    }
    if (this.viewModel.serverName && this.viewModel.serverName !== 'Auto (Locate API)') {
      return `Server: ${this.viewModel.serverName}`;
    }
    return 'Server: Auto (M-Lab Locate)';
  }

  private getStateColor(state: Ndt7State): string {
    switch (state) {
      case Ndt7State.DISCOVERING:
        return '#FFD600';
      case Ndt7State.DOWNLOAD_CONNECTING:
      case Ndt7State.DOWNLOAD_RUNNING:
        return '#00E5FF';
      case Ndt7State.UPLOAD_CONNECTING:
      case Ndt7State.UPLOAD_RUNNING:
        return '#00E676';
      case Ndt7State.COMPLETED:
        return '#76FF03';
      case Ndt7State.CANCELED:
        return '#FF9100';
      case Ndt7State.FAILED:
        return '#FF1744';
      default:
        return '#8E8E93';
    }
  }
}
