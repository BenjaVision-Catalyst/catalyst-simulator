"
CatalystSimulation P0/P1 portable probe foundation. Generic mechanisms only; ecosystem rules and UE content belong to domain components.
"
Class {
	#name : 'CSSmalltalkBackend',
	#superclass : 'Object',
	#instVars : [
		'bundle',
		'accepted',
		'advancing',
		'registry'
	],
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'portable kernel' }
CSSmalltalkBackend class >> fromCheckpoint: encoded [
 ^ self new initializeCheckpoint: encoded
]

{ #category : 'portable graph' }
CSSmalltalkBackend class >> fromCheckpoint: encoded registry: capabilities [
 ^ self new initializeCheckpoint: encoded registry: capabilities
]

{ #category : 'portable kernel' }
CSSmalltalkBackend class >> model: model seed: seed [
 ^ self new initializeModel: model seed: seed
]

{ #category : 'portable graph' }
CSSmalltalkBackend class >> model: model seed: seed registry: capabilities [
 ^ self new initializeModel: model seed: seed registry: capabilities
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

{ #category : 'portable graph' }
CSSmalltalkBackend >> advance [
 | candidate |
 CSKernelMath require: advancing ~= true message: 'Backend is already advancing'.
 advancing := true.
 [candidate := self snapshot.
  candidate at: 'tick' put: (CSKernelMath nonnegative: (candidate at: 'tick') + 1).
  bundle isGraph
   ifTrue: [candidate at: 'outcomes' put: #(). self executeGraphOn: candidate]
   ifFalse: [
    self applyEventsTo: candidate. self applyMotionTo: candidate.
    self applyContentionTo: candidate. self applyRandomTo: candidate].
  self validate: candidate. accepted := candidate
 ] ensure: [advancing := false].
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

{ #category : 'portable graph' }
CSSmalltalkBackend >> applyEffect: op inputs: inputs parameters: params state: state entity: id [
 | entity |
 op = 'core.events.apply' ifTrue: [self applyEventsTo: state. ^ nil].
 op = 'core.resource.resolve' ifTrue: [self applyContentionTo: state. ^ nil].
 inputs first ifFalse: [^ nil].
 entity := (state at: 'entities') at: id.
 op = 'core.velocity.set' ifTrue: [entity at: 3 put: inputs second copy. ^ nil].
 op = 'core.mode.set' ifTrue: [entity at: 6 put: inputs second copy. ^ nil].
 op = 'core.resource.request' ifTrue: [
  CSKernelMath nonnegative: inputs third.
  entity at: 4 put: inputs second copy; at: 5 put: inputs third. ^ nil].
 op = 'core.motion.integrate' ifTrue: [self integrateEntity: entity. ^ nil].
 op = 'core.random.draw' ifTrue: [self drawEntity: entity seed: (state at: 'seed') stream: (params at: 'stream'). ^ nil].
 CSKernelError signal: 'No executable handler for declared operation'
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

{ #category : 'portable graph' }
CSSmalltalkBackend >> compatibilityReport [
 ^ bundle compatibilityReportFor: (registry ifNil: [CSOperationRegistry portable])
]

{ #category : 'portable graph' }
CSSmalltalkBackend >> drawEntity: entity seed: seed stream: stream [
 | draw |
 draw := entity seventh.
 entity at: 8 put: (CSPhilox sampleFor: entity first seed: seed stream: stream draw: draw).
 entity at: 7 put: (CSKernelMath uint32: draw + 1)
]

{ #category : 'portable kernel' }
CSSmalltalkBackend >> entityIdsIn: state [
 ^ (state at: 'entities') keys asArray sorted: [ :a :b | CSKernelMath string: a precedes: b ]
]

{ #category : 'portable graph' }
CSSmalltalkBackend >> evaluateNode: node inputs: inputs state: state read: read entity: id [
 | op params index |
 op := node at: 'operation'. params := node at: 'parameters'.
 op = 'core.constant' ifTrue: [^ CSCanonicalCodec copy: (params at: 'value')].
 op = 'core.tick' ifTrue: [^ read at: 'tick'].
 op = 'core.entity.field' ifTrue: [
  index := #('id' 'position' 'velocity' 'requestedResource' 'requestedQuantity' 'mode' 'drawIndex' 'sample' 'motionRemainders') indexOf: (params at: 'field').
  ^ CSCanonicalCodec copy: (((read at: 'entities') at: id) at: index)].
 op = 'core.i64.add' ifTrue: [^ CSKernelMath int64: inputs first + inputs second].
 op = 'core.i64.less' ifTrue: [^ inputs first < inputs second].
 op = 'core.select.i64' ifTrue: [^ inputs first ifTrue: [inputs second] ifFalse: [inputs third]].
 op = 'core.string.equal' ifTrue: [^ inputs first = inputs second].
 op = 'core.bool.and' ifTrue: [^ inputs first and: [inputs second]].
 op = 'core.bool.not' ifTrue: [^ inputs first not].
 ^ self applyEffect: op inputs: inputs parameters: params state: state entity: id
]

{ #category : 'portable graph' }
CSSmalltalkBackend >> executeGraphOn: state [
 | graph nodes byId values ids stage read |
 graph := bundle graph. nodes := graph orderedNodes. byId := Dictionary new.
 nodes do: [:node | byId at: (node at: 'id') put: node].
 ids := self entityIdsIn: state.
 CSKernelMath require: ((nodes count: [:node | (node at: 'scope') = 'world']) + ((nodes count: [:node | (node at: 'scope') = 'entity']) * ids size)) <= (graph snapshot at: 'maxNodeEvaluations') message: 'Node evaluation budget exceeded'.
 values := Dictionary new. stage := nil.
 nodes do: [:node |
  stage = (node at: 'stage') ifFalse: [
   stage := node at: 'stage'. read := CSCanonicalCodec copy: state].
  (node at: 'scope') = 'world'
   ifTrue: [| result |
    result := self evaluateNode: node inputs: (self inputsFor: node entity: nil values: values nodes: byId) state: state read: read entity: nil.
    (node at: 'type') = 'void' ifFalse: [values at: (node at: 'id') put: result]]
   ifFalse: [| results |
    results := Dictionary new.
    ids do: [:id | | result |
     result := self evaluateNode: node inputs: (self inputsFor: node entity: id values: values nodes: byId) state: state read: read entity: id.
     (node at: 'type') = 'void' ifFalse: [results at: id put: result]].
    (node at: 'type') = 'void' ifFalse: [values at: (node at: 'id') put: results]] ]
]

{ #category : 'portable graph' }
CSSmalltalkBackend >> initializeCheckpoint: encoded [
 ^ self initializeCheckpoint: encoded registry: CSOperationRegistry portable
]

{ #category : 'portable graph' }
CSSmalltalkBackend >> initializeCheckpoint: encoded registry: capabilities [
 | candidate |
 candidate := CSCanonicalCodec decode: encoded.
 CSKernelMath require: ((candidate isKindOf: Dictionary) and: [candidate includesKey: 'model']) message: 'Checkpoint model is required'.
 bundle := CSModelBundle fromSnapshot: (candidate at: 'model').
 registry := CSOperationRegistry supporting: capabilities snapshot keys asArray.
 self requireCompatible: (bundle compatibilityReportFor: registry).
 advancing := false. self validate: candidate. accepted := candidate. ^ self
]

{ #category : 'portable graph' }
CSSmalltalkBackend >> initializeModel: model seed: seed [
 ^ self initializeModel: model seed: seed registry: CSOperationRegistry portable
]

{ #category : 'portable graph' }
CSSmalltalkBackend >> initializeModel: model seed: seed registry: capabilities [
 | report |
 registry := CSOperationRegistry supporting: capabilities snapshot keys asArray.
 report := model compatibilityReportFor: registry.
 self requireCompatible: report.
 CSKernelMath uint64: seed. bundle := CSModelBundle fromSnapshot: model snapshot. advancing := false.
 accepted := Dictionary new
  at: 'version' put: (bundle isGraph ifTrue: [2] ifFalse: [1]);
  at: 'model' put: bundle snapshot; at: 'tick' put: 0; at: 'seed' put: seed;
  at: 'entities' put: Dictionary new; at: 'resources' put: Dictionary new;
  at: 'events' put: (CSEventQueue limit: bundle eventLimit) snapshot;
  at: 'outcomes' put: #(); yourself.
 bundle isGraph ifTrue: [accepted at: 'modelDigest' put: bundle digest].
 self validate: accepted. ^ self
]

{ #category : 'portable graph' }
CSSmalltalkBackend >> inputsFor: node entity: id values: values nodes: byId [
 ^ (node at: 'inputs') collect: [:ref | | value |
  value := values at: ref.
  ((byId at: ref) at: 'scope') = 'entity' ifTrue: [value at: id] ifFalse: [value]]
]

{ #category : 'portable graph' }
CSSmalltalkBackend >> integrateEntity: entity [
 | position remainder wide |
 position := entity second. remainder := entity at: 9.
 1 to: 3 do: [:i |
  wide := (entity third at: i) * bundle tickMilliseconds + (remainder at: i).
  position at: i put: (CSKernelMath int64: (position at: i) + (wide // 1000)).
  remainder at: i put: wide \\ 1000]
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

{ #category : 'portable graph' }
CSSmalltalkBackend >> requireCompatible: report [
 (report at: 'compatible') ifFalse: [| first |
  first := (report at: 'issues') first.
  CSKernelError signal: (first at: 'path'), ': ', (first at: 'message')]
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

{ #category : 'portable graph' }
CSSmalltalkBackend >> validate: state [
 | entities resources queue expectedKeys |
 CSKernelMath require: (state isKindOf: Dictionary) message: 'Invalid state'.
 expectedKeys := #('version' 'model' 'tick' 'seed' 'entities' 'resources' 'events' 'outcomes') asSet.
 bundle isGraph ifTrue: [expectedKeys add: 'modelDigest'].
 CSKernelMath require: state keys asSet = expectedKeys message: 'Unknown or missing checkpoint fields'.
 CSKernelMath require: ((state at: 'version') = (bundle isGraph ifTrue: [2] ifFalse: [1]) and: [(state at: 'model') = bundle snapshot]) message: 'Checkpoint version or model mismatch'.
 bundle isGraph ifTrue: [CSKernelMath require: (state at: 'modelDigest') = bundle digest message: 'Checkpoint model digest mismatch'].
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
