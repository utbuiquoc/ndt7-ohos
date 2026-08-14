import { describe, it, expect } from '@ohos/hypium';
import { SpeedTestViewModel } from '../main/ets/viewmodel/SpeedTestViewModel';
import { Ndt7State } from '@mlab/ndt7-ohos';

export default function localUnitTest() {
  describe('WearableViewModelTests', () => {

    it('initializesWithIdleState', 0, () => {
      const vm = new SpeedTestViewModel();
      expect(vm.state).assertEqual(Ndt7State.IDLE);
      expect(vm.isRunning()).assertFalse();
      expect(vm.downloadMbps).assertEqual(0);
      expect(vm.uploadMbps).assertEqual(0);
    });

    it('handlesLogBufferRingCorrectly', 0, () => {
      const vm = new SpeedTestViewModel();
      for (let i = 0; i < 60; i++) {
        vm.addLog(`Test log line ${i}`);
      }
      expect(vm.logs.length <= 50).assertTrue();
    });

  });
}
