import { SpeedTestViewModel } from '../viewmodel/SpeedTestViewModel';
import { Ndt7State } from '@mlab/ndt7-ohos';

@Entry
@Component
struct MainPage {
  @State viewModel: SpeedTestViewModel = new SpeedTestViewModel();
  @State refreshTrigger: number = 0;

  aboutToAppear(): void {
    this.viewModel.setOnUpdate(() => {
      this.refreshTrigger++;
    });
  }

  build() {
    Column() {
      // 1. Header & State Badge
      Text('NDT7 Test Harness')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .margin({ top: 12, bottom: 4 })

      Text(`State: ${this.viewModel.state}`)
        .fontSize(11)
        .fontColor(this.getStateColor(this.viewModel.state))
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .backgroundColor('#222222')
        .borderRadius(10)
        .margin({ bottom: 6 })

      // 2. Metrics Block
      Row() {
        Column() {
          Text('↓ DOWNLOAD')
            .fontSize(9)
            .fontColor('#888888')
          Text(`${this.viewModel.downloadMbps.toFixed(1)}`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#00E5FF')
          Text('Mbps')
            .fontSize(9)
            .fontColor('#AAAAAA')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        Divider()
          .vertical(true)
          .height(32)
          .color('#333333')

        Column() {
          Text('↑ UPLOAD')
            .fontSize(9)
            .fontColor('#888888')
          Text(`${this.viewModel.uploadMbps.toFixed(1)}`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#00E676')
          Text('Mbps')
            .fontSize(9)
            .fontColor('#AAAAAA')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }
      .width('84%')
      .padding(6)
      .backgroundColor('#161616')
      .borderRadius(12)
      .margin({ bottom: 4 })

      // 3. Diagnostics & Server Info
      Row() {
        Text(`RTT: ${this.viewModel.latencyMs > 0 ? this.viewModel.latencyMs + ' ms' : '--'}`)
          .fontSize(9)
          .fontColor('#CCCCCC')
          .margin({ right: 8 })

        Text(`Retrans: ${this.viewModel.retransPercent > 0 ? this.viewModel.retransPercent + '%' : '--'}`)
          .fontSize(9)
          .fontColor('#CCCCCC')
      }
      .margin({ bottom: 2 })

      Text(this.viewModel.serverName ? `Server: ${this.viewModel.serverName}` : 'Server: Auto')
        .fontSize(9)
        .fontColor('#888888')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('80%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 6 })

      // 4. Action Button (Start / Cancel)
      if (this.viewModel.isRunning()) {
        Button('Cancel Test')
          .width('70%')
          .height(28)
          .fontSize(11)
          .backgroundColor('#D50000')
          .fontColor('#FFFFFF')
          .borderRadius(14)
          .onClick(() => {
            this.viewModel.cancelSpeedTest();
          })
      } else {
        Button('Start Test')
          .width('70%')
          .height(28)
          .fontSize(11)
          .backgroundColor('#00B0FF')
          .fontColor('#000000')
          .fontWeight(FontWeight.Medium)
          .borderRadius(14)
          .onClick(() => {
            this.viewModel.startSpeedTest();
          })
      }

      // 5. Diagnostic Log Area
      List() {
        ForEach(this.viewModel.logs, (logLine: string, index: number) => {
          ListItem() {
            Text(logLine)
              .fontSize(8)
              .fontColor('#9E9E9E')
              .fontFamily('monospace')
          }
        }, (logLine: string, index: number) => `${index}_${logLine}`)
      }
      .width('84%')
      .height(60)
      .margin({ top: 6, bottom: 8 })
      .padding(4)
      .backgroundColor('#0D0D0D')
      .borderRadius(8)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
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
        return '#888888';
    }
  }
}
