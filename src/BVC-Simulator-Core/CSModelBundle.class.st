"
CatalystSimulation P0/P1 portable probe foundation. Generic mechanisms only; ecosystem rules and UE content belong to domain components.
"
Class {
	#name : 'CSModelBundle',
	#superclass : 'Object',
	#instVars : [
		'canonical',
		'digest',
		'tickMillis',
		'entityCapacity',
		'eventCapacity',
		'graphProfile'
	],
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'portable kernel' }
CSModelBundle class >> fromSnapshot: value [
 ^ self new initializeFrom: value
]

{ #category : 'portable kernel' }
CSModelBundle class >> probe [
 ^ self fromSnapshot: #('simulation-portable-1/probe-1' 'portable-probe' 100 10000 10000 #('events' 'move' 'contend' 'random'))
]

{ #category : 'portable graph' }
CSModelBundle >> canonicalBytes [
 ^ canonical copy
]

{ #category : 'portable graph' }
CSModelBundle >> compatibilityIssues [
 ^ ((self compatibilityReportFor: CSOperationRegistry portable) at: 'issues') collect: [:issue | {issue at: 'path'. issue at: 'message'}]
]

{ #category : 'portable graph' }
CSModelBundle >> compatibilityReportFor: capabilities [
 | issues stages required catalog |
 self isGraph
  ifTrue: [issues := capabilities issuesFor: self graph entityLimit: self entityLimit]
  ifFalse: [
   issues := OrderedCollection new. stages := self snapshot sixth.
   stages = #('events' 'move' 'contend' 'random') ifFalse: [
    issues add: (capabilities issueAt: 'model/stages' code: 'unsupported-stages' message: 'probe-1 requires events, move, contend, random in that order')].
   required := #('core.events.apply' 'core.motion.integrate' 'core.resource.resolve' 'core.random.draw').
   catalog := capabilities snapshot.
   1 to: required size do: [:i |
    (catalog includesKey: (required at: i)) ifFalse: [
     issues add: (capabilities issueAt: 'model/stages/', i printString code: 'unsupported-operation' message: 'Backend does not implement ', (required at: i))]].
   issues := issues asArray].
 ^ Dictionary new
  at: 'profile' put: self snapshot first; at: 'modelDigest' put: self digest;
  at: 'registryDigest' put: capabilities digest; at: 'compatible' put: issues isEmpty;
  at: 'issues' put: issues; yourself
]

{ #category : 'portable graph' }
CSModelBundle >> digest [
 ^ digest ifNil: [CSSha256 hexDigestOf: 'CatalystSimulation-Model-1:', canonical] ifNotNil: [digest copy]
]

{ #category : 'portable graph' }
CSModelBundle >> entityLimit [
 ^ entityCapacity ifNil: [self snapshot fourth]
]

{ #category : 'portable graph' }
CSModelBundle >> eventLimit [
 ^ eventCapacity ifNil: [self snapshot fifth]
]

{ #category : 'portable graph' }
CSModelBundle >> graph [
 CSKernelMath require: self isGraph message: 'Graph profile required'.
 ^ CSModelGraph fromSnapshot: self snapshot sixth
]

{ #category : 'typed population' }
CSModelBundle >> initializeFrom: value [
 | normalized graph |
 CSKernelMath require: (value class == Array and: [value size = 6]) message: 'Model requires six fields'.
 CSKernelMath require: (#('simulation-portable-1/probe-1' 'simulation-portable-1/graph-1' 'simulation-portable-1/typed-1') includes: value first) message: 'Unsupported model profile'.
 CSKernelMath require: (value second isString and: [value second notEmpty]) message: 'Model identity required'.
 CSKernelMath int64: value third.
 CSKernelMath require: (value third between: 1 and: 1000) message: 'Tick duration must be 1..1000 milliseconds'.
 4 to: 5 do: [:i | CSKernelMath int64: (value at: i). CSKernelMath require: ((value at: i) between: 1 and: ((i = 4 and: [value first = 'simulation-portable-1/typed-1']) ifTrue: [1000000] ifFalse: [10000])) message: 'Model capacity exceeds profile'].
 normalized := CSCanonicalCodec copy: value.
 value first = 'simulation-portable-1/probe-1'
  ifTrue: [CSKernelMath require: (value sixth class == Array and: [value sixth allSatisfy: [:stage | stage isString]]) message: 'Stages must be described names']
  ifFalse: [graph := CSModelGraph fromSnapshot: value sixth. normalized at: 6 put: graph snapshot].
 tickMillis := normalized third. entityCapacity := normalized fourth. eventCapacity := normalized fifth.
 graphProfile := normalized first ~= 'simulation-portable-1/probe-1'.
 canonical := CSCanonicalCodec encode: normalized.
 digest := CSSha256 hexDigestOf: 'CatalystSimulation-Model-1:', canonical. ^ self
]

{ #category : 'portable graph' }
CSModelBundle >> isGraph [
 ^ graphProfile ifNil: [self snapshot first = 'simulation-portable-1/graph-1']
]

{ #category : 'typed population' }
CSModelBundle >> isTyped [ ^ self snapshot first = 'simulation-portable-1/typed-1'
]

{ #category : 'portable kernel' }
CSModelBundle >> snapshot [
 ^ CSCanonicalCodec decode: canonical
]

{ #category : 'portable graph' }
CSModelBundle >> tickMilliseconds [
 ^ tickMillis ifNil: [self snapshot third]
]
