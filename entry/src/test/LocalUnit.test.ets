import { describe, it, expect } from '@ohos/hypium';
import { SpeedTestViewModel } from '../main/ets/viewmodel/SpeedTestViewModel';
import {
  Ndt7AbortError,
  Ndt7Client,
  Ndt7Config,
  Ndt7EventCallbacks,
  Ndt7State,
  Ndt7TestResult
} from 'ndt7-ohos';

class AbortErrorStubClient extends Ndt7Client {
  public async startTest(_config?: Ndt7Config, _callbacks?: Ndt7EventCallbacks): Promise<Ndt7TestResult> {
    throw new Ndt7AbortError('User canceled');
  }

  public getState(): Ndt7State {
    return Ndt7State.CANCELED;
  }
}

class CanceledStateStubClient extends Ndt7Client {
  public async startTest(_config?: Ndt7Config, _callbacks?: Ndt7EventCallbacks): Promise<Ndt7TestResult> {
    throw new Error('Simulated transport failure after cancel');
  }

  public getState(): Ndt7State {
    return Ndt7State.CANCELED;
  }
}

class FailedStubClient extends Ndt7Client {
  public async startTest(_config?: Ndt7Config, _callbacks?: Ndt7EventCallbacks): Promise<Ndt7TestResult> {
    throw new Error('Simulated locate failure');
  }

  public getState(): Ndt7State {
    return Ndt7State.FAILED;
  }
}

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

    it('cancelOnIdleClientIsNoOp', 0, () => {
      const vm = new SpeedTestViewModel();
      vm.cancelSpeedTest();
      expect(vm.state).assertEqual(Ndt7State.IDLE);
      expect(vm.isRunning()).assertFalse();
    });

    it('startTestAbortErrorKeepsCanceledState', 0, async () => {
      const vm = new SpeedTestViewModel(new AbortErrorStubClient());
      await vm.startSpeedTest();
      expect(vm.state).assertEqual(Ndt7State.CANCELED);
      expect(vm.isRunning()).assertFalse();
      expect(vm.statusMessage).assertEqual('Canceled');
    });

    it('startTestErrorWithCanceledClientKeepsCanceledState', 0, async () => {
      const vm = new SpeedTestViewModel(new CanceledStateStubClient());
      await vm.startSpeedTest();
      expect(vm.state).assertEqual(Ndt7State.CANCELED);
      expect(vm.isRunning()).assertFalse();
    });

    it('startTestGenuineFailureSetsFailedState', 0, async () => {
      const vm = new SpeedTestViewModel(new FailedStubClient());
      await vm.startSpeedTest();
      expect(vm.state).assertEqual(Ndt7State.FAILED);
      expect(vm.isRunning()).assertFalse();
      // Without a UI context the friendly error falls back to the hardcoded label
      expect(vm.statusMessage).assertEqual('Test failed. Please try again.');
    });

  });
}