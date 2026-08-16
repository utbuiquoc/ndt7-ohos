import { SpeedTestViewModel } from '../viewmodel/SpeedTestViewModel';
import { Ndt7State } from '@mlab/ndt7-ohos';
import { ScreenAwakeManager } from '../utils/ScreenAwakeManager';
import { LegalInfoView } from './LegalInfoView';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  curves,
  ArcButton,
  ArcButtonOptions,
  ArcButtonPosition,
  ArcButtonStyleMode,
  ArcScrollBar,
  ColorMetrics
} from '@kit.ArkUI';

const DOMAIN = 0xA11A;
const TAG = 'MainPage';

const PAGE_HOME = 0;
const PAGE_SETTINGS = 1;

@Entry
@Component
struct MainPage {
  viewModel: SpeedTestViewModel = new SpeedTestViewModel();
  @State hasAcceptedPolicy: boolean = false;
  @State isCheckingPolicy: boolean = true;
  @State isAcceptingPolicy: boolean = false;
  @State pageIndex: number = PAGE_HOME;
  @State viewportWidth: number = 466;
  @State dragOffsetX: number = 0;
  @State settling: boolean = false;
  @State legalNavStack: NavPathStack = new NavPathStack();
  private policyScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const ctx = getContext(this);
    this.viewModel.setContext(ctx);

