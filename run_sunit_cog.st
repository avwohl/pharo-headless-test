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
 <prefix>_test_classes.txt first, then invoke stock Pharo with
 `eval ''...run_sunit_cog.st...'' asFileReference fileIn` (without
 --save — this script writes results and calls exitSuccess itself).

 PATH PREFIX (2026-09-02).  Every path below comes from the SUNIT_PREFIX
 environment variable, defaulting to the historical '/tmp/sunit'.  The two
 runners used to share these fixed paths with no namespacing, so a Cog run
 started while a custom-VM sweep was in flight silently corrupted it — the
 results file is append-shared and /tmp/sunit_run_completed.txt makes the
 next batch skip itself entirely.  Set SUNIT_PREFIX=/tmp/cogsunit (say) and
 the two can run side by side."

| prefix classFile classNames stream detail totalP totalF totalE totalS totalT totalX totalClasses perTestTimeout |
"Same session state as run_sunit_tests.st (SUnitRunner class>>startUp:), so
 the two VMs run the tests in the same conditions: the Morphic UI manager and
 the fake-GUI World cycle when the image has them, and the pharo.version file
 that ReleaseTest>>testPharoVersionFileExists reads."
[ (UIManager default class == MorphicUIManager) ifFalse: [ MorphicUIManager new beDefault ] ] on: Error do: [ :e | ].
[ (Smalltalk globals at: #FakeGUI ifAbsent: [ nil ]) ifNotNil: [ :fg | fg perform: #startCycleLoop ] ] on: Error do: [ :e | ].
[ | vf | vf := FileLocator imageDirectory / 'pharo.version'.
  vf exists ifFalse: [ vf writeStreamDo: [ :o | o nextPutAll: (SystemVersion current major * 10) printString ] ] ] on: Error do: [ :e | ].
prefix := (Smalltalk os environment at: 'SUNIT_PREFIX' ifAbsent: [ nil ])
  ifNil: [ '/tmp/sunit' ]
  ifNotNil: [ :v | v trimBoth isEmpty ifTrue: [ '/tmp/sunit' ] ifFalse: [ v trimBoth ] ].
classFile := (prefix , '_test_classes.txt') asFileReference.
classNames := (classFile contents lines collect: [:s | s trimBoth])
  reject: [:s | s isEmpty].

stream := (prefix , '_test_results.txt') asFileReference writeStream.
detail := (prefix , '_test_detail.txt') asFileReference writeStream.
totalP := 0. totalF := 0. totalE := 0. totalS := 0. totalT := 0. totalX := 0.
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
  ([ klass isAbstract ] on: Error do: [ :ex | false ]) ifTrue: [
    "run_sunit_tests.st does not run an abstract class; do the same."
    stream nextPutAll: '=== '; nextPutAll: className; nextPutAll: ' === SKIPPED (abstract)'; nextPut: Character lf.
    stream flush
  ] ifFalse: [
    | selectors cp cf ce cs ct cx |
    cp := 0. cf := 0. ce := 0. cs := 0. ct := 0. cx := 0.
    selectors := klass allTestSelectors.
    stream nextPutAll: '=== '; nextPutAll: className; nextPutAll: ' ==='; nextPut: Character lf.
    selectors do: [:sel |
      | instance result failText errText skipText expected |
      instance := klass selector: sel.
      "A test that is marked as an expected failure runs.  It fails or errors:
       XFAIL.  It passes: an unexpected pass, which SUnit reports as a failure."
      expected := ([ (klass lookupSelector: sel) pragmas anySatisfy: [ :pr | pr selector = #expectedFailure ] ]
        on: Error do: [ :ex | false ])
          or: [ [ instance shouldPass not ] on: Error do: [ :ex | false ] ].
      stream nextPutAll: '  RUN: '; nextPutAll: sel.
      expected ifTrue: [ stream nextPutAll: ' (expectedFailure)' ].
      stream nextPut: Character lf.
      stream flush.
      result := nil. failText := nil. errText := nil. skipText := nil.
      [[[
        "runCaseManaged, not runCase: the test runs inside a
         TestExecutionEnvironment, as it does under TestCase>>run.  With a bare
         runCase, ProcessTest and SUnitTest gave 50 errors that were not defects
         (DefaultExecutionEnvironment does not understand processMonitor)."
        result := (className = 'ReleaseTest' and: [ sel = #testUnknownProcesses ])
          ifTrue: [
            "This test lists every process of the image.  Run it with no
             helper process of the harness alive: no fake-GUI cycle loop and
             no valueWithin: watchdog (run_sunit_tests.st does the same in
             SUnitRunner class>>withoutHelperProcessesDo:)."
            | cycle |
            cycle := Smalltalk globals at: #FakeGUICycleLoop ifAbsent: [ nil ].
            cycle ifNotNil: [ :p | [ p terminate ] on: Error do: [ :e | ] ].
            [ instance runCaseManaged. #pass ] ensure: [
              cycle ifNotNil: [ :p |
                (Smalltalk globals at: #FakeGUI ifAbsent: [ nil ]) ifNotNil: [ :fg |
                  [ fg perform: #startCycleLoop ] on: Error do: [ :e | ] ] ] ] ]
          ifFalse: [
            [instance runCaseManaged. #pass]
              valueWithin: perTestTimeout onTimeout: [#timeout] ]]
          on: TestFailure do: [:ex |
            failText := ex messageText ifNil: [''].
            result := #fail]]
          on: TestSkipped do: [:ex |
            skipText := ex messageText ifNil: [''].
            result := #skip]]
          on: Error do: [:ex |
            errText := ex class name , ': ' , (ex messageText ifNil: ['']).
            result := #error].
      (expected and: [ result = #pass ]) ifTrue: [
        result := #fail.
        failText := 'unexpected pass: the test is marked as an expected failure and it passes' ].
      (expected and: [ result = #fail and: [ (failText beginsWith: 'unexpected pass') not ] ]) ifTrue: [
        result := #xfail.
        stream nextPutAll: '  XFAIL: '; nextPutAll: sel;
          nextPutAll: ' ['; nextPutAll: (failText copyFrom: 1 to: (failText size min: 500));
          nextPutAll: ']'; nextPut: Character lf ].
      (expected and: [ result = #error ]) ifTrue: [
        result := #xfail.
        stream nextPutAll: '  XFAIL: '; nextPutAll: sel;
          nextPutAll: ' ('; nextPutAll: (errText copyFrom: 1 to: (errText size min: 500));
          nextPutAll: ')'; nextPut: Character lf ].
      result = #xfail ifTrue: [cx := cx + 1].
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
    stream nextPutAll: 'Total: '; print: cp + cf + ce + cs + ct + cx;
      nextPutAll: ' P:'; print: cp;
      nextPutAll: ' F:'; print: cf;
      nextPutAll: ' E:'; print: ce;
      nextPutAll: ' S:'; print: cs.
    ct > 0 ifTrue: [stream nextPutAll: ' T:'; print: ct].
    cx > 0 ifTrue: [stream nextPutAll: ' X:'; print: cx].
    stream nextPut: Character lf.
    stream nextPut: Character lf.
    stream flush.
    totalP := totalP + cp. totalF := totalF + cf. totalE := totalE + ce.
    totalS := totalS + cs. totalT := totalT + ct. totalX := totalX + cx.
    totalClasses := totalClasses + 1]]].

stream nextPut: Character lf.
stream nextPutAll: '=== BATCH TOTAL ==='; nextPut: Character lf.
stream nextPutAll: 'Classes: '; print: totalClasses; nextPut: Character lf.
stream nextPutAll: 'Pass: '; print: totalP; nextPut: Character lf.
stream nextPutAll: 'Fail: '; print: totalF; nextPut: Character lf.
stream nextPutAll: 'Error: '; print: totalE; nextPut: Character lf.
stream nextPutAll: 'Skip: '; print: totalS; nextPut: Character lf.
totalT > 0 ifTrue: [stream nextPutAll: 'Timeout: '; print: totalT; nextPut: Character lf].
totalX > 0 ifTrue: [stream nextPutAll: 'ExpectedFailure: '; print: totalX; nextPut: Character lf].
stream nextPutAll: 'Total: '; print: totalP + totalF + totalE + totalS + totalT + totalX; nextPut: Character lf.
stream nextPutAll: 'Finished: '; nextPutAll: DateAndTime now printString; nextPut: Character lf.
stream nextPut: Character lf.
stream nextPutAll: '=== BATCH COMPLETE ==='; nextPut: Character lf.
stream close. detail close.

(prefix , '_run_completed.txt') asFileReference writeStreamDo: [:ws |
  ws nextPutAll: 'Stock Cog run completed at '; nextPutAll: DateAndTime now printString].

Smalltalk exitSuccess
