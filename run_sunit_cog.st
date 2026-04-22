"Stock-Cog baseline generation now uses the SAME harness as the custom VM.

 Before 2026-04-21 this file was a stand-alone runner that walked
 /tmp/class-list.txt with a bespoke loop.  That made Cog and the custom
 VM run different Smalltalk, so class-literal sets in the harness
 method differed and ClassQueryTest>>testAllCallsOn counted different
 senders for each VM — not a fair comparison.

 Unified flow (both VMs):

   # prep: stock Pharo fileIn + save installs SUnitRunner and its
   # SessionManager startup handler; stage the external class list.
   pharo Pharo.image eval --save \"'run_sunit_tests.st' asFileReference fileIn\"
   cp test_classes.txt /tmp/sunit_test_classes.txt

   # run: no eval args.  SessionManager fires SUnitRunner>>startUp:
   # on resume, which calls runAllTests and writes
   # /tmp/sunit_test_results.txt plus /tmp/sunit_test_detail.txt.
   pharo Pharo.image                 # stock-Cog baseline
   build/test_load_image Pharo.image # custom VM

 Running this file directly just aborts with a hint — it has no
 runner class of its own any more."

Transcript show: 'run_sunit_cog.st is deprecated.  Use run_sunit_tests.st (see file header).'; cr.
Smalltalk exitFailure.