    this.viewModel.loadConsent(ctx).then((accepted: boolean) => {
      this.hasAcceptedPolicy = accepted;
      this.isCheckingPolicy = false;
    }).catch(() => {
      this.hasAcceptedPolicy = false;
      this.isCheckingPolicy = false;
    });
  }

  aboutToDisappear(): void {
    if (this.viewModel.isRunning()) {
      this.viewModel.cancelSpeedTest();
    }
    ScreenAwakeManager.setKeepScreenOn(getContext(this), false);
    ScreenAwakeManager.reset();
  }

  onBackPress(): boolean | void {
    if (this.legalNavStack.size() > 0) {
      this.legalNavStack.pop();
      return true;
    }
    if (this.pageIndex === PAGE_SETTINGS) {
      this.settleToPage(PAGE_HOME);
      return true;
    }
    return false;
  }

  // ─── Interactive Pager Motion Policy from Chinou Architecture ───
  private rootPanDirection(): PanDirection {
    // If inside a NavDestination sub-page, yield gesture to Navigation swipe-back
    if (this.legalNavStack.size() > 0) {
      return PanDirection.None;
    }
    if (this.pageIndex === PAGE_HOME) {
      return PanDirection.Left;
    }
    if (this.pageIndex === PAGE_SETTINGS) {
      return PanDirection.Right;
    }
    return PanDirection.None;
  }

  private updateRootDrag(offsetX: number): void {
    const pageWidth = this.viewportWidth;
    if (pageWidth <= 0) {
      return;
    }
    this.settling = false;
    if (this.pageIndex === PAGE_HOME) {
      this.dragOffsetX = Math.max(-pageWidth, Math.min(0, offsetX));
    } else {
      this.dragOffsetX = Math.min(pageWidth, Math.max(0, offsetX));
    }
  }

  private finishRootDrag(event: GestureEvent): void {
    const target = this.pageIndex === PAGE_HOME ? PAGE_SETTINGS : PAGE_HOME;
    const forwardVelocity = this.pageIndex === PAGE_HOME ? -event.velocityX : event.velocityX;
    const distance = Math.abs(this.dragOffsetX);

    if (distance >= this.viewportWidth * 0.28 || forwardVelocity >= 900) {
      this.settleToPage(target);
    } else {
      this.cancelRootDrag();
    }
  }

  private cancelRootDrag(): void {
    if (this.dragOffsetX === 0) {
      return;
    }
    this.settling = true;
    this.getUIContext().animateTo({
      duration: 240,
      curve: curves.responsiveSpringMotion(0.32, 0.82, 0.1),
      onFinish: () => {
        this.settling = false;
        this.dragOffsetX = 0;
      }
    }, () => {
      this.dragOffsetX = 0;
    });
  }

  private settleToPage(index: number): void {
    if (index === PAGE_SETTINGS) {
      // Switch state immediately so pan direction switches to Right instantly
      const initialSettingsOffset = this.viewportWidth + (this.pageIndex === PAGE_HOME ? this.dragOffsetX : 0);
      this.pageIndex = PAGE_SETTINGS;
      this.dragOffsetX = initialSettingsOffset;
      this.settling = true;
      this.getUIContext().animateTo({
        duration: 240,
        curve: curves.responsiveSpringMotion(0.32, 0.82, 0.1),
        onFinish: () => {
          this.settling = false;
          this.dragOffsetX = 0;
        }
      }, () => {
        this.dragOffsetX = 0;
      });
    } else {
      // Switch state immediately so pan direction switches to Left instantly
      const initialHomeOffset = -this.viewportWidth + (this.pageIndex === PAGE_SETTINGS ? this.dragOffsetX : 0);
      this.pageIndex = PAGE_HOME;
      this.dragOffsetX = initialHomeOffset;
      this.settling = true;
      this.getUIContext().animateTo({
        duration: 240,
        curve: curves.responsiveSpringMotion(0.32, 0.82, 0.1),
        onFinish: () => {
          this.settling = false;
          this.dragOffsetX = 0;
        }
      }, () => {
        this.dragOffsetX = 0;
      });
    }
  }

  private homePageOffset(): number {
    if (this.viewportWidth <= 0) {
      return 0;
    }
    return this.pageIndex === PAGE_HOME
      ? this.dragOffsetX
      : -this.viewportWidth + this.dragOffsetX;
  }

  private settingsPageOffset(): number {
    if (this.viewportWidth <= 0) {
      return 0;
    }
    return this.pageIndex === PAGE_HOME
      ? this.viewportWidth + this.dragOffsetX
      : this.dragOffsetX;
  }

  private isPageVisible(page: number): Visibility {
    if (this.pageIndex === page || this.dragOffsetX !== 0 || this.settling) {
      return Visibility.Visible;
    }
    return Visibility.Hidden;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.isCheckingPolicy) {
        // Initial silent loading placeholder
        Column()
          .width('100%')
          .height('100%')
      } else if (!this.hasAcceptedPolicy) {
        // ─── First-Launch M-Lab Data Policy Consent Screen (Standard Wearable Consent Dialog) ───
        Scroll(this.policyScroller) {
          Column() {
            // 1. Policy Header
            Text($r('app.string.policy_title'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.ndt7_text_primary'))
              .margin({ top: 28, bottom: 4 })

            Text($r('app.string.policy_badge'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ndt7_accent_download'))
              .backgroundColor($r('app.color.ndt7_badge_bg'))
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .borderRadius(12)
              .margin({ bottom: 14 })

            // 2. Single Continuous Policy Document Card
            Column({ space: 14 }) {
              // Section 1
              Column({ space: 5 }) {
                Text($r('app.string.policy_sec1_title'))
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.ndt7_accent_download'))
                Text($r('app.string.policy_sec1_body'))
                  .fontSize(14)
                  .fontColor($r('app.color.ndt7_text_body'))
                  .lineHeight(20)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              Divider().color($r('app.color.ndt7_divider')).height(1)

              // Section 2
              Column({ space: 5 }) {
                Text($r('app.string.policy_sec2_title'))
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.ndt7_accent_download'))
                Text($r('app.string.policy_sec2_body'))
                  .fontSize(14)
                  .fontColor($r('app.color.ndt7_text_body'))
                  .lineHeight(20)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              Divider().color($r('app.color.ndt7_divider')).height(1)

              // Section 3
              Column({ space: 5 }) {
                Text($r('app.string.policy_sec3_title'))
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.ndt7_accent_download'))
                Text($r('app.string.policy_sec3_body'))
                  .fontSize(14)
                  .fontColor($r('app.color.ndt7_text_body'))
                  .lineHeight(20)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')

              Divider().color($r('app.color.ndt7_divider')).height(1)

              // Section 4
              Column({ space: 5 }) {
                Text($r('app.string.policy_sec4_title'))
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.ndt7_accent_download'))
                Text($r('app.string.policy_sec4_body'))
                  .fontSize(14)
                  .fontColor($r('app.color.ndt7_text_body'))
                  .lineHeight(20)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            }
            .width('88%')
            .padding({ top: 14, bottom: 14, left: 12, right: 12 })
            .backgroundColor($r('app.color.ndt7_card_bg'))
            .borderRadius(16)
            .alignItems(HorizontalAlign.Start)

            // 3. Primary Agree Button ("Agree")
            Button($r('app.string.btn_agree'), { type: ButtonType.Capsule, stateEffect: true })
              .width('68%')
              .height(42)
              .backgroundColor($r('app.color.ndt7_btn_agree_bg'))
              .fontColor($r('app.color.ndt7_text_primary'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .enabled(!this.isAcceptingPolicy)
              .margin({ top: 16, bottom: 10 })
              .onClick(() => {
                if (this.isAcceptingPolicy) {
                  return;
                }
                this.isAcceptingPolicy = true;
                this.viewModel.acceptPolicy(getContext(this)).then(() => {
                  this.hasAcceptedPolicy = true;
                  this.isAcceptingPolicy = false;
                }).catch((err: Object) => {
                  this.hasAcceptedPolicy = false;
                  this.isAcceptingPolicy = false;
                  hilog.error(DOMAIN, TAG, 'Failed to persist policy consent: %{public}s', String(err));
                });
              })

            // 4. Secondary Decline Button ("Decline")
            Button($r('app.string.btn_decline'), { type: ButtonType.Capsule, stateEffect: true })
              .width('68%')
              .height(42)
              .backgroundColor($r('app.color.ndt7_btn_decline_bg'))
              .fontColor($r('app.color.ndt7_btn_decline_text'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .margin({ bottom: 28 })
              .onClick(() => {
                try {
                  (getContext(this) as common.UIAbilityContext).terminateSelf();
                } catch (err) {
                  hilog.warn(DOMAIN, TAG, 'terminateSelf failed: %{public}s', String(err));
                }
              })
          }
          .width('100%')
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
      } else {
        // ─── Multi-Panel Pager (Native Interactive Swiper Architecture from Chinou) ───
        Stack() {
          // Page 0: Main Speed Test Dashboard
          Stack({ alignContent: Alignment.Bottom }) {
            Column() {
              // 1. App Title
              Text($r('app.string.ndt7_title'))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.ndt7_text_primary'))
                .margin({ top: 24, bottom: 4 })

              // 2. Status Capsule Badge
              Text(this.getStatusLabel())
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.getStateColor(this.viewModel.state))
                .padding({ left: 12, right: 12, top: 3, bottom: 3 })
                .backgroundColor($r('app.color.ndt7_badge_bg'))
                .borderRadius(12)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: '78%' })
                .textAlign(TextAlign.Center)
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
                    .fontColor(this.viewModel.state === Ndt7State.DOWNLOAD_RUNNING ? $r('app.color.ndt7_accent_download') : $r('app.color.ndt7_text_primary'))
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
                    .fontColor(this.viewModel.state === Ndt7State.UPLOAD_RUNNING ? $r('app.color.ndt7_accent_upload') : $r('app.color.ndt7_text_primary'))
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
                    .fontColor($r('app.color.ndt7_text_primary'))
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
                    .fontColor($r('app.color.ndt7_text_primary'))
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

            // ArcButton attached cleanly to the circular bottom edge
            if (this.viewModel.isRunning()) {
              ArcButton({
                options: new ArcButtonOptions({
                  position: ArcButtonPosition.BOTTOM_EDGE,
                  styleMode: ArcButtonStyleMode.CUSTOM,
                  backgroundColor: ColorMetrics.resourceColor($r('app.color.ndt7_btn_cancel_bg')),
                  fontColor: ColorMetrics.resourceColor($r('app.color.ndt7_text_primary')),
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
                  backgroundColor: ColorMetrics.resourceColor($r('app.color.ndt7_btn_agree_bg')),
                  fontColor: ColorMetrics.resourceColor($r('app.color.ndt7_text_primary')),
                  label: this.getTestButtonLabel(),
                  onClick: () => {
                    this.viewModel.startSpeedTest(getContext(this));
                  }
                })
              })
            }
          }
          .width('100%')
          .height('100%')
          .translate({ x: this.homePageOffset() })
          .visibility(this.isPageVisible(PAGE_HOME))

          // Page 1: Legal Info / Settings Panel
          Stack() {
            LegalInfoView({
              navPathStack: $legalNavStack,
              onRevokeConsent: () => {
                this.viewModel.revokePolicy(getContext(this)).then(() => {
                  this.hasAcceptedPolicy = false;
                  this.pageIndex = PAGE_HOME;
                  this.dragOffsetX = 0;
                }).catch((err: Object) => {
                  hilog.error(DOMAIN, TAG, 'Failed to revoke consent: %{public}s', String(err));
                });
              }
            })
          }
          .width('100%')
          .height('100%')
          .translate({ x: this.settingsPageOffset() })
          .visibility(this.isPageVisible(PAGE_SETTINGS))
        }
        .width('100%')
        .height('100%')
        .clip(true)
        .gesture(
          PanGesture({
            fingers: 1,
            direction: this.rootPanDirection(),
            distance: 12
          })
            .onActionUpdate((event: GestureEvent) => this.updateRootDrag(event.offsetX))
            .onActionEnd((event: GestureEvent) => this.finishRootDrag(event))
            .onActionCancel(() => this.cancelRootDrag())
        )
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          const width = Number.parseFloat(`${newArea.width}`);
          if (Number.isFinite(width) && width > 0) {
            this.viewportWidth = width;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
  }

  private getTestButtonLabel(): ResourceStr {
    if (this.viewModel.state === Ndt7State.COMPLETED ||
        this.viewModel.state === Ndt7State.FAILED ||
        this.viewModel.state === Ndt7State.CANCELED) {
      return $r('app.string.btn_test_again');
    }
    return $r('app.string.btn_start_test');
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
        return this.viewModel.statusMessage || $r('app.string.status_failed');
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
