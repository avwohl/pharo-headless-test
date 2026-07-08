"ExpC: UNBOUNDED freeze recursion — remove the depth cap and outer catch so the
 recursing stack is never unwound. This pins every freeze-copied signaler stack LIVE,
 exactly the census's 'process recursing in Exception>>freeze, ~12 contexts/pass,
 heap -> GB of Contexts'. Heap capped at 1200MB: a genuine storm aborts with
 [HEAP-CENSUS] dominated by Context/MessageNotUnderstood/PrimitiveFailed."
| mk |
mk := nil.
mk := [:n |
   [ (MessageNotUnderstood new) signal ]
      on: MessageNotUnderstood
      do: [:e |
          e freeze.
          mk value: n + 1 ] ].
mk value: 1
