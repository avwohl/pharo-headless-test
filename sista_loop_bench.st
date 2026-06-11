"sista_loop_bench.st — self-contained known-output benchmark for the Sista
 counted-loop fusions.  Runs each collection idiom in a hot outer loop (forces
 tier-2 / OSR so the fusion compiles), checks the result against a
 mathematically-known answer, writes /tmp/sista_bench.txt, then QUITS.

 Unlike the SUnit runner it never enters the scheduler idle loop, so it
 finishes in seconds under the box-safe harness.  Enable the fusions at launch
 with PHARO_SISTA_DISPATCH=1; disable just the counted-loop lowering with
 PHARO_SISTA_NO_LOWER_COUNTED_LOOP=1 for an A/B (fusion vs tier-1) check."

Object subclass: #SistaBench
  instanceVariableNames: ''
  classVariableNames: ''
  package: 'SistaBench'!

SistaBench class compile: 'check: label expected: exp got: got on: aStream
  | ok |
  ok := exp = got.
  aStream nextPutAll: label; nextPutAll: '' expected=''; print: exp;
    nextPutAll: '' got=''; print: got;
    nextPutAll: (ok ifTrue: ['' PASS''] ifFalse: ['' FAIL'']);
    nextPut: Character lf.
  ^ ok' classified: 'bench'!

"Dedicated helper methods — each is a small canonical-shape method so that when
 it gets hot and tier-2 compiles, the IR builder recognizes exactly one
 counted-loop fusion.  Mirrors why inject:into: (a real library method) fuses."
SistaBench class compile: 'doSumArray: arr
  | t | t := 0. arr do: [:e | t := t + e]. ^ t' classified: 'helpers'!
SistaBench class compile: 'injectSumArray: arr
  ^ arr inject: 0 into: [:a :e | a + e]' classified: 'helpers'!
SistaBench class compile: 'collectSqArray: arr
  ^ arr collect: [:e | e * e]' classified: 'helpers'!
SistaBench class compile: 'selectEvenArray: arr
  ^ arr select: [:e | e even]' classified: 'helpers'!
SistaBench class compile: 'selectGtArray: arr
  ^ arr select: [:e | e > 5]' classified: 'helpers'!
SistaBench class compile: 'doSumInterval: n
  | t | t := 0. (1 to: n) do: [:e | t := t + e]. ^ t' classified: 'helpers'!
SistaBench class compile: 'intervalDoNop: n
  | t | t := 0. (1 to: n) do: [:e | e * e]. (1 to: n) do: [:e | t := t + e]. ^ t' classified: 'helpers'!
SistaBench class compile: 'timesRepeatSum
  | s | s := 0. 1000 timesRepeat: [s := s + 1]. ^ s' classified: 'helpers'!
"WhileTrueAccum SERIES shape: `1 to: LITERAL do: [:i | s := s + i]` inlines to a
 counter loop whose body adds the loop variable → folds to s + limit*(limit+1)/2.
 (Literal bound so the recognizer fires; `1 to: n do:` with a var bound would not.)"
SistaBench class compile: 'seriesSum
  | s | s := 0. 1 to: 100 do: [:i | s := s + i]. ^ s' classified: 'helpers'!
"Larger literal-bound series — still folds (limit 100000 < 2^30, sum
 5000050000 < SmI max) so verifies the closed-form path on a big bound."
SistaBench class compile: 'bigSeriesSum
  | s | s := 0. 1 to: 100000 do: [:i | s := s + i]. ^ s' classified: 'helpers'!
"Overflowing series — STORM TRIGGER.  Accum starts at SmI max so s + 5050
 overflows SmI range; the fold''s runtime SmI-range check fails and DEOPTs
 EVERY call.  Verifies (a) correctness (interpreter computes the LargeInteger
 after deopt) and (b) the deopt-storm self-heals via the bail/blacklist guard
 (g_sistaDeopt_whileTrueAccum stays bounded, not == reps)."
SistaBench class compile: 'overflowSeries
  | s | s := 1152921504606846975. 1 to: 100 do: [:i | s := s + i]. ^ s' classified: 'helpers'!
"Literal-bound to:do: with a NON-foldable body (array access, not canonical
 accum arith).  bodyOk must reject it → the to:do: recognizer must NOT fuse →
 correct sum via normal interp.  Precision guard for enable-by-default."
SistaBench class compile: 'todoNonFold: arr
  | t | t := 0. 1 to: 10 do: [:i | t := t + (arr at: i)]. ^ t' classified: 'helpers'!
SistaBench class compile: 'injectSumInterval: n
  ^ (1 to: n) inject: 0 into: [:a :e | a + e]' classified: 'helpers'!
"Negative lower bound — regression guard for the signed-compare fix (a buggy
 unsigned compare runs 0 iterations → 0, not the correct sum)."
SistaBench class compile: 'negSum: lo to: hi
  | t | t := 0. (lo to: hi) do: [:e | t := t + e]. ^ t' classified: 'helpers'!
SistaBench class compile: 'negInject: lo to: hi
  ^ (lo to: hi) inject: 0 into: [:a :e | a + e]' classified: 'helpers'!
SistaBench class compile: 'negIntervalDo: lo to: hi
  | t | t := 0. (lo to: hi) do: [:e | e * e]. (lo to: hi) do: [:e | t := t + e]. ^ t' classified: 'helpers'!
"Non-local return inside a do: block — regression guard for the NLR-bail fix
 (a buggy fusion drops the ^ and falls through to ^0)."
