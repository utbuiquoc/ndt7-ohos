import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xA11A;
const TAG = 'ConsentPrefs';
const PREFS_NAME = 'ndt7_settings';
const KEY_DATA_POLICY = 'ndt7_data_policy_accepted';

/**
 * Persistence manager for NDT7 Data Policy consent state
 */
export class ConsentPreferencesManager {
  private static instance?: ConsentPreferencesManager;
  private prefStore?: preferences.Preferences;

  public static getInstance(): ConsentPreferencesManager {
    if (!ConsentPreferencesManager.instance) {
      ConsentPreferencesManager.instance = new ConsentPreferencesManager();
    }
    return ConsentPreferencesManager.instance;
  }

  private async getStore(context: Context): Promise<preferences.Preferences> {
    if (!this.prefStore) {
      try {
        this.prefStore = await preferences.getPreferences(context, PREFS_NAME);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'Failed to get preferences store: %{public}s', String(err));
        throw new Error(`Preferences store unavailable: ${String(err)}`);
      }
    }
    return this.prefStore;
  }

  public async isPolicyAccepted(context: Context): Promise<boolean> {
    try {
      const store = await this.getStore(context);
      const val = await store.get(KEY_DATA_POLICY, false);
      return val === true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to read policy consent preference: %{public}s', String(err));
      return false;
    }
  }

  public async setPolicyAccepted(context: Context, accepted: boolean): Promise<void> {
    // Let write failures propagate: callers must not treat consent as saved when it is not.
    const store = await this.getStore(context);
    try {
      await store.put(KEY_DATA_POLICY, accepted);
      await store.flush();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to save policy consent preference: %{public}s', String(err));
      throw new Error(`Failed to persist consent: ${String(err)}`);
    }
  }
}

