"Minimal SUnit runner for stock Cog.  Reads /tmp/sunit_test_classes.txt
 (one class name per line — the same file the custom-VM harness
 consumes), runs each test, writes /tmp/sunit_test_results.txt in the
 same format as run_sunit_tests.st.

 Why a separate runner for Cog?  run_sunit_tests.st's runAllTests is
 elaborate — fork-based per-test watchdogs, Delay scheduler
 instrumentation, TestExecutionEnvironment wrapping — all of which is
 needed to work around our custom VM's failure modes (scheduler death
 under JIT, stuck FFI callbacks, etc.).  On stock Cog that machinery
 interacts badly: every test hits the outer hard-wait timeout
 (TIMEOUT(prim-stuck)) instead of completing normally.  This script is
 a simple valueWithin:onTimeout: loop that Cog handles fine.

 Fairness vs the custom-VM harness: both harnesses read the same
 external class list, so neither harness method's literal pool
 contains test-class symbols — ClassQueryTest>>testAllCallsOn counts
 the same senders on both VMs.

 Caller: stage scripts/pharo-headless-test/test_classes.txt to
 /tmp/sunit_test_classes.txt first, then invoke stock Pharo with
 `eval ''...run_sunit_cog.st...'' asFileReference fileIn` (without
 --save — this script writes results and calls exitSuccess itself)."

| classFile classNames stream detail totalP totalF totalE totalS totalT totalClasses perTestTimeout |
classFile := '/tmp/sunit_test_classes.txt' asFileReference.
classNames := (classFile contents lines collect: [:s | s trimBoth])
  reject: [:s | s isEmpty].

stream := '/tmp/sunit_test_results.txt' asFileReference writeStream.
detail := '/tmp/sunit_test_detail.txt' asFileReference writeStream.
totalP := 0. totalF := 0. totalE := 0. totalS := 0. totalT := 0.
totalClasses := 0.
perTestTimeout := 50 seconds.

stream nextPutAll: '=== Stock Cog SUnit run ==='; nextPut: Character lf.
stream nextPutAll: 'Classes to run: '; print: classNames size; nextPut: Character lf.
stream nextPutAll: 'Per-test timeout: '; print: perTestTimeout; nextPut: Character lf.
stream nextPutAll: 'Image: '; nextPutAll: Smalltalk imageFile fullName; nextPut: Character lf.
stream nextPutAll: 'Started: '; nextPutAll: DateAndTime now printString; nextPut: Character lf.
stream nextPut: Character lf.
stream flush.

classNames do: [:className |
  | klass |
  klass := Smalltalk globals at: className asSymbol ifAbsent: [nil].
  klass isNil ifTrue: [
    stream nextPutAll: '=== '; nextPutAll: className; nextPutAll: ' ==='; nextPut: Character lf.
    stream nextPutAll: '  MISSING (class not in image)'; nextPut: Character lf.
    stream nextPutAll: 'Total: 0 P:0 F:0 E:0 S:0'; nextPut: Character lf.
    stream nextPut: Character lf.
    stream flush
  ] ifFalse: [
    | selectors cp cf ce cs ct |
    cp := 0. cf := 0. ce := 0. cs := 0. ct := 0.
    selectors := klass allTestSelectors.
    stream nextPutAll: '=== '; nextPutAll: className; nextPutAll: ' ==='; nextPut: Character lf.
    selectors do: [:sel |
      | instance result failText errText skipText |
      instance := klass selector: sel.
      stream nextPutAll: '  RUN: '; nextPutAll: sel; nextPut: Character lf.
      stream flush.
      result := nil. failText := nil. errText := nil. skipText := nil.
      [[[
        result := [instance runCase. #pass]
          valueWithin: perTestTimeout onTimeout: [#timeout]]
          on: TestFailure do: [:ex |
            failText := ex messageText ifNil: [''].
            result := #fail]]
          on: TestSkipped do: [:ex |
            skipText := ex messageText ifNil: [''].
            result := #skip]]
          on: Error do: [:ex |
            errText := ex class name , ': ' , (ex messageText ifNil: ['']).
            result := #error].
      result = #pass ifTrue: [cp := cp + 1].
      result = #fail ifTrue: [
        cf := cf + 1.
        stream nextPutAll: '  FAIL: '; nextPutAll: sel;
          nextPutAll: ' ['; nextPutAll: (failText copyFrom: 1 to: (failText size min: 500));
          nextPutAll: ']'; nextPut: Character lf].
      result = #error ifTrue: [
        ce := ce + 1.
        stream nextPutAll: '  ERROR: '; nextPutAll: sel;
          nextPutAll: ' ('; nextPutAll: (errText copyFrom: 1 to: (errText size min: 500));
          nextPutAll: ')'; nextPut: Character lf].
      result = #skip ifTrue: [
        cs := cs + 1.
        stream nextPutAll: '  SKIP: '; nextPutAll: sel;
          nextPutAll: ' ('; nextPutAll: (skipText copyFrom: 1 to: (skipText size min: 200));
          nextPutAll: ')'; nextPut: Character lf].
      result = #timeout ifTrue: [
        ct := ct + 1.
        stream nextPutAll: '  TIMEOUT: '; nextPutAll: sel;
          nextPutAll: ' (exceeded '; print: perTestTimeout asSeconds;
          nextPutAll: 's)'; nextPut: Character lf].
      stream flush].
    stream nextPutAll: 'Total: '; print: cp + cf + ce + cs + ct;
      nextPutAll: ' P:'; print: cp;
      nextPutAll: ' F:'; print: cf;
      nextPutAll: ' E:'; print: ce;
      nextPutAll: ' S:'; print: cs.
    ct > 0 ifTrue: [stream nextPutAll: ' T:'; print: ct].
    stream nextPut: Character lf.
    stream nextPut: Character lf.
    stream flush.
    totalP := totalP + cp. totalF := totalF + cf. totalE := totalE + ce.
    totalS := totalS + cs. totalT := totalT + ct.
    totalClasses := totalClasses + 1]].

stream nextPut: Character lf.
stream nextPutAll: '=== BATCH TOTAL ==='; nextPut: Character lf.
stream nextPutAll: 'Classes: '; print: totalClasses; nextPut: Character lf.
stream nextPutAll: 'Pass: '; print: totalP; nextPut: Character lf.
stream nextPutAll: 'Fail: '; print: totalF; nextPut: Character lf.
stream nextPutAll: 'Error: '; print: totalE; nextPut: Character lf.
stream nextPutAll: 'Skip: '; print: totalS; nextPut: Character lf.
totalT > 0 ifTrue: [stream nextPutAll: 'Timeout: '; print: totalT; nextPut: Character lf].
stream nextPutAll: 'Total: '; print: totalP + totalF + totalE + totalS + totalT; nextPut: Character lf.
stream nextPutAll: 'Finished: '; nextPutAll: DateAndTime now printString; nextPut: Character lf.
stream nextPut: Character lf.
stream nextPutAll: '=== BATCH COMPLETE ==='; nextPut: Character lf.
stream close. detail close.

'/tmp/sunit_run_completed.txt' asFileReference writeStreamDo: [:ws |
  ws nextPutAll: 'Stock Cog run completed at '; nextPutAll: DateAndTime now printString].

Smalltalk exitSuccess