SistaBench class compile: 'nlrFirst: n
  (1 to: n) do: [:e | ^ e]. ^ 0' classified: 'helpers'!
"Deopt-resume guards (B fix): a LargeInteger (> SmI range) interval BOUND forces
 the entry tag-check to deopt.  If the deopt wrongly resumes at PushFullBlock
 (the elided to: send) it sends do:/inject: to a SmallInt → DNU/crash.  A correct
 resume re-runs the to: send → real Interval → real (4-element) loop.  Top-level
 so the fusion forms; small range so the post-deopt interp loop is fast.  Note:
 must NOT be wrapped in on:Error do: — that nests the do: in a block and the
 fusion never forms (no deopt exercised)."
SistaBench class compile: 'intvDoDeopt
  (4611686018427387904 to: 4611686018427387907) do: [:e | e * e]. ^ 42' classified: 'helpers'!
SistaBench class compile: 'intvInjectDeopt
  ^ (4611686018427387904 to: 4611686018427387907) inject: 0 into: [:a :e | a + e]' classified: 'helpers'!

SistaBench class compile: 'runBench
  | arr s r reps |
  reps := 400000.
  s := WriteStream on: String new.
  arr := #(1 2 3 4 5 6 7 8 9 10).
  r := 0. 1 to: reps do: [:k | r := self injectSumArray: arr].
  self check: ''inject_array'' expected: 55 got: r on: s.
  r := 0. 1 to: reps do: [:k | r := self doSumArray: arr].
  self check: ''do_array'' expected: 55 got: r on: s.
  r := nil. 1 to: reps do: [:k | r := self collectSqArray: arr].
  self check: ''collect_array'' expected: #(1 4 9 16 25 36 49 64 81 100) got: r on: s.
  r := nil. 1 to: reps do: [:k | r := self selectEvenArray: arr].
  self check: ''select_array'' expected: #(2 4 6 8 10) got: r on: s.
  r := nil. 1 to: reps do: [:k | r := self selectGtArray: arr].
  self check: ''select_gt'' expected: #(6 7 8 9 10) got: r on: s.
  r := 0. 1 to: reps do: [:k | r := self injectSumInterval: 100].
  self check: ''inject_interval'' expected: 5050 got: r on: s.
  r := 0. 1 to: reps do: [:k | r := self doSumInterval: 100].
  self check: ''do_interval'' expected: 5050 got: r on: s.
  r := 0. 1 to: reps do: [:k | r := self timesRepeatSum].
  self check: ''timesrepeat'' expected: 1000 got: r on: s.
  r := 0. 1 to: reps do: [:k | r := self seriesSum].
  self check: ''series_sum'' expected: 5050 got: r on: s.
  r := 0. 1 to: reps do: [:k | r := self bigSeriesSum].
  self check: ''big_series'' expected: 5000050000 got: r on: s.
  r := 0. 1 to: reps do: [:k | r := self todoNonFold: arr].
  self check: ''todo_nonfold'' expected: 55 got: r on: s.
  "Overflow storm: fewer reps (it deopts every call until blacklisted; we only
   need enough to drive the bail/blacklist guard and observe self-heal)."
  r := 0. 1 to: 50000 do: [:k | r := self overflowSeries].
  self check: ''overflow_series'' expected: 1152921504606852025 got: r on: s.
  r := 0. 1 to: reps do: [:k | r := self intervalDoNop: 100].
  self check: ''interval_do'' expected: 5050 got: r on: s.
  r := 0. 1 to: reps do: [:k | r := self negSum: -3 to: 5].
  self check: ''neg_do'' expected: 9 got: r on: s.
  r := 0. 1 to: reps do: [:k | r := self negInject: -3 to: 5].
  self check: ''neg_inject'' expected: 9 got: r on: s.
  r := 0. 1 to: reps do: [:k | r := self negIntervalDo: -3 to: 5].
  self check: ''neg_intervaldo'' expected: 9 got: r on: s.
  r := 0. 1 to: reps do: [:k | r := self nlrFirst: 5].
  self check: ''nlr_first'' expected: 1 got: r on: s.
  r := 0. 1 to: reps do: [:k | r := self intvDoDeopt].
  self check: ''ivdo_deopt'' expected: 42 got: r on: s.
  r := 0. 1 to: reps do: [:k | r := self intvInjectDeopt].
  self check: ''ivinject_deopt'' expected: (4611686018427387904 * 4) + 6 got: r on: s.
  [ | f | f := ''/tmp/sista_bench.txt'' asFileReference.
    f exists ifTrue: [f delete].
    f writeStreamDo: [:w | w nextPutAll: s contents] ] on: Error do: [:e | ].
  Transcript show: ''SISTABENCH-DONE''; cr' classified: 'bench'!

SistaBench class compile: 'startUp: resuming
  resuming ifFalse: [^ self].
  (''/tmp/sista_bench_done.txt'' asFileReference exists) ifTrue: [^ self].
  [self runBench] on: Error do: [:e |
     [ ''/tmp/sista_bench.txt'' asFileReference writeStreamDo: [:w |
        w nextPutAll: ''RUN-ERROR: ''; nextPutAll: e messageText ] ] on: Error do: [:e2 | ] ].
  ''/tmp/sista_bench_done.txt'' asFileReference ensureCreateFile.
  Smalltalk snapshot: false andQuit: true' classified: 'startup'!

SistaBench class compile: 'shutDown: quitting' classified: 'startup'!

SessionManager default
  register: (ClassSessionHandler forClassNamed: #SistaBench)
  inCategory: SessionManager default userCategory
  atPriority: 90!
