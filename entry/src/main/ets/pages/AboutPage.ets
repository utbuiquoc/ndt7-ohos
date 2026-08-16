import {
  ArcScrollBar
} from '@kit.ArkUI';

@Component
export struct AboutView {
  private scroller: Scroller = new Scroller();

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Scroll(this.scroller) {
        Column({ space: 10 }) {
          // ─── Header ───
          Text($r('app.string.info_about_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ndt7_text_primary'))
            .textAlign(TextAlign.Center)
            .width('100%')
            .maxLines(1)
            .margin({ top: 28, bottom: 4 })

          // ─── Section 1: App Info (Key-Value Rows) ───
          Column({ space: 10 }) {
            Text($r('app.string.app_name'))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.ndt7_accent_warn'))
              .textAlign(TextAlign.Center)
              .width('100%')

            Divider().color($r('app.color.ndt7_divider')).height(1).width('100%')

            Row() {
              Text($r('app.string.info_about_version_label'))
                .fontSize(13)
                .fontColor($r('app.color.ndt7_text_secondary'))
              Blank()
              Text($r('app.string.info_about_sub'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ndt7_text_primary'))
            }
            .width('100%')

            Row() {
              Text($r('app.string.info_about_protocol_label'))
                .fontSize(13)
                .fontColor($r('app.color.ndt7_text_secondary'))
              Blank()
              Text($r('app.string.info_about_protocol_value'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ndt7_text_primary'))
            }
            .width('100%')

            Row() {
              Text($r('app.string.info_about_target_label'))
                .fontSize(13)
                .fontColor($r('app.color.ndt7_text_secondary'))
              Blank()
              Text($r('app.string.info_about_target_value'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ndt7_text_primary'))
            }
            .width('100%')
          }
          .width('88%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .backgroundColor($r('app.color.ndt7_card_item_bg'))
          .borderRadius(18)
          .alignItems(HorizontalAlign.Center)

          // ─── Section 2: Platform Info ───
          Column({ space: 8 }) {
            Text($r('app.string.info_about_mlab_title'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.ndt7_text_primary'))
              .textAlign(TextAlign.Center)
              .width('100%')

            Text($r('app.string.info_about_mlab_desc'))
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

          // ─── Section 3: GitHub Source QR Code ───
          Column({ space: 8 }) {
            Text($r('app.string.info_about_source_title'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.ndt7_text_primary'))

            Text($r('app.string.info_about_source_hint'))
              .fontSize(12)
              .fontColor($r('app.color.ndt7_text_secondary'))

            QRCode($r('app.string.info_about_repo'))
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

          // Bottom Spacer
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
