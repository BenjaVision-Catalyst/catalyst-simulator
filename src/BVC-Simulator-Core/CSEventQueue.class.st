"
CatalystSimulation P0/P1 portable probe foundation. Generic mechanisms only; ecosystem rules and UE content belong to domain components.
"
Class {
	#name : 'CSEventQueue',
	#superclass : 'Object',
	#instVars : [
		'entries',
		'generations',
		'sequence',
		'limit'
	],
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'portable kernel' }
CSEventQueue class >> fromSnapshot: value [
 ^ self new initializeFrom: value
]

{ #category : 'portable kernel' }
CSEventQueue class >> limit: capacity [
 ^ self new initializeLimit: capacity
]

{ #category : 'portable kernel' }
CSEventQueue >> active: event [
 ^ event seventh = (generations at: event sixth)
]

{ #category : 'portable kernel' }
CSEventQueue >> cancel: eventId [
 CSKernelMath identifier: eventId.
 (generations includesKey: eventId) ifTrue: [ generations at: eventId put: (CSKernelMath nonnegative: (generations at: eventId) + 1) ]
]

{ #category : 'portable kernel' }
CSEventQueue >> initializeFrom: value [
 CSKernelMath require: (value class == Array and: [ value size = 4 ]) message: 'Invalid event queue'.
 self initializeLimit: value fourth.
 CSKernelMath nonnegative: value third. sequence := value third.
 CSKernelMath require: (value first class == Array and: [ value second isKindOf: Dictionary ]) message: 'Invalid event queue containers'.
 CSKernelMath require: (value first size <= limit and: [ value second size <= limit ]) message: 'Event capacity exceeded'.
 generations := CSCanonicalCodec copy: value second.
 generations keysAndValuesDo: [ :key :generation | CSKernelMath identifier: key. CSKernelMath nonnegative: generation ].
 entries := (CSCanonicalCodec copy: value first) asOrderedCollection.
 entries do: [ :event |
  CSKernelMath require: (event class == Array and: [ event size = 8 ]) message: 'Invalid event fields'.
  CSKernelMath nonnegative: event first.
  CSKernelMath require: (event second = 0 and: [ event third = 0 ]) message: 'Unsupported event phase or priority'.
  CSKernelMath identifier: event fourth.
  CSKernelMath nonnegative: event fifth.
  CSKernelMath require: (event fifth > 0 and: [ event fifth <= sequence ]) message: 'Invalid event sequence'.
  CSKernelMath identifier: event sixth. CSKernelMath nonnegative: event seventh.
  CSKernelMath require: ((generations includesKey: event sixth) and: [ event seventh <= (generations at: event sixth) ]) message: 'Invalid event generation'.
  CSKernelMath require: event eighth isString message: 'Mode must be a string' ].
 CSKernelMath require: (entries collect: [ :e | e fifth ]) asSet size = entries size message: 'Duplicate event sequence'.
 ^ self
]

{ #category : 'portable kernel' }
CSEventQueue >> initializeLimit: capacity [
 CSKernelMath require: (capacity isInteger and: [ capacity between: 1 and: 10000 ]) message: 'Event capacity required'.
 limit := capacity. entries := OrderedCollection new. generations := Dictionary new. sequence := 0. ^ self
]

{ #category : 'portable kernel' }
CSEventQueue >> schedule: eventId at: tick entity: entityId mode: mode [
 | generation |
 CSKernelMath identifier: eventId. CSKernelMath identifier: entityId.
 CSKernelMath nonnegative: tick. CSKernelMath require: mode isString message: 'Mode required'.
 entries := entries select: [ :each | self active: each ].
 CSKernelMath require: entries size < limit message: 'Event capacity exceeded'.
 CSKernelMath require: ((generations includesKey: eventId) or: [ generations size < limit ]) message: 'Event identity capacity exceeded'.
 generation := CSKernelMath nonnegative: (generations at: eventId ifAbsent: [ -1 ]) + 1.
 sequence := CSKernelMath nonnegative: sequence + 1.
 generations at: eventId put: generation.
 entries add: { tick. 0. 0. entityId. sequence. eventId. generation. mode }
]

{ #category : 'portable kernel' }
CSEventQueue >> snapshot [
 ^ CSCanonicalCodec copy: { (entries asArray sorted: [ :a :b | CSKernelMath less: a than: b ]). generations. sequence. limit }
]

{ #category : 'portable kernel' }
CSEventQueue >> takeThrough: tick [
 | due |
 CSKernelMath nonnegative: tick.
 due := entries select: [ :each | each first <= tick and: [ self active: each ] ].
 entries := entries select: [ :each | each first > tick and: [ self active: each ] ].
 ^ due asArray sorted: [ :a :b | CSKernelMath less: a than: b ]
]
