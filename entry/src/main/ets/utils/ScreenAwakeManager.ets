import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xA11A;
const TAG = 'ScreenAwakeManager';

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
      if (keepOn) {
        hilog.warn(DOMAIN, TAG, 'Cannot keep screen awake: Context is undefined');
      } else {
        hilog.warn(DOMAIN, TAG, 'Cannot release screen awake: Context is undefined');
      }
      return;
    }

    try {
      const topWindow = await window.getLastWindow(context);
      if (topWindow) {
        await topWindow.setWindowKeepScreenOn(keepOn);
        ScreenAwakeManager.isAwake = keepOn;
        hilog.info(DOMAIN, TAG, 'Window keepScreenOn set to %{public}s', String(keepOn));
      } else {
        hilog.warn(DOMAIN, TAG, 'Failed to acquire top window');
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Window setKeepScreenOn failed: %{public}s', String(err));
    }
  }
}
