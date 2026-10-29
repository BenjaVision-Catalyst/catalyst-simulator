"
CatalystSimulation P0/P1 portable probe foundation. Generic mechanisms only; ecosystem rules and UE content belong to domain components.
"
Class {
	#name : 'CSKernelExamples',
	#superclass : 'TestCase',
	#category : 'BVC-Simulator-Tests',
	#package : 'BVC-Simulator-Tests'
}

{ #category : 'tests' }
CSKernelExamples >> id: integer [
 ^ (String new: 31 withAll: $0), integer asString
]

{ #category : 'tests' }
CSKernelExamples >> probe [
 | backend |
 backend := CSSmalltalkBackend model: CSModelBundle probe seed: 42.
 backend addResource: 'charge' quantity: 3.
 #(2 1) do: [ :i | | id |
  id := self id: i.
  backend addEntity: id position: #(0 0 0) velocity: #(3 -3 0).
  backend requestResource: 'charge' quantity: 2 for: id ].
 backend schedule: (self id: 8) at: 2 entity: (self id: 1) mode: 'ready'.
 ^ backend
]

{ #category : 'tests' }
CSKernelExamples >> testBoundedRunUntil [
 | backend manual before |
 backend := self probe. manual := self probe.
 backend advanceThrough: 6.
 6 timesRepeat: [manual advance].
 self assert: backend checkpoint equals: manual checkpoint.
 before := backend checkpoint.
 self assert: (backend advanceThrough: 6) equals: 6.
 self should: [backend advanceThrough: 5] raise: CSKernelError.
 self should: [backend advanceThrough: 1007] raise: CSKernelError.
 self assert: backend checkpoint equals: before
]

{ #category : 'tests' }
CSKernelExamples >> testCanonicalEncoding [
 | first second text |
 first := Dictionary new at: 'b' put: #(1 true nil); at: 'a' put: 'hello'; yourself.
 second := Dictionary new at: 'a' put: 'hello'; at: 'b' put: #(1 true nil); yourself.
 text := 'd2:s1:as5:hellos1:ba3:i1;tn'.
 self assert: (CSCanonicalCodec encode: first) equals: text.
 self assert: (CSCanonicalCodec encode: second) equals: text.
 self assert: (CSCanonicalCodec decode: text) equals: first.
 self assert: (CSCanonicalCodec copy: '') equals: ''.
 self assert: (CSCanonicalCodec copy: -9223372036854775808) equals: -9223372036854775808.
 self assert: (CSCanonicalCodec copy: 18446744073709551615) equals: 18446744073709551615
]

{ #category : 'tests' }
CSKernelExamples >> testCanonicalRejections [
 #('i01;' 'i-0;' 'd2:s1:bi1;s1:ai2;' 'd2:s1:ai1;s1:ai2;' 's2:a' 'i1;extra' 'a-1:' 's1:') do: [ :text |
  self should: [ CSCanonicalCodec decode: text ] raise: CSKernelError ].
 self should: [ CSCanonicalCodec encode: 1.5 ] raise: CSKernelError.
 self should: [ CSCanonicalCodec encode: [ 1 ] ] raise: CSKernelError.
 self should: [ CSCanonicalCodec encode: #symbol ] raise: CSKernelError.
 self should: [ CSCanonicalCodec encode: 18446744073709551616 ] raise: CSKernelError.
 self should: [ CSCanonicalCodec encode: (String new: 4097 withAll: $a) ] raise: CSKernelError
]

{ #category : 'tests' }
CSKernelExamples >> testCapacityAndInvalidAdmission [
 | raw backend before |
 raw := CSModelBundle probe snapshot. raw at: 4 put: 1; at: 5 put: 1.
 backend := CSSmalltalkBackend model: (CSModelBundle fromSnapshot: raw) seed: 0.
 backend addEntity: (self id: 1) position: #(0 0 0) velocity: #(0 0 0).
 before := backend checkpoint.
 self should: [ backend addEntity: (self id: 2) position: #(0 0 0) velocity: #(0 0 0) ] raise: CSKernelError.
 self should: [ backend schedule: (self id: 8) at: 0 entity: (self id: 1) mode: 'ready' ] raise: CSKernelError.
 self assert: backend checkpoint equals: before.
 backend schedule: (self id: 8) at: 1 entity: (self id: 1) mode: 'ready'.
 before := backend checkpoint.
 self should: [ backend schedule: (self id: 9) at: 1 entity: (self id: 1) mode: 'ready' ] raise: CSKernelError.
 self assert: backend checkpoint equals: before
]

{ #category : 'tests' }
CSKernelExamples >> testCheckpointContinuation [
 | backend restored |
 backend := self probe. backend advance.
 restored := CSSmalltalkBackend fromCheckpoint: backend checkpoint.
 self assert: restored checkpoint equals: backend checkpoint.
 5 timesRepeat: [ backend advance. restored advance ].
 self assert: restored checkpoint equals: backend checkpoint
]

{ #category : 'tests' }
CSKernelExamples >> testClockAndDrawExhaustion [
 | state backend before |
 #('tick' 'draw') do: [ :field |
  state := self probe snapshot.
  field = 'tick'
   ifTrue: [ state at: 'tick' put: 9223372036854775807. state at: 'events' put: (CSEventQueue limit: 10000) snapshot ]
   ifFalse: [ ((state at: 'entities') at: (self id: 1)) at: 7 put: 4294967295 ].
  backend := CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: state).
  before := backend checkpoint.
  self should: [ backend advance ] raise: CSKernelError.
  self assert: backend checkpoint equals: before ]
]

{ #category : 'tests' }
CSKernelExamples >> testContentionAndMotion [
 | backend state entity |
 backend := self probe. backend advance.
 state := backend snapshot. entity := (state at: 'entities') at: (self id: 1).
 self assert: entity second equals: #(0 -1 0).
 self assert: (entity at: 9) equals: #(300 700 0).
 self assert: (state at: 'resources') values asArray equals: #(1).
 self assert: entity fifth equals: 0.
 self assert: ((state at: 'entities') at: (self id: 2)) fifth equals: 2.
 self assert: (state at: 'outcomes') first third equals: (self id: 1).
 9 timesRepeat: [ backend advance ].
 self assert: ((backend snapshot at: 'entities') at: (self id: 1)) second equals: #(3 -3 0)
]

{ #category : 'tests' }
CSKernelExamples >> testEventOrderAndCancelledCheckpoint [
 | backend restored |
 backend := self probe.
 backend cancel: (self id: 8).
 backend schedule: (self id: 9) at: 1 entity: (self id: 1) mode: 'first'.
 backend schedule: (self id: 7) at: 1 entity: (self id: 1) mode: 'last'.
 restored := CSSmalltalkBackend fromCheckpoint: backend checkpoint.
 2 timesRepeat: [ backend advance. restored advance ].
 self assert: backend checkpoint equals: restored checkpoint.
 self assert: ((restored snapshot at: 'entities') at: (self id: 1)) sixth equals: 'last'
]

{ #category : 'tests' }
CSKernelExamples >> testFailedStepDoesNotPublish [
 | backend before |
 backend := CSFailingProbeBackend fromCheckpoint: self probe checkpoint.
 before := backend checkpoint.
 2 timesRepeat: [
  self should: [ backend advance ] raise: CSKernelError.
  self assert: backend tick equals: 0.
  self assert: backend checkpoint equals: before ].
 backend addResource: 'another' quantity: 1
]

{ #category : 'tests' }
CSKernelExamples >> testIterationOrderIndependence [
 | first second |
 first := self probe.
 second := CSSmalltalkBackend model: CSModelBundle probe seed: 42.
 second addResource: 'charge' quantity: 3.
 #(1 2) do: [ :i |
  second addEntity: (self id: i) position: #(0 0 0) velocity: #(3 -3 0).
  second requestResource: 'charge' quantity: 2 for: (self id: i) ].
 second schedule: (self id: 8) at: 2 entity: (self id: 1) mode: 'ready'.
 4 timesRepeat: [ first advance. second advance ].
 self assert: first checkpoint equals: second checkpoint
]

{ #category : 'tests' }
CSKernelExamples >> testMalformedRestore [
 | state |
 state := self probe snapshot.
 state at: 'unknown' put: true.
 self should: [ CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: state) ] raise: CSKernelError.
 state := self probe snapshot.
 ((((state at: 'entities') at: (self id: 1)) at: 9)) at: 1 put: -1.
 self should: [ CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: state) ] raise: CSKernelError.
 state := self probe snapshot.
 (state at: 'events') first first at: 1 put: 0.
 self should: [ CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: state) ] raise: CSKernelError
]

{ #category : 'tests' }
CSKernelExamples >> testModelCompatibilityAndIsolation [
 | raw model |
 raw := CSModelBundle probe snapshot. model := CSModelBundle fromSnapshot: raw.
 raw at: 3 put: 999.
 self assert: model tickMilliseconds equals: 100.
 raw := model snapshot. raw sixth at: 1 put: 'closure'.
 model := CSModelBundle fromSnapshot: raw.
 self assert: model compatibilityIssues first first equals: 'model/stages'.
 self should: [ CSSmalltalkBackend model: model seed: 0 ] raise: CSKernelError
]

{ #category : 'tests' }
CSKernelExamples >> testMotionConservesFractionalDisplacement [
 | raw backend entity |
 raw := CSModelBundle probe snapshot. raw at: 3 put: 37.
 -9 to: 9 do: [ :speed |
  backend := CSSmalltalkBackend model: (CSModelBundle fromSnapshot: raw) seed: 0.
  backend addEntity: (self id: 1) position: #(0 0 0) velocity: { speed. 0. 0 }.
  13 timesRepeat: [ backend advance ].
  entity := (backend snapshot at: 'entities') at: (self id: 1).
  self assert: entity second first * 1000 + (entity at: 9) first equals: speed * 37 * 13 ]
]

{ #category : 'tests' }
CSKernelExamples >> testOverflowDoesNotPublish [
 | backend before |
 backend := CSSmalltalkBackend model: CSModelBundle probe seed: 0.
 backend addEntity: (self id: 1) position: #(9223372036854775807 0 0) velocity: #(1000 0 0).
 before := backend checkpoint.
 self should: [ backend advance ] raise: CSKernelError.
 self assert: backend checkpoint equals: before
]

{ #category : 'tests' }
CSKernelExamples >> testPhiloxKnownAnswers [
 self assert: (CSPhilox wordsFor: #(0 0 0 0) key: #(0 0)) equals: #(16r6627E8D5 16rE169C58D 16rBC57AC4C 16r9B00DBD8).
 self assert: (CSPhilox wordsFor: #(16rFFFFFFFF 16rFFFFFFFF 16rFFFFFFFF 16rFFFFFFFF) key: #(16rFFFFFFFF 16rFFFFFFFF)) equals: #(16r408F276D 16r41C83B0E 16rA20BC7C6 16r6D5451FD).
 self assert: (CSPhilox wordsFor: #(16r243F6A88 16r85A308D3 16r13198A2E 16r03707344) key: #(16rA4093822 16r299F31D0)) equals: #(16rD16CFE09 16r94FDCCEB 16r5001E420 16r24126EA1).
 self assert: (CSPhilox sampleFor: '0123456789abcdeffedcba9876543210' seed: 16rFEDCBA9876543210 stream: 16r13579BDF draw: 16r2468ACE0) equals: 697764476
]

{ #category : 'tests' }
CSKernelExamples >> testSnapshotsDoNotAliasAcceptedState [
 | backend before data key |
 backend := self probe. before := backend checkpoint.
 data := backend snapshot.
 ((data at: 'entities') at: (self id: 1)) second at: 1 put: 999.
 self assert: backend checkpoint equals: before.
 key := 'other' copy. backend addResource: key quantity: 1.
 before := backend checkpoint. key at: 1 put: $X.
 self assert: backend checkpoint equals: before
]

{ #category : 'tests' }
CSKernelExamples >> testSpatialQueriesAgainstDistance [
 | positions grid point expected |
 positions := Dictionary new.
 1 to: 9 do: [ :i | positions at: (self id: i) put: { i * 3 - 15. i - 5. 0 } ].
 grid := CSSpatialGrid width: 5 positions: positions.
 self assert: (grid cellFor: #(-1 -5 -6)) equals: #(-1 -1 -2).
 #(#(0 0 0) #(-5 -1 0) #(10 4 0)) do: [ :center |
  point := center.
  expected := positions keys select: [ :id | | distance |
   distance := 0. 1 to: 3 do: [ :i | distance := distance + (((positions at: id) at: i) - (point at: i)) squared ].
   distance <= 49 ].
  self assert: (grid within: 7 of: center) equals: (expected asArray sorted: [ :a :b | CSKernelMath string: a precedes: b ]) ].
 self should: [ grid within: 10000 of: #(0 0 0) ] raise: CSKernelError
]

{ #category : 'tests' }
CSKernelExamples >> testTimerCancellationAndReschedule [
 | backend |
 backend := self probe.
 backend cancel: (self id: 8).
 backend advance; advance.
 self assert: ((backend snapshot at: 'entities') at: (self id: 1)) sixth equals: 'idle'.
 backend schedule: (self id: 8) at: 3 entity: (self id: 1) mode: 'obsolete'.
 backend schedule: (self id: 8) at: 3 entity: (self id: 1) mode: 'ready'.
 backend advance.
 self assert: ((backend snapshot at: 'entities') at: (self id: 1)) sixth equals: 'ready'.
 self assert: (backend snapshot at: 'events') first isEmpty
]
