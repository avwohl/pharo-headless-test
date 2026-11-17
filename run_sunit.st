"run_sunit.st -- the SUnit sweep runner.  ONE file for our VM and for stock Cog.

 Start it as an eval of the image under test, on either VM:

     <vm> <image> eval FILEIN
 where FILEIN is the expression  '<path>/run_sunit.st' asFileReference fileIn
 in double quotes on the shell command line.

 The script defines no class, installs no method and changes nothing in the
 image under test.  Every test runs in the calling process through
 TestCase>>runCaseManaged, that is inside the SUnit TestExecutionEnvironment
 with its watchdog and its process monitor, and the result of a test is
 classified as TestResult>>runCase: classifies it (TestFailure, TestSkipped,
 Warning and Error handled; Deprecation passed on).  The time limit of a test
 is the limit of SUnit: TestCase>>defaultTimeLimit (10 s) or the limit of the
 test class or of the test (timeLimit:).  A test that runs past its limit gets
 TestTookTooMuchTime from the SUnit watchdog and is written as TIMEOUT.

 Files (all names are <prefix>_<name>; the prefix is the environment variable
 SUNIT_PREFIX, default /tmp/sunit):
   test_classes.txt   input: class names, one per line, run first (optional)
   class_names.txt    input: run only these classes (optional)
   method_names.txt   input: run only these selectors (optional)
   batch.txt          input: '<first> <last>' index range of the class list
   test_results.txt   output: summary, same lines as ever (=== Class ===, RUN:,
                      FAIL:, ERROR:, SKIP:, TIMEOUT:, XFAIL:, Total:, ...)
   test_detail.txt    output: run number, class, selector, result, ms (TAB)
   run_completed.txt  output: marker written at the end
 The class list is: the names of test_classes.txt that exist in the image,
 then every other non-abstract TestCase subclass sorted by name.

 Environment variables (all optional):
   SUNIT_PREFIX         see above
   SUNIT_COUNT_ONLY     write the number of classes to <prefix>_class_count.txt
                        and quit (sunit-sweep.sh asks for TOTAL this way)
   SUNIT_TIMEOUT_MULT   N > 1 sets TestCase defaultTimeLimit: to N * 10 s
                        (the SUnit setting).  OFF by default.  For a slow
                        build (interpreter only, Rosetta).  Classes with a
                        limit of their own keep it.

 Session state that is set up here, the same on both VMs (see
 docs/sunit-runner.md): the Morphic UI manager, the fake-GUI World cycle when
 the image has it, the file pharo.version beside the image, and for the test
 ReleaseTest>>testUnknownProcesses the stop of the fake-GUI cycle loop."

| prefix path readLines classFile classNames testClasses seen addOnce batchStart batchEnd
  batchClasses stream detail totalP totalF totalE totalS totalT totalX totalClasses runNum
  mult |

path := [ :name | prefix , '_' , name ].
readLines := [ :name | | f |
	f := (path value: name) asFileReference.
	f exists
		ifTrue: [ (f readStreamDo: [ :s | s contents ]) lines
			collect: [ :l | l trimBoth ] thenSelect: [ :l | l notEmpty ] ]
		ifFalse: [ nil ] ].

prefix := (OSEnvironment current at: 'SUNIT_PREFIX' ifAbsent: [ nil ])
	ifNil: [ '/tmp/sunit' ]
	ifNotNil: [ :v | v trimBoth isEmpty ifTrue: [ '/tmp/sunit' ] ifFalse: [ v trimBoth ] ].

"The class list."
testClasses := OrderedCollection new.
seen := IdentitySet new.
addOnce := [ :cls | (seen includes: cls) ifFalse: [ seen add: cls. testClasses add: cls ] ].
(readLines value: 'test_classes.txt') ifNotNil: [ :names |
	names do: [ :n |
		(Smalltalk globals at: n asSymbol ifAbsent: [ nil ]) ifNotNil: [ :cls | addOnce value: cls ] ] ].
((TestCase allSubclasses reject: [ :c | [ c isAbstract ] on: Error do: [ :e | true ] ])
	asSortedCollection: [ :a :b | a name <= b name ]) do: [ :cls | addOnce value: cls ].

(OSEnvironment current at: 'SUNIT_COUNT_ONLY' ifAbsent: [ nil ]) ifNotNil: [ :v |
	(path value: 'class_count.txt') asFileReference ensureDelete; writeStreamDo: [ :o | o nextPutAll: testClasses size printString ].
	Smalltalk exitSuccess ].

