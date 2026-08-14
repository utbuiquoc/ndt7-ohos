import { window } from '@kit.ArkUI';

/**
 * Helper to keep screen awake during active speed tests on HarmonyOS Wearable / Phone / Tablet
 */
export class ScreenAwakeManager {
  private static isAwake: boolean = false;

  public static async setKeepScreenOn(context?: Context, keepOn: boolean = true): Promise<void> {
    if (ScreenAwakeManager.isAwake === keepOn) {
      return;
    }
    if (!context) {
      return;
    }
    try {
      const topWindow = await window.getLastWindow(context);
      if (topWindow) {
        await topWindow.setWindowKeepScreenOn(keepOn);
        ScreenAwakeManager.isAwake = keepOn;
      }
    } catch (_) {
      // Non-fatal if window manager rejected in headless test environments
    }
  }
}
