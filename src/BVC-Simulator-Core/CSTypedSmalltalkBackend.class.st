Class {
	#name : 'CSTypedSmalltalkBackend',
	#superclass : 'CSSmalltalkBackend',
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'typed population' }
CSTypedSmalltalkBackend class >> fromPopulationState: state [
 ^ self new initializePopulationState: state
]

{ #category : 'typed population' }
CSTypedSmalltalkBackend class >> model: model seed: seed population: population [
 | state |
 CSKernelMath require: model isTyped message: 'Typed model profile required'.
 state := (CSSmalltalkBackend model: model seed: seed) snapshot.
 state at: 'entities' put: population.
 ^ self fromPopulationState: state
]

{ #category : 'typed population' }
CSTypedSmalltalkBackend >> applyContentionTo: state [
 | outcomes resources population |
 resources := state at: 'resources'. population := state at: 'entities'. outcomes := OrderedCollection new.
 (self entityIdsIn: state) do: [:id | | entity quantity key available |
  entity := population at: id. quantity := entity fifth. key := entity fourth.
  quantity > 0 ifTrue: [
   available := resources at: key.
   available >= quantity ifTrue: [
    resources at: key put: available - quantity. entity at: 5 put: 0. population at: id put: entity.
    outcomes add: {(state at: 'tick'). key. id. quantity}]]].
 state at: 'outcomes' put: outcomes asArray
]

{ #category : 'typed population' }
CSTypedSmalltalkBackend >> applyEffect: op inputs: inputs parameters: params state: state entity: id [
 | entity population |
 op = 'core.events.apply' ifTrue: [self applyEventsTo: state. ^ nil].
 op = 'core.resource.resolve' ifTrue: [self applyContentionTo: state. ^ nil].
 inputs first ifFalse: [^ nil].
 population := state at: 'entities'.
 op = 'core.motion.integrate' ifTrue: [population integrate: id milliseconds: bundle tickMilliseconds. ^ nil].
 entity := population at: id.
 op = 'core.velocity.set' ifTrue: [entity at: 3 put: inputs second copy].
 op = 'core.mode.set' ifTrue: [entity at: 6 put: inputs second copy].
 op = 'core.resource.request' ifTrue: [
  CSKernelMath require: (inputs third = 0 or: [(state at: 'resources') includesKey: inputs second]) message: 'Missing requested resource'.
  entity at: 4 put: inputs second copy; at: 5 put: inputs third].
 op = 'core.random.draw' ifTrue: [self drawEntity: entity seed: (state at: 'seed') stream: (params at: 'stream')].
 population at: id put: entity. ^ nil
]

{ #category : 'typed population' }
CSTypedSmalltalkBackend >> applyEventsTo: state [
 | queue population |
 queue := CSEventQueue fromSnapshot: (state at: 'events'). population := state at: 'entities'.
 (queue takeThrough: (state at: 'tick')) do: [:event | | row | row := population at: event fourth. row at: 6 put: event eighth. population at: event fourth put: row].
 state at: 'events' put: queue snapshot
]

{ #category : 'typed population' }
CSTypedSmalltalkBackend >> change: operation [
 | candidate |
 CSKernelMath require: advancing ~= true message: 'Backend is already advancing'.
 candidate := self snapshot. operation value: candidate. self validate: candidate. accepted := candidate
]

{ #category : 'typed population' }
CSTypedSmalltalkBackend >> checkpoint [
 CSKernelError signal: 'Typed populations require checkpoint-1 artifacts'
]

{ #category : 'typed population' }
CSTypedSmalltalkBackend >> copyState: state [
 | result |
 result := Dictionary new.
 state keysAndValuesDo: [:key :value | result at: key put: (key = 'entities' ifTrue: [value copy] ifFalse: [CSCanonicalCodec copy: value])].
 ^ result
]

{ #category : 'typed population' }
CSTypedSmalltalkBackend >> executeGraphOn: state [
 | graph nodes byId values ids stage read |
 graph := bundle graph. nodes := graph orderedNodes. byId := Dictionary new.
 nodes do: [:node | byId at: (node at: 'id') put: node].
 ids := self entityIdsIn: state.
 CSKernelMath require: ((nodes count: [:node | (node at: 'scope') = 'world']) + ((nodes count: [:node | (node at: 'scope') = 'entity']) * ids size)) <= (graph snapshot at: 'maxNodeEvaluations') message: 'Node evaluation budget exceeded'.
 values := Dictionary new. stage := nil.
 nodes do: [:node |
  stage = (node at: 'stage') ifFalse: [
   stage := node at: 'stage'. read := self copyState: state].
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

{ #category : 'typed population' }
CSTypedSmalltalkBackend >> initializePopulationState: state [
 bundle := CSModelBundle fromSnapshot: (state at: 'model').
 CSKernelMath require: bundle isTyped message: 'Typed model profile required'.
 registry := CSOperationRegistry portable. self requireCompatible: (bundle compatibilityReportFor: registry).
 advancing := false. accepted := self copyState: state.
 (accepted at: 'entities') seal.
 self validate: accepted.
 (accepted at: 'entities') keysAndValuesDo: [:id :row | self validateEntity: row id: id resources: (accepted at: 'resources')].
 ^ self
]

{ #category : 'typed population' }
CSTypedSmalltalkBackend >> populationStatistics [ ^ (accepted at: 'entities') statistics
]

{ #category : 'typed population' }
CSTypedSmalltalkBackend >> snapshot [ ^ self copyState: accepted
]

{ #category : 'typed population' }
CSTypedSmalltalkBackend >> validate: state [
 CSKernelMath require: ((state at: 'entities') isKindOf: CSTypedPopulation) message: 'Typed population required'.
 self validateHeader: state entities: (state at: 'entities')
]
