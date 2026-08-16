import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ScreenAwakeManager } from '../utils/ScreenAwakeManager';

const DOMAIN = 0xA11A;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to set dark mode: %{public}s', String(err));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/MainPage', (error) => {
      if (error && error.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load MainPage: code=%{public}d, message=%{public}s', error.code, error.message || '');
      }
    });
  }

  onWindowStageDestroy(): void {
    ScreenAwakeManager.reset();
  }

  onDestroy(): void {
    ScreenAwakeManager.reset();
  }
}
