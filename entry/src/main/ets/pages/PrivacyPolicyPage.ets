import {
  ArcScrollBar
} from '@kit.ArkUI';

@Component
export struct PrivacyPolicyView {
  private scroller: Scroller = new Scroller();

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Scroll(this.scroller) {
        Column({ space: 10 }) {
          // ─── Header ───
          Text($r('app.string.info_privacy_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ndt7_accent_download'))
            .textAlign(TextAlign.Center)
            .width('100%')
            .maxLines(1)
            .margin({ top: 28, bottom: 4 })

          // ─── Section 1: Overview ───
          Column({ space: 8 }) {
            Text($r('app.string.info_privacy_badge'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.ndt7_text_primary'))
              .textAlign(TextAlign.Center)
              .width('100%')

            Text($r('app.string.info_privacy_desc'))
              .fontSize(13)
              .fontColor($r('app.color.ndt7_text_desc'))
              .lineHeight(19)
              .textAlign(TextAlign.Center)
          }
          .width('88%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .backgroundColor($r('app.color.ndt7_card_item_bg'))
          .borderRadius(18)
          .alignItems(HorizontalAlign.Center)

          // ─── Section 2: App Privacy Policy QR Code ───
          Column({ space: 8 }) {
            Text($r('app.string.info_app_privacy_title'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.ndt7_text_primary'))

            Text($r('app.string.info_scan_hint'))
              .fontSize(12)
              .fontColor($r('app.color.ndt7_text_secondary'))

            QRCode($r('app.string.info_app_privacy_url'))
              .width(130)
              .height(130)
              .color('#000000')
              .backgroundColor('#FFFFFF')
              .padding(8)
              .borderRadius(12)
              .margin({ top: 4, bottom: 2 })
          }
          .width('88%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .backgroundColor($r('app.color.ndt7_card_item_bg'))
          .borderRadius(18)
          .alignItems(HorizontalAlign.Center)

          // ─── Section 3: M-Lab Privacy & Data Policy QR Code ───
          Column({ space: 8 }) {
            Text($r('app.string.info_mlab_privacy_title'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.ndt7_text_primary'))
              .textAlign(TextAlign.Center)

            Text($r('app.string.info_scan_hint'))
              .fontSize(12)
              .fontColor($r('app.color.ndt7_text_secondary'))

            QRCode($r('app.string.info_privacy_url'))
              .width(130)
              .height(130)
              .color('#000000')
              .backgroundColor('#FFFFFF')
              .padding(8)
              .borderRadius(12)
              .margin({ top: 4, bottom: 2 })
          }
          .width('88%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .backgroundColor($r('app.color.ndt7_card_item_bg'))
          .borderRadius(18)
          .alignItems(HorizontalAlign.Center)

          // Bottom Spacer for clean circular overscroll
          Column().width('100%').height(44)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onDigitalCrown((e) => {
        this.scroller.scrollBy(0, e.degree * 2.3);
      })

      // Circular ArcScrollBar
      ArcScrollBar({ scroller: this.scroller })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
  }
}
