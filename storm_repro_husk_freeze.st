| c mk husk |
(Smalltalk at: #HuskStormA ifAbsent: [nil]) ifNotNil: [:k | k removeFromSystem].
c := Smalltalk classInstaller make: [ :b |
      b superclass: Object; name: #HuskStormA; layoutClass: FixedLayout;
        package: 'Zz'; traitComposition: TOne asTraitComposition; slots: #( x ) ].
c new. c addInstVarNamed: #y.
c new. c addInstVarNamed: #z.
husk := c allInstances detect: [:o | [o instVarAt: c instSize. false] on: Error do: [:e | true] ] ifNone: [nil].
husk isNil
  ifTrue: [ Smalltalk at: #R put: 'NO-HUSK' ]
  ifFalse: [
    mk := nil.
    mk := [:n | [ husk instVarAt: c instSize ] on: Error do: [:e | e freeze. mk value: n+1] ].
    mk value: 1.
    Smalltalk at: #R put: 'completed-no-storm' ].
