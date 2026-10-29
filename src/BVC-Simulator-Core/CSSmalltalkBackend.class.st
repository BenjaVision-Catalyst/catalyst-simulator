"
CatalystSimulation P0/P1 portable probe foundation. Generic mechanisms only; ecosystem rules and UE content belong to domain components.
"
Class {
	#name : 'CSSmalltalkBackend',
	#superclass : 'Object',
	#instVars : [
		'bundle',
		'accepted',
		'advancing'
	],
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'portable kernel' }
CSSmalltalkBackend class >> fromCheckpoint: encoded [
 ^ self new initializeCheckpoint: encoded
]

{ #category : 'portable kernel' }
CSSmalltalkBackend class >> model: model seed: seed [
 ^ self new initializeModel: model seed: seed
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> addEntity: id position: point velocity: velocity [
 self change: [ :candidate |
  CSKernelMath require: ((candidate at: 'entities') includesKey: id) not message: 'Duplicate entity'.
  (candidate at: 'entities') at: id put: { id copy. point copy. velocity copy. ''. 0. 'idle'. 0. 0. #(0 0 0) copy } ]
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> addResource: key quantity: quantity [
 self change: [ :candidate |
  CSKernelMath require: ((candidate at: 'resources') includesKey: key) not message: 'Duplicate resource'.
  (candidate at: 'resources') at: key put: quantity ]
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> advance [
 | candidate |
 CSKernelMath require: advancing ~= true message: 'Backend is already advancing'.
 advancing := true.
 [ candidate := self snapshot.
   candidate at: 'tick' put: (CSKernelMath nonnegative: (candidate at: 'tick') + 1).
   self applyEventsTo: candidate.
   self applyMotionTo: candidate.
   self applyContentionTo: candidate.
   self applyRandomTo: candidate.
   self validate: candidate.
   accepted := candidate
 ] ensure: [ advancing := false ].
 ^ self tick
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> advanceThrough: target [
 CSKernelMath nonnegative: target.
 CSKernelMath require: (target >= self tick and: [ target - self tick <= 1000 ]) message: 'Run requires 0..1000 future ticks'.
 [self tick < target] whileTrue: [self advance].
 ^ self tick
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> applyContentionTo: state [
 | outcomes resources |
 resources := state at: 'resources'. outcomes := OrderedCollection new.
 (self entityIdsIn: state) do: [ :id | | entity quantity key available |
  entity := (state at: 'entities') at: id. quantity := entity fifth. key := entity fourth.
  quantity > 0 ifTrue: [
   available := resources at: key.
   available >= quantity ifTrue: [
    resources at: key put: available - quantity.
    entity at: 5 put: 0.
    outcomes add: { (state at: 'tick'). key. id. quantity } ] ] ].
 state at: 'outcomes' put: outcomes asArray
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> applyEventsTo: state [
 | queue |
 queue := CSEventQueue fromSnapshot: (state at: 'events').
 (queue takeThrough: (state at: 'tick')) do: [ :event |
  ((state at: 'entities') at: event fourth) at: 6 put: event eighth ].
 state at: 'events' put: queue snapshot
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> applyMotionTo: state [
 (self entityIdsIn: state) do: [ :id | | entity position remainder wide |
  entity := (state at: 'entities') at: id.
  position := entity second. remainder := (entity at: 9).
  1 to: 3 do: [ :i |
   wide := (entity third at: i) * bundle tickMilliseconds + (remainder at: i).
   position at: i put: (CSKernelMath int64: (position at: i) + (wide // 1000)).
   remainder at: i put: wide \\ 1000 ] ]
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> applyRandomTo: state [
 (self entityIdsIn: state) do: [ :id | | entity draw |
  entity := (state at: 'entities') at: id. draw := entity seventh.
  entity at: 8 put: (CSPhilox sampleFor: id seed: (state at: 'seed') stream: 0 draw: draw).
  entity at: 7 put: (CSKernelMath uint32: draw + 1) ]
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> cancel: eventId [
 self change: [ :candidate | | queue |
  queue := CSEventQueue fromSnapshot: (candidate at: 'events').
  queue cancel: eventId.
  candidate at: 'events' put: queue snapshot ]
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> change: operation [
 | candidate |
 CSKernelMath require: advancing ~= true message: 'Backend is already advancing'.
 candidate := self snapshot.
 operation value: candidate.
 self validate: candidate.
 accepted := CSCanonicalCodec copy: candidate
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> checkpoint [
 ^ CSCanonicalCodec encode: accepted
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> entityIdsIn: state [
 ^ (state at: 'entities') keys asArray sorted: [ :a :b | CSKernelMath string: a precedes: b ]
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> initializeCheckpoint: encoded [
 | candidate |
 candidate := CSCanonicalCodec decode: encoded.
 CSKernelMath require: (candidate isKindOf: Dictionary) message: 'Checkpoint dictionary required'.
 bundle := CSModelBundle fromSnapshot: (candidate at: 'model').
 CSKernelMath require: bundle compatibilityIssues isEmpty message: 'Unsupported model stages'.
 advancing := false. self validate: candidate. accepted := candidate. ^ self
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> initializeModel: model seed: seed [
 CSKernelMath require: model compatibilityIssues isEmpty message: 'Unsupported model stages'.
 CSKernelMath uint64: seed. bundle := CSModelBundle fromSnapshot: model snapshot. advancing := false.
 accepted := Dictionary new
  at: 'version' put: 1;
  at: 'model' put: bundle snapshot;
  at: 'tick' put: 0;
  at: 'seed' put: seed;
  at: 'entities' put: Dictionary new;
  at: 'resources' put: Dictionary new;
  at: 'events' put: (CSEventQueue limit: bundle eventLimit) snapshot;
  at: 'outcomes' put: #();
  yourself.
 self validate: accepted. ^ self
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> model [
 ^ CSModelBundle fromSnapshot: bundle snapshot
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> requestResource: key quantity: quantity for: id [
 self change: [ :candidate | | entity |
  entity := (candidate at: 'entities') at: id.
  entity at: 4 put: key copy; at: 5 put: quantity ]
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> schedule: eventId at: tick entity: id mode: mode [
 self change: [ :candidate | | queue |
  CSKernelMath require: tick > (candidate at: 'tick') message: 'Event must target a future tick'.
  queue := CSEventQueue fromSnapshot: (candidate at: 'events').
  queue schedule: eventId at: tick entity: id mode: mode.
  candidate at: 'events' put: queue snapshot ]
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> snapshot [
 ^ CSCanonicalCodec copy: accepted
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> spatialGridWithWidth: width [
 | positions |
 positions := Dictionary new.
 (accepted at: 'entities') keysAndValuesDo: [ :id :entity | positions at: id put: entity second ].
 ^ CSSpatialGrid width: width positions: positions
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> tick [
 ^ accepted at: 'tick'
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> validate: state [
 | entities resources queue |
 CSKernelMath require: (state isKindOf: Dictionary) message: 'Invalid state'.
 CSKernelMath require: state keys asSet = #('version' 'model' 'tick' 'seed' 'entities' 'resources' 'events' 'outcomes') asSet message: 'Unknown or missing checkpoint fields'.
 CSKernelMath require: ((state at: 'version') = 1 and: [ (state at: 'model') = bundle snapshot ]) message: 'Checkpoint version or model mismatch'.
 CSKernelMath nonnegative: (state at: 'tick'). CSKernelMath uint64: (state at: 'seed').
 entities := state at: 'entities'. resources := state at: 'resources'.
 CSKernelMath require: ((entities isKindOf: Dictionary) and: [ entities size <= bundle entityLimit ]) message: 'Entity capacity exceeded'.
 CSKernelMath require: ((resources isKindOf: Dictionary) and: [ resources size <= bundle entityLimit ]) message: 'Resource capacity exceeded'.
 resources keysAndValuesDo: [ :key :quantity |
  CSKernelMath require: (key isString and: [ key notEmpty ]) message: 'Resource name required'. CSKernelMath nonnegative: quantity ].
 entities keysAndValuesDo: [ :id :entity |
  CSKernelMath identifier: id.
  CSKernelMath require: (entity class == Array and: [ entity size = 9 and: [ entity first = id ] ]) message: 'Invalid entity record'.
  CSKernelMath vector: entity second. CSKernelMath vector: entity third.
  CSKernelMath require: entity fourth isString message: 'Invalid resource request'.
  CSKernelMath nonnegative: entity fifth.
  CSKernelMath require: (entity fifth = 0 or: [ resources includesKey: entity fourth ]) message: 'Missing requested resource'.
  CSKernelMath require: entity sixth isString message: 'Invalid mode'.
  CSKernelMath uint32: entity seventh. CSKernelMath uint32: entity eighth.
  CSKernelMath vector: (entity at: 9).
  CSKernelMath require: ((entity at: 9) allSatisfy: [ :r | r between: 0 and: 999 ]) message: 'Invalid motion remainder' ].
 queue := CSEventQueue fromSnapshot: (state at: 'events').
 CSKernelMath require: queue snapshot fourth = bundle eventLimit message: 'Event limit mismatch'.
 queue snapshot first do: [ :event |
  CSKernelMath require: (event first > (state at: 'tick') and: [ entities includesKey: event fourth ]) message: 'Past event or missing target' ].
 CSKernelMath require: ((state at: 'outcomes') class == Array and: [ (state at: 'outcomes') size <= bundle entityLimit ]) message: 'Outcome capacity exceeded'.
 (state at: 'outcomes') do: [ :outcome |
  CSKernelMath require: (outcome class == Array and: [ outcome size = 4 ]) message: 'Invalid outcome'.
  CSKernelMath require: (outcome first = (state at: 'tick') and: [ (resources includesKey: outcome second) and: [ entities includesKey: outcome third ] ]) message: 'Invalid outcome references'.
  CSKernelMath nonnegative: outcome fourth ].
 CSCanonicalCodec encode: state
]
