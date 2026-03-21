"Setup Fake GUI Environment for Headless Pharo.

 Creates a virtual display with a running Morphic world loop so that
 GUI-dependent code (Spec presenters, menus, morphs) works without a
 real display driver. After loading, you can:

   FakeGUI clickMenuItemNamed: 'Save'.
   FakeGUI clickButtonNamed: 'OK' in: aPresenter.
   FakeGUI screenshotToFile: '/tmp/screenshot.png'.
   FakeGUI screenshot. ""returns the Display Form""

 Usage:
   pharo --headless Pharo.image eval --save \
     '''setup_fake_gui.st'' asFileReference fileIn'

 Works on: Pharo 13, Pharo 14, any Spur VM (Cog JIT, interpreter, Mac Catalyst)
 Dependencies: none (pure Smalltalk)"!

"=== Step 1: Ensure Display and World exist ==="

"Create Display Form if missing"
(Smalltalk globals at: #Display ifAbsent: [nil]) ifNil: [
  | form |
  form := Form extent: 1024@768 depth: 32.
  Smalltalk globals at: #Display put: form].

"Ensure a WorldMorph exists"
WorldMorph allInstances ifEmpty: [
  | world |
  world := WorldMorph new.
  world extent: 1024@768.
  world color: Color white.
  ActiveWorld := world.
  World := world].

"=== Step 2: Install MorphicUIManager and start UI process ==="

"Switch from NonInteractiveUIManager to MorphicUIManager so that
 the UI process runs and deferred blocks execute."
(UIManager default class == MorphicUIManager) ifFalse: [
  MorphicUIManager new beDefault].

"Ensure the UI process is running (MorphicRenderLoop doOneCycleWhile:)"
(UIManager default respondsTo: #uiProcess) ifTrue: [
  | proc |
  proc := UIManager default uiProcess.
  (proc isNil or: [proc isTerminated]) ifTrue: [
    MorphicUIManager new spawnNewProcess]].

"=== Step 3: Patch Morph>>activate/passivate to handle nil submorphs ==="

"In headless mode, submorphs can contain nil entries when layout hasn't
 fully initialized. This causes 'receiver of activate is nil' errors."
Morph compile: 'activate
  "Make receiver and submorphs able to respond to events."
  self submorphsDo: [:m | m ifNotNil: [m activate]]' classified: 'events-processing'!

Morph compile: 'passivate
  "Make receiver and submorphs unable to respond to events."
  self submorphsDo: [:m | m ifNotNil: [m passivate]]' classified: 'events-processing'!

"=== Step 4: FakeGUI helper class ==="

ShiftClassInstaller make: [:builder |
  builder
    name: #FakeGUI;
    superclass: Object;
    package: 'Tests-FakeGUI']!

"--- World stepping ---"

!FakeGUI class methodsFor: 'world'!
ensureWorldStepping
  "Force world cycles to process pending deferred blocks."
  | world |
  world := WorldMorph allInstances
    ifEmpty: [nil]
    ifNotEmpty: [:all | all first].
  world ifNotNil: [
    3 timesRepeat: [
      [world doOneCycleNow] on: Error do: [:e |]]]! !

"--- Opening presenters ---"

!FakeGUI class methodsFor: 'opening'!
openPresenter: aPresenter
  "Open a presenter and wait for it to be built."
  | window |
  window := aPresenter open.
  self ensureWorldStepping.
  ^ window! !

"--- Menu and button interaction ---"

!FakeGUI class methodsFor: 'menus'!
findMenuItemNamed: aString in: aMorph
  "Recursively find a menu item morph by label text."
  | result |
  result := nil.
  aMorph submorphsDo: [:m |
    result ifNil: [
      ((m respondsTo: #contents) and: [
        [m contents asString = aString] on: Error do: [:e | false]])
          ifTrue: [result := m].
      result ifNil: [
        ((m respondsTo: #label) and: [
          [m label asString = aString] on: Error do: [:e | false]])
            ifTrue: [result := m]].
      result ifNil: [
        ((m respondsTo: #labelString) and: [
          m labelString notNil and: [
            [m labelString asString = aString] on: Error do: [:e | false]]])
              ifTrue: [result := m]].
      result ifNil: [
        result := self findMenuItemNamed: aString in: m]]].
  ^ result! !

!FakeGUI class methodsFor: 'menus'!
clickMenuItemNamed: aString
  "Find and click a menu item by name in the world."
  | world item |
  world := World ifNil: [WorldMorph allInstances first].
  item := self findMenuItemNamed: aString in: world.
  item ifNil: [^ self error: 'Menu item not found: ', aString].
  item mouseDown: (MouseButtonEvent new
    setPosition: item bounds center;
    yourself).
  item mouseUp: (MouseButtonEvent new
    setPosition: item bounds center;
    yourself).
  self ensureWorldStepping.
  ^ item! !

!FakeGUI class methodsFor: 'menus'!
clickButtonNamed: aString in: aPresenterOrMorph
  "Find and click a button by label in a presenter window or morph."
  | morph target |
  morph := (aPresenterOrMorph respondsTo: #window)
    ifTrue: [aPresenterOrMorph window ifNotNil: [:w | w morph]]
    ifFalse: [aPresenterOrMorph].
  morph ifNil: [^ self error: 'No morph to search in'].
  target := self findMenuItemNamed: aString in: morph.
  target ifNil: [^ self error: 'Button not found: ', aString].
  target mouseDown: (MouseButtonEvent new
    setPosition: target bounds center;
    yourself).
  target mouseUp: (MouseButtonEvent new
    setPosition: target bounds center;
    yourself).
  self ensureWorldStepping.
  ^ target! !

"--- Querying morphs ---"

!FakeGUI class methodsFor: 'querying'!
allMorphsNamed: aString
  "Find all morphs in the world that display the given text."
  | results world |
  results := OrderedCollection new.
  world := World ifNil: [WorldMorph allInstances first].
  self collectMorphsNamed: aString in: world into: results.
  ^ results! !

!FakeGUI class methodsFor: 'querying'!
collectMorphsNamed: aString in: aMorph into: results
  "Recursively collect morphs matching a name."
  aMorph submorphsDo: [:m |
    (m respondsTo: #contents) ifTrue: [
      ([m contents asString = aString] on: Error do: [:e | false])
        ifTrue: [results add: m]].
    (m respondsTo: #label) ifTrue: [
      ([m label asString = aString] on: Error do: [:e | false])
        ifTrue: [results add: m]].
    self collectMorphsNamed: aString in: m into: results]! !

!FakeGUI class methodsFor: 'querying'!
findWidgetOfType: aClass in: aPresenterOrMorph
  "Find first widget of given class in a presenter or morph tree."
  | morph |
  morph := (aPresenterOrMorph respondsTo: #window)
    ifTrue: [aPresenterOrMorph window ifNotNil: [:w | w morph]]
    ifFalse: [aPresenterOrMorph].
  morph ifNil: [^ nil].
  ^ self findMorphOfType: aClass in: morph! !

!FakeGUI class methodsFor: 'querying'!
findMorphOfType: aClass in: aMorph
  "Recursively find first morph of given class."
  | result |
  (aMorph isKindOf: aClass) ifTrue: [^ aMorph].
  result := nil.
  aMorph submorphsDo: [:m |
    result ifNil: [
      result := self findMorphOfType: aClass in: m]].
  ^ result! !

"--- Screenshots ---"

!FakeGUI class methodsFor: 'screenshots'!
screenshot
  "Return the current Display Form after stepping the world.
   The form contains whatever the Morphic world has rendered."
  self ensureWorldStepping.
  ^ Display! !

!FakeGUI class methodsFor: 'screenshots'!
screenshotToFile: aFilePath
  "Render the world and save the Display as a PNG file.
   Returns the file path.

   Example:
     FakeGUI screenshotToFile: '/tmp/screenshot.png'"
  | form |
  self ensureWorldStepping.
  form := Display.
  form writePNGFileNamed: aFilePath.
  ^ aFilePath! !

!FakeGUI class methodsFor: 'screenshots'!
screenshotOf: aMorph
  "Render a specific morph to a Form and return it."
  | form |
  form := aMorph imageForm.
  ^ form! !

!FakeGUI class methodsFor: 'screenshots'!
screenshotOf: aMorph toFile: aFilePath
  "Render a specific morph and save as PNG.

   Example:
     FakeGUI screenshotOf: World toFile: '/tmp/world.png'.
     FakeGUI screenshotOf: somePresenter window morph toFile: '/tmp/dialog.png'"
  | form |
  form := aMorph imageForm.
  form writePNGFileNamed: aFilePath.
  ^ aFilePath! !

"=== Done ==="
Transcript show: 'FakeGUI environment installed'; cr!