"Session state, as a resumed interactive image has it."
[ (UIManager default class == MorphicUIManager) ifFalse: [ MorphicUIManager new beDefault ] ] on: Error do: [ :e | ].
[ (Smalltalk globals at: #FakeGUI ifAbsent: [ nil ]) ifNotNil: [ :fg | fg perform: #startCycleLoop ] ] on: Error do: [ :e | ].
"ReleaseTest>>testPharoVersionFileExists reads imageDirectory/pharo.version, which
 every installation has and a bare image file does not."
[ | vf | vf := FileLocator imageDirectory / 'pharo.version'.
  vf exists ifFalse: [ vf writeStreamDo: [ :o | o nextPutAll: (SystemVersion current major * 10) printString ] ] ] on: Error do: [ :e | ].

"Opt-in multiplier of the default time limit (the SUnit setting)."
mult := (OSEnvironment current at: 'SUNIT_TIMEOUT_MULT' ifAbsent: [ nil ])
	ifNil: [ 1 ] ifNotNil: [ :v | v trimBoth asInteger ifNil: [ 1 ] ].
mult > 1 ifTrue: [ TestCase defaultTimeLimit: (10 * mult) seconds ].

"Which classes."
batchStart := 1. batchEnd := testClasses size. batchClasses := nil.
(readLines value: 'class_names.txt') ifNotNil: [ :names | | missing |
	batchClasses := OrderedCollection new. missing := OrderedCollection new.
	names do: [ :n |
		(Smalltalk globals at: n asSymbol ifAbsent: [ nil ])
			ifNil: [ missing add: n ] ifNotNil: [ :cls | batchClasses add: cls ] ].
	batchStart := 1. batchEnd := batchClasses size.
	missing isEmpty ifFalse: [
		(path value: 'unknown_classes.txt') asFileReference ensureDelete; writeStreamDo: [ :o |
			missing do: [ :n | o nextPutAll: n; lf ] ] ] ].
batchClasses ifNil: [
	(readLines value: 'batch.txt') ifNotNil: [ :l | | parts |
		parts := l first substrings.
		batchStart := parts first asInteger.
		batchEnd := parts second asInteger min: testClasses size ].
	batchClasses := testClasses copyFrom: batchStart to: batchEnd ].
classNames := readLines value: 'method_names.txt'.

runNum := [ | f n |
	f := (path value: 'run_number.txt') asFileReference.
	n := [ (f readStreamDo: [ :s | s contents ]) trimBoth asInteger ] on: Error do: [ :e | nil ].
	n := (n ifNil: [ 0 ]) + 1.
	f ensureDelete; writeStreamDo: [ :o | o nextPutAll: n printString ].
	n ] value.

(path value: 'test_results.txt') asFileReference ensureDelete.
stream := (path value: 'test_results.txt') asFileReference writeStream.
(path value: 'test_detail.txt') asFileReference ensureDelete.
detail := (path value: 'test_detail.txt') asFileReference writeStream.
totalP := 0. totalF := 0. totalE := 0. totalS := 0. totalT := 0. totalX := 0.
totalClasses := 0.

stream nextPutAll: '=== SUnit Test Run #'; print: runNum;
	nextPutAll: ' (batch '; print: batchStart; nextPutAll: '-'; print: batchEnd;
	nextPutAll: ' of '; print: testClasses size; nextPutAll: ') ==='; lf; lf.
stream nextPutAll: 'Image: '; nextPutAll: Smalltalk imageFile fullName; lf.
stream nextPutAll: 'VM: '; nextPutAll: ([ Smalltalk vm version ] on: Error do: [ :e | '?' ]); lf.
stream nextPutAll: 'Default time limit: '; print: TestCase defaultTimeLimit; lf.
stream nextPutAll: 'Process priority: '; print: Processor activeProcess priority; lf.
stream nextPutAll: 'Started: '; nextPutAll: DateAndTime now printString; lf; lf.
stream flush.

batchClasses do: [ :klass |
	| tests cp cf ce cs ct cx abstract |
	cp := 0. cf := 0. ce := 0. cs := 0. ct := 0. cx := 0.
	abstract := [ klass isAbstract ] on: Error do: [ :ex | false ].
	stream nextPutAll: '=== '; nextPutAll: klass name; nextPutAll: ' ==='.
	abstract ifTrue: [ stream nextPutAll: ' SKIPPED (abstract)' ].
	stream lf.
	"The tests of SUnit itself: buildSuite tests.  A ParametrizedTestCase class
	 gives one test per selector and per parameter set; the test carries its
	 parameters.  The name of a test is nameForReport (the selector, and the
	 parameters of a parametrized test) without white space."
	tests := abstract
		ifTrue: [ #() ]
		ifFalse: [ [ klass buildSuite tests asArray ] on: Error do: [ :ex |
			stream nextPutAll: '  ERROR: buildSuite ('; nextPutAll: ex class name; nextPutAll: ': ';
				nextPutAll: (ex messageText ifNil: [ '' ]); nextPutAll: ')'; lf.
			ce := ce + 1.
			#() ] ].
	tests := tests asSortedCollection: [ :a :b | a nameForReport asString <= b nameForReport asString ].
	classNames ifNotNil: [ :wanted | tests := tests select: [ :t | wanted includes: t selector asString ] ].
	tests do: [ :test |
		| sel result result2 expected text trace t0 ms |
		sel := (test nameForReport asString collect: [ :c | c isSeparator ifTrue: [ $_ ] ifFalse: [ c ] ]) asString.
		"A test marked as an expected failure runs.  It fails or errors: XFAIL.
		 It passes: an unexpected pass, which SUnit reports as a failure."
		expected := [ test shouldPass not ] on: Error do: [ :ex | false ].
		stream nextPutAll: '  RUN: '; nextPutAll: sel.
		expected ifTrue: [ stream nextPutAll: ' (expectedFailure)' ].
		stream lf; flush.
		text := nil. trace := nil.
		result := TestResult new.
		t0 := Time millisecondClockValue.
		"The same handlers as TestResult>>runCase:, with the message kept."
		[ [ [ test announce: TestCaseStarted withResult: result.
			(klass name = 'ReleaseTest' and: [ test selector == #testUnknownProcesses ])
				ifTrue: [
					"This test lists every process of the image: no helper process
					 of the harness may live.  Only the fake-GUI cycle loop is one."
					| cycle |
					cycle := Smalltalk globals at: #FakeGUICycleLoop ifAbsent: [ nil ].
					cycle ifNotNil: [ :p | [ p terminate ] on: Error do: [ :e | ] ].
					[ test runCaseManaged ] ensure: [
						cycle ifNotNil: [ :p |
							(Smalltalk globals at: #FakeGUI ifAbsent: [ nil ]) ifNotNil: [ :fg |
								[ fg perform: #startCycleLoop ] on: Error do: [ :e | ] ] ] ] ]
				ifFalse: [ test runCaseManaged ].
			result addPass: test ]
			on: TestFailure , TestSkipped , Warning , Error
			do: [ :ex |
				text := ex class name , ': ' , (ex messageText ifNil: [ '' ]).
				trace := [ | ctx n lines |
					ctx := ex signalerContext. n := 0. lines := OrderedCollection new.
					[ ctx notNil and: [ n < 25 ] ] whileTrue: [
						lines add: ctx printString. ctx := ctx sender. n := n + 1 ].
					lines ] on: Error do: [ :e2 | #() ].
				ex sunitAnnounce: test toResult: result ] ]
			on: Deprecation do: [ :ex | ex pass ] ]
			ensure: [
				test announce: TestCaseEnded withResult: result.
				[ test classForTestResource resetResources: test resources ] on: Error do: [ :e | ] ].
		ms := Time millisecondClockValue - t0.
		"Classify like TestResult."
		result2 := nil.
		"the stored collections: result errors etc. leave the expected defects out"
		((result instVarNamed: 'skipped') includes: test) ifTrue: [ result2 := #skip ].
		((result instVarNamed: 'errors') includes: test) ifTrue: [ result2 := #error ].
		((result instVarNamed: 'failures') includes: test) ifTrue: [ result2 := #fail ].
		(result2 notNil and: [ text beginsWith: 'TestTookTooMuchTime' ]) ifTrue: [ result2 := #timeout ].
		result2 ifNil: [
			result2 := ((result instVarNamed: 'passed') includes: test) ifTrue: [ #pass ] ifFalse: [ #error ].
			text ifNil: [ text := 'the test left no result' ] ].
		(expected and: [ result2 = #pass ]) ifTrue: [
			result2 := #fail.
			text := 'unexpected pass: the test is marked as an expected failure and it passes' ].
		(expected and: [ #(fail error timeout) includes: result2 ]) ifTrue: [
			(text beginsWith: 'unexpected pass') ifFalse: [ result2 := #xfail ] ].
		result2 = #pass ifTrue: [ cp := cp + 1 ].
		result2 = #xfail ifTrue: [
			cx := cx + 1.
			stream nextPutAll: '  XFAIL: '; nextPutAll: sel;
				nextPutAll: ' ['; nextPutAll: (text copyFrom: 1 to: (text size min: 500)); nextPutAll: ']'; lf ].
		result2 = #fail ifTrue: [
			cf := cf + 1.
			stream nextPutAll: '  FAIL: '; nextPutAll: sel;
				nextPutAll: ' ['; nextPutAll: (text copyFrom: 1 to: (text size min: 500)); nextPutAll: ']'; lf ].
		result2 = #error ifTrue: [
			ce := ce + 1.
			stream nextPutAll: '  ERROR: '; nextPutAll: sel;
				nextPutAll: ' ('; nextPutAll: (text copyFrom: 1 to: (text size min: 500)); nextPutAll: ')'; lf.
			(trace ifNil: [ #() ]) do: [ :l | stream nextPutAll: '    >> '; nextPutAll: l; lf ] ].
		result2 = #skip ifTrue: [
			cs := cs + 1.
			stream nextPutAll: '  SKIP: '; nextPutAll: sel;
				nextPutAll: ' ('; nextPutAll: ((text ifNil: [ '' ]) copyFrom: 1 to: ((text ifNil: [ '' ]) size min: 200)); nextPutAll: ')'; lf ].
		result2 = #timeout ifTrue: [
			ct := ct + 1.
			stream nextPutAll: '  TIMEOUT: '; nextPutAll: sel;
				nextPutAll: ' ('; nextPutAll: (text copyFrom: 1 to: (text size min: 300));
				nextPutAll: ') '; print: ms; nextPutAll: 'ms'; lf ].
		detail nextPutAll: runNum printString; tab; nextPutAll: klass name; tab; nextPutAll: sel; tab;
			nextPutAll: result2 asString asUppercase; tab; print: ms; lf.
		stream flush. detail flush ].
	stream nextPutAll: 'Total: '; print: cp + cf + ce + cs + ct + cx;
		nextPutAll: ' P:'; print: cp; nextPutAll: ' F:'; print: cf;
		nextPutAll: ' E:'; print: ce; nextPutAll: ' S:'; print: cs.
	ct > 0 ifTrue: [ stream nextPutAll: ' T:'; print: ct ].
	cx > 0 ifTrue: [ stream nextPutAll: ' X:'; print: cx ].
	stream lf; lf; flush.
	totalP := totalP + cp. totalF := totalF + cf. totalE := totalE + ce.
	totalS := totalS + cs. totalT := totalT + ct. totalX := totalX + cx.
	totalClasses := totalClasses + 1 ].

stream lf; nextPutAll: '*** BATCH COMPLETED for '; print: batchClasses size;
	nextPutAll: ' classes ('; print: batchStart; nextPutAll: '-'; print: batchEnd; nextPutAll: ')'; lf; lf.
stream nextPutAll: '=== BATCH TOTAL ==='; lf.
stream nextPutAll: 'Run: #'; print: runNum; lf.
stream nextPutAll: 'Classes: '; print: totalClasses; lf.
stream nextPutAll: 'Pass: '; print: totalP; lf.
stream nextPutAll: 'Fail: '; print: totalF; lf.
stream nextPutAll: 'Error: '; print: totalE; lf.
stream nextPutAll: 'Skip: '; print: totalS; lf.
totalT > 0 ifTrue: [ stream nextPutAll: 'Timeout: '; print: totalT; lf ].
totalX > 0 ifTrue: [ stream nextPutAll: 'ExpectedFailure: '; print: totalX; lf ].
stream nextPutAll: 'Total: '; print: totalP + totalF + totalE + totalS + totalT + totalX; lf.
stream nextPutAll: 'Finished: '; nextPutAll: DateAndTime now printString; lf; lf.
stream nextPutAll: '=== BATCH COMPLETE ==='; lf.
stream close. detail close.

(path value: 'run_completed.txt') asFileReference writeStreamDo: [ :ws |
	ws nextPutAll: 'Run #'; nextPutAll: runNum printString; nextPutAll: ' completed at '; nextPutAll: DateAndTime now printString ].

Smalltalk exitSuccess
