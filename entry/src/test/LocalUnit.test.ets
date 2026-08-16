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
      expect(vm.statusMessage).assertEqual('Ready');
    });

    it('handlesLogBufferRingCorrectly', 0, () => {
      const vm = new SpeedTestViewModel();
      for (let i = 0; i < 60; i++) {
        vm.addLog(`Test log line ${i}`);
      }
      expect(vm.logs.length <= 50).assertTrue();
    });

    it('terminalStatesAreNotRunning', 0, () => {
      const vm = new SpeedTestViewModel();
      vm.state = Ndt7State.COMPLETED;
      expect(vm.isRunning()).assertFalse();
      vm.state = Ndt7State.CANCELED;
      expect(vm.isRunning()).assertFalse();
      vm.state = Ndt7State.FAILED;
      expect(vm.isRunning()).assertFalse();
    });

    it('activeStatesAreRunning', 0, () => {
      const vm = new SpeedTestViewModel();
      vm.state = Ndt7State.DISCOVERING;
      expect(vm.isRunning()).assertTrue();
      vm.state = Ndt7State.DOWNLOAD_RUNNING;
      expect(vm.isRunning()).assertTrue();
      vm.state = Ndt7State.UPLOAD_RUNNING;
      expect(vm.isRunning()).assertTrue();
    });

    it('addLogDoesNotTriggerUiNotify', 0, () => {
      const vm = new SpeedTestViewModel();
      let notifyCount = 0;
      vm.setOnUpdate(() => {
        notifyCount++;
      });
      vm.addLog('Diagnostic message');
      expect(notifyCount).assertEqual(0);
      expect(vm.logs.length).assertEqual(1);
      expect(vm.logs[0].includes('Diagnostic message')).assertTrue();
    });

    it('cancelSpeedTestTransitionsToCanceled', 0, () => {
      const vm = new SpeedTestViewModel();
      vm.state = Ndt7State.DOWNLOAD_RUNNING;
      expect(vm.isRunning()).assertTrue();
      vm.cancelSpeedTest();
      expect(vm.state).assertEqual(Ndt7State.IDLE);
      expect(vm.isRunning()).assertFalse();
    });

  });
}