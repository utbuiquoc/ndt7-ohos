import { SpeedTestViewModel } from '../viewmodel/SpeedTestViewModel';
import { Ndt7State } from '@mlab/ndt7-ohos';
import { ScreenAwakeManager } from '../utils/ScreenAwakeManager';
import {
  ArcButton,
  ArcButtonOptions,
  ArcButtonPosition,
  ArcButtonStyleMode,
  ArcScrollBar,
  ColorMetrics
} from '@kit.ArkUI';

@Entry
@Component
struct MainPage {
  @State viewModel: SpeedTestViewModel = new SpeedTestViewModel();
  @State refreshTrigger: number = 0;
  @State hasAcceptedPolicy: boolean = false;
  @State isCheckingPolicy: boolean = true;
  private policyScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const ctx = getContext(this);
    this.viewModel.setContext(ctx);
    this.viewModel.setOnUpdate(() => {
      this.refreshTrigger++;
    });

    this.viewModel.loadConsent(ctx).then((accepted: boolean) => {
      this.hasAcceptedPolicy = accepted;
      this.isCheckingPolicy = false;
    }).catch(() => {
      this.hasAcceptedPolicy = false;
      this.isCheckingPolicy = false;
    });
  }

  aboutToDisappear(): void {
    this.viewModel.setOnUpdate(undefined);
    if (this.viewModel.isRunning()) {
      this.viewModel.cancelSpeedTest();
    }
    ScreenAwakeManager.setKeepScreenOn(getContext(this), false);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.isCheckingPolicy) {
        // Initial silent loading placeholder
        Column()
          .width('100%')
          .height('100%')
      } else if (!this.hasAcceptedPolicy) {
        // ─── First-Launch M-Lab Data Policy Consent Screen (Unified Full-Height Document) ───
        Scroll(this.policyScroller) {
          Column() {
            // 1. Policy Header
            Text($r('app.string.policy_title'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .margin({ top: 26, bottom: 4 })

            Text($r('app.string.policy_badge'))
              .fontSize(9)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ndt7_accent_download'))
              .backgroundColor($r('app.color.ndt7_badge_bg'))
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(10)
              .margin({ bottom: 12 })

            // 2. Single Continuous Policy Document Card
            Column({ space: 10 }) {
              // Section 1
              Column({ space: 3 }) {
                Text($r('app.string.policy_sec1_title'))
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.ndt7_accent_download'))
                Text($r('app.string.policy_sec1_body'))
                  .fontSize(10)
                  .fontColor($r('app.color.ndt7_text_secondary'))
                  .lineHeight(14)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              Divider().color($r('app.color.ndt7_divider')).height(1)

              // Section 2
              Column({ space: 3 }) {
                Text($r('app.string.policy_sec2_title'))
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.ndt7_accent_download'))
                Text($r('app.string.policy_sec2_body'))
                  .fontSize(10)
                  .fontColor($r('app.color.ndt7_text_secondary'))
                  .lineHeight(14)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              Divider().color($r('app.color.ndt7_divider')).height(1)

              // Section 3
              Column({ space: 3 }) {
                Text($r('app.string.policy_sec3_title'))
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.ndt7_accent_download'))
                Text($r('app.string.policy_sec3_body'))
                  .fontSize(10)
                  .fontColor($r('app.color.ndt7_text_secondary'))
                  .lineHeight(14)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              Divider().color($r('app.color.ndt7_divider')).height(1)

              // Section 4
              Column({ space: 3 }) {
                Text($r('app.string.policy_sec4_title'))
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.ndt7_accent_download'))
                Text($r('app.string.policy_sec4_body'))
                  .fontSize(10)
                  .fontColor($r('app.color.ndt7_text_secondary'))
                  .lineHeight(14)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              // Document End Cue
              Text($r('app.string.policy_scroll_cue'))
                .fontSize(9)
                .fontColor($r('app.color.ndt7_text_tertiary'))
                .textAlign(TextAlign.Center)
                .width('100%')
                .margin({ top: 4 })
            }
            .width('86%')
            .padding({ top: 12, bottom: 12, left: 10, right: 10 })
            .backgroundColor($r('app.color.ndt7_card_bg'))
            .borderRadius(16)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({ bottom: 78 })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        // Arc ScrollBar curving along the circular bezel
        ArcScrollBar({
          scroller: this.policyScroller
        })

        // 3. Agree Arc Button - Floats over the bottom arc, shifted closer to bezel
        ArcButton({
          options: new ArcButtonOptions({
            position: ArcButtonPosition.BOTTOM_EDGE,
            styleMode: ArcButtonStyleMode.CUSTOM,
            backgroundColor: ColorMetrics.resourceColor($r('app.color.ndt7_accent_download')),
            fontColor: ColorMetrics.resourceColor('#000000'),
            label: $r('app.string.btn_agree_continue'),
            onClick: () => {
              this.viewModel.acceptPolicy(getContext(this)).then(() => {
                this.hasAcceptedPolicy = true;
              });
            }
          })
        })
        .offset({ y: 4 })
      } else {
        // ─── Main Speed Test Dashboard ───
        Column() {
          // Unconditionally rendered invisible state observer ensuring ArkUI re-renders on ViewModel notifications
          Text(String(this.refreshTrigger))
            .width(0)
            .height(0)
            .visibility(Visibility.None)

          // 1. App Title
          Text($r('app.string.ndt7_title'))
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
            .backgroundColor($r('app.color.ndt7_badge_bg'))
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
                  .fontColor($r('app.color.ndt7_accent_download'))
                  .margin({ right: 2 })
                Text($r('app.string.label_download'))
                  .fontSize(9)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ndt7_text_secondary'))
              }

              Text(`${this.viewModel.downloadMbps.toFixed(1)}`)
                .fontSize(22)
                .fontWeight(FontWeight.Bolder)
                .fontColor(this.viewModel.state === Ndt7State.DOWNLOAD_RUNNING ? '#00E5FF' : '#FFFFFF')
                .margin({ top: 2, bottom: 1 })

              Text($r('app.string.label_mbps'))
                .fontSize(9)
                .fontColor($r('app.color.ndt7_text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)

            // Vertical Divider
            Divider()
              .vertical(true)
              .height(44)
              .color($r('app.color.ndt7_divider'))

            // Upload Column
            Column() {
              Row() {
                Text('↑')
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.ndt7_accent_upload'))
                  .margin({ right: 2 })
                Text($r('app.string.label_upload'))
                  .fontSize(9)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ndt7_text_secondary'))
              }

              Text(`${this.viewModel.uploadMbps.toFixed(1)}`)
                .fontSize(22)
                .fontWeight(FontWeight.Bolder)
                .fontColor(this.viewModel.state === Ndt7State.UPLOAD_RUNNING ? '#00E676' : '#FFFFFF')
                .margin({ top: 2, bottom: 1 })

              Text($r('app.string.label_mbps'))
                .fontSize(9)
                .fontColor($r('app.color.ndt7_text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
          }
          .width('82%')
          .padding({ top: 8, bottom: 8, left: 6, right: 6 })
          .backgroundColor($r('app.color.ndt7_card_bg'))
          .borderRadius(16)
          .margin({ bottom: 8 })

          // 4. Latency & Retransmission Diagnostics
          Row() {
            Row() {
              Text($r('app.string.label_rtt'))
                .fontSize(9)
                .fontColor($r('app.color.ndt7_text_secondary'))
                .margin({ right: 4 })
              Text(this.viewModel.latencyMs > 0 ? `${this.viewModel.latencyMs} ms` : '--')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
            }
            .margin({ right: 14 })

            Row() {
              Text($r('app.string.label_loss'))
                .fontSize(9)
                .fontColor($r('app.color.ndt7_text_secondary'))
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
            .fontColor($r('app.color.ndt7_text_tertiary'))
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
              backgroundColor: ColorMetrics.resourceColor($r('app.color.ndt7_btn_cancel_bg')),
              fontColor: ColorMetrics.resourceColor('#FFFFFF'),
              label: $r('app.string.btn_cancel'),
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
              backgroundColor: ColorMetrics.resourceColor($r('app.color.ndt7_accent_download')),
              fontColor: ColorMetrics.resourceColor('#000000'),
              label: $r('app.string.btn_start_test'),
              onClick: () => {
                this.viewModel.startSpeedTest(getContext(this));
              }
            })
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }

  private getStatusLabel(): ResourceStr {
    switch (this.viewModel.state) {
      case Ndt7State.IDLE:
        return $r('app.string.status_ready');
      case Ndt7State.DISCOVERING:
        return $r('app.string.status_finding_server');
      case Ndt7State.DOWNLOAD_CONNECTING:
        return $r('app.string.status_connecting_download');
      case Ndt7State.DOWNLOAD_RUNNING:
        return $r('app.string.status_testing_download');
      case Ndt7State.UPLOAD_CONNECTING:
        return $r('app.string.status_connecting_upload');
      case Ndt7State.UPLOAD_RUNNING:
        return $r('app.string.status_testing_upload');
      case Ndt7State.COMPLETED:
        return $r('app.string.status_completed');
      case Ndt7State.CANCELED:
        return $r('app.string.status_canceled');
      case Ndt7State.FAILED:
        return $r('app.string.status_failed');
      default:
        return this.viewModel.statusMessage || String(this.viewModel.state);
    }
  }

  private getServerDisplay(): ResourceStr {
    if (this.viewModel.serverCity) {
      return `Server: ${this.viewModel.serverCity}`;
    }
    if (this.viewModel.serverName && this.viewModel.serverName !== 'Auto (Locate API)') {
      return `Server: ${this.viewModel.serverName}`;
    }
    return $r('app.string.label_server_auto');
  }

  private getStateColor(state: Ndt7State): ResourceColor {
    switch (state) {
      case Ndt7State.DISCOVERING:
        return $r('app.color.ndt7_accent_warn');
      case Ndt7State.DOWNLOAD_CONNECTING:
      case Ndt7State.DOWNLOAD_RUNNING:
        return $r('app.color.ndt7_accent_download');
      case Ndt7State.UPLOAD_CONNECTING:
      case Ndt7State.UPLOAD_RUNNING:
        return $r('app.color.ndt7_accent_upload');
      case Ndt7State.COMPLETED:
        return $r('app.color.ndt7_accent_success');
      case Ndt7State.CANCELED:
        return $r('app.color.ndt7_accent_canceled');
      case Ndt7State.FAILED:
        return $r('app.color.ndt7_accent_error');
      default:
        return $r('app.color.ndt7_text_secondary');
    }
  }
}
