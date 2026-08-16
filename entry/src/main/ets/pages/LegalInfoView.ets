import {
  ArcList,
  ArcListItem,
  ArcListAttribute,
  ArcListItemAttribute,
  ArcScrollBar,
  LengthMetrics
} from '@kit.ArkUI';
import { PrivacyPolicyView } from './PrivacyPolicyPage';
import { AboutView } from './AboutPage';
import { LicenseView } from './LicensePage';

const DESTINATION_PRIVACY = 'PrivacyPolicy';
const DESTINATION_ABOUT = 'About';
const DESTINATION_LICENSE = 'License';

@Component
export struct LegalInfoView {
  @Link navPathStack: NavPathStack;
  private scroller: Scroller = new Scroller();
  onRevokeConsent: () => void = () => {};

  @Builder
  private pageDestination(name: string) {
    NavDestination() {
      if (name === DESTINATION_PRIVACY) {
        PrivacyPolicyView()
      } else if (name === DESTINATION_ABOUT) {
        AboutView()
      } else if (name === DESTINATION_LICENSE) {
        LicenseView()
      }
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.start_window_background'))
  }

  build() {
    Navigation(this.navPathStack) {
      Stack({ alignContent: Alignment.Center }) {
        // ─── Main ArcList standard from Tasku Architecture (initialIndex: 1 centers items on circular screen) ───
        ArcList({ initialIndex: 1, scroller: this.scroller }) {
          // ─── Section Header: More ───
          ArcListItem() {
            Text($r('app.string.info_page_title'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ndt7_text_secondary'))
              .textAlign(TextAlign.Center)
              .width('100%')
              .maxLines(1)
          }
          .width('88%')
          .height(32)
          .autoScale(false)

          // ─── Item 1: Privacy Policy ───
          ArcListItem() {
            this.ArcCardItem(
              $r('sys.symbol.lock_fill'),
              $r('app.color.ndt7_icon_bg_privacy'),
              $r('app.color.ndt7_accent_download'),
              $r('app.string.info_privacy_title'),
              null,
              () => {
                this.navPathStack.pushPathByName(DESTINATION_PRIVACY, null);
              }
            )
          }
          .width('88%')
          .height(56)

          // ─── Item 2: About (with version) ───
          ArcListItem() {
            this.ArcCardItem(
              $r('sys.symbol.info_circle_fill'),
              $r('app.color.ndt7_icon_bg_about'),
              $r('app.color.ndt7_accent_warn'),
              $r('app.string.info_about_title'),
              $r('app.string.info_about_sub'),
              () => {
                this.navPathStack.pushPathByName(DESTINATION_ABOUT, null);
              }
            )
          }
          .width('88%')
          .height(56)

          // ─── Item 3: Open Source Licenses ───
          ArcListItem() {
            this.ArcCardItem(
              $r('sys.symbol.doc_text_fill'),
              $r('app.color.ndt7_icon_bg_license'),
              $r('app.color.ndt7_accent_upload'),
              $r('app.string.info_license_title'),
              null,
              () => {
                this.navPathStack.pushPathByName(DESTINATION_LICENSE, null);
              }
            )
          }
          .width('88%')
          .height(56)

          // ─── Item 4: Reset Consent (revoke M-Lab data policy) ───
          ArcListItem() {
            this.ArcCardItem(
              $r('sys.symbol.arrow_counterclockwise'),
              $r('app.color.ndt7_icon_bg_reset'),
              $r('app.color.ndt7_accent_error'),
              $r('app.string.info_reset_title'),
              $r('app.string.info_reset_sub'),
              () => {
                this.onRevokeConsent();
              }
            )
          }
          .width('88%')
          .height(56)
        }
        .width('100%')
        .height('100%')
        .space(LengthMetrics.vp(6))
        .scrollBar(BarState.Auto)
        .onDigitalCrown((e) => {
          this.scroller.scrollBy(0, e.degree * 2.3);
        })

        // ─── Circular ArcScrollBar ───
        ArcScrollBar({ scroller: this.scroller })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.start_window_background'))
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .navDestination(this.pageDestination)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
  }

  // ── ArcCard standard pattern from Tasku (icon left + label center + chevron right) ──
  @Builder
  ArcCardItem(
    icon: Resource,
    iconBg: ResourceColor,
    iconFg: ResourceColor,
    label: ResourceStr,
    subLabel: ResourceStr | null,
    onTap: () => void
  ) {
    Button() {
      Stack({ alignContent: Alignment.Center }) {
        // Left Icon + Right Chevron Row
        Row() {
          Column() {
            SymbolGlyph(icon)
              .fontSize(18)
              .fontColor([iconFg])
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(iconBg)
          .justifyContent(FlexAlign.Center)

          Blank()

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('app.color.ndt7_chevron')])
        }
        .width('100%')
        .height('100%')
        .padding({ left: 8, right: 12 })

        // Centered Content
        Column({ space: 1 }) {
          Text(label)
            .fontSize(this.subLabelFontSize(subLabel))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ndt7_text_primary'))
            .maxLines(2)
            .textAlign(TextAlign.Center)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (subLabel !== null) {
            Text(subLabel)
              .fontSize(11)
              .fontWeight(FontWeight.Regular)
              .fontColor($r('app.color.ndt7_text_secondary'))
              .maxLines(1)
              .textAlign(TextAlign.Center)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .padding({ left: 44, right: 30 })
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .borderRadius(28)
    .backgroundColor($r('app.color.ndt7_card_button_bg'))
    .onClick(() => {
      onTap();
    })
  }

  private subLabelFontSize(subLabel: ResourceStr | null): number {
    return subLabel !== null ? 15 : 14;
  }
}
