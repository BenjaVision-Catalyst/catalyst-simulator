"
Bounded normalized dataflow graph with staged immutable reads and explicit typed dependencies. Contains no executable source.
"
Class {
	#name : 'CSModelGraph',
	#superclass : 'Object',
	#instVars : [
		'canonical',
		'order'
	],
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'portable graph' }
CSModelGraph class >> fromSnapshot: value [
 ^ self new initializeFrom: value
]

{ #category : 'portable graph' }
CSModelGraph class >> name: value [
 ^ value isString and: [value isSymbol not and: [(value size between: 1 and: 64) and: [value allSatisfy: [:c | 'abcdefghijklmnopqrstuvwxyz0123456789-' includes: c]]]]
]

{ #category : 'portable graph' }
CSModelGraph class >> stages [
 ^ #('events' 'decide' 'motion' 'resolve' 'random')
]

{ #category : 'portable graph' }
CSModelGraph class >> types [
 ^ #('void' 'i64' 'u32' 'bool' 'string' 'vec3')
]

{ #category : 'portable graph' }
CSModelGraph >> initializeFrom: raw [
 | value nodes byId edges pending ready chosen seen stageRank |
 value := CSCanonicalCodec copy: raw.
 CSKernelMath require: ((value isKindOf: Dictionary) and: [value keys asSet = #('version' 'nodes' 'maxNodeEvaluations') asSet]) message: 'model/graph: invalid fields'.
 CSKernelMath require: (value at: 'version') = 1 message: 'model/graph/version: unsupported'.
 CSKernelMath require: ((value at: 'maxNodeEvaluations') isInteger and: [(value at: 'maxNodeEvaluations') between: 1 and: 1000000]) message: 'model/graph/maxNodeEvaluations: requires 1..1000000'.
 nodes := value at: 'nodes'.
 CSKernelMath require: (nodes class == Array and: [nodes size between: 1 and: 128]) message: 'model/graph/nodes: requires 1..128 nodes'.
 byId := Dictionary new. edges := 0.
 nodes do: [:node | | id |
  CSKernelMath require: ((node isKindOf: Dictionary) and: [node keys asSet = #('id' 'operation' 'version' 'stage' 'scope' 'type' 'inputs' 'after' 'parameters') asSet]) message: 'model/graph/nodes: invalid node fields'.
  id := node at: 'id'.
  CSKernelMath require: (self class name: id) message: 'model/graph/nodes: invalid node ID'.
  CSKernelMath require: (byId includesKey: id) not message: 'model/graph/nodes: duplicate node ID'.
  CSKernelMath require: ((node at: 'operation') isString and: [(node at: 'operation') size between: 1 and: 128]) message: 'model/graph/nodes/', id, '/operation: invalid name'.
  CSKernelMath require: ((node at: 'version') isInteger and: [(node at: 'version') between: 1 and: 65535]) message: 'model/graph/nodes/', id, '/version: invalid operation version'.
  CSKernelMath require: (self class stages includes: (node at: 'stage')) message: 'model/graph/nodes/', id, '/stage: unknown stage'.
  CSKernelMath require: (#('world' 'entity') includes: (node at: 'scope')) message: 'model/graph/nodes/', id, '/scope: unknown scope'.
  CSKernelMath require: (self class types includes: (node at: 'type')) message: 'model/graph/nodes/', id, '/type: unknown type'.
  #('inputs' 'after') do: [:key | | refs |
   refs := node at: key.
   CSKernelMath require: (refs class == Array and: [refs size <= 32 and: [refs allSatisfy: [:ref | self class name: ref]]]) message: 'model/graph/nodes/', id, '/', key, ': invalid references'.
   edges := edges + refs size].
  CSKernelMath require: (node at: 'after') asSet size = (node at: 'after') size message: 'model/graph/nodes/', id, '/after: duplicate reference'.
  node at: 'after' put: ((node at: 'after') sorted: [:a :b | CSKernelMath string: a precedes: b]).
  CSKernelMath require: ((node at: 'parameters') isKindOf: Dictionary) message: 'model/graph/nodes/', id, '/parameters: dictionary required'.
  CSKernelMath require: (node at: 'parameters') size <= 8 message: 'model/graph/nodes/', id, '/parameters: budget exceeded'.
  byId at: id put: node].
 CSKernelMath require: edges <= 1024 message: 'model/graph: edge budget exceeded'.
 nodes do: [:node | | rank |
  rank := self class stages indexOf: (node at: 'stage').
  ((node at: 'inputs'), (node at: 'after')) do: [:ref |
   CSKernelMath require: (byId includesKey: ref) message: 'model/graph/nodes/', (node at: 'id'), ': missing reference ', ref.
   CSKernelMath require: (self class stages indexOf: ((byId at: ref) at: 'stage')) <= rank message: 'model/graph/nodes/', (node at: 'id'), ': backward stage reference'].
  (node at: 'inputs') do: [:ref |
   CSKernelMath require: (((byId at: ref) at: 'type') ~= 'void') message: 'model/graph/nodes/', (node at: 'id'), ': void input'.
   CSKernelMath require: ((node at: 'scope') = 'entity' or: [((byId at: ref) at: 'scope') = 'world']) message: 'model/graph/nodes/', (node at: 'id'), ': entity input into world scope']].
 pending := nodes asOrderedCollection. seen := Set new. order := OrderedCollection new.
 [pending notEmpty] whileTrue: [
  ready := pending select: [:node | ((node at: 'inputs'), (node at: 'after')) allSatisfy: [:ref | seen includes: ref]].
  CSKernelMath require: ready notEmpty message: 'model/graph: cyclic dependencies'.
  ready := ready asArray sorted: [:a :b |
   stageRank := (self class stages indexOf: (a at: 'stage')) - (self class stages indexOf: (b at: 'stage')).
   stageRank = 0 ifTrue: [CSKernelMath string: (a at: 'id') precedes: (b at: 'id')] ifFalse: [stageRank < 0]].
  chosen := ready first. order add: (chosen at: 'id'). seen add: (chosen at: 'id'). pending remove: chosen].
 order := order asArray.
 value at: 'nodes' put: (nodes sorted: [:a :b | CSKernelMath string: (a at: 'id') precedes: (b at: 'id')]).
 canonical := CSCanonicalCodec encode: value. ^ self
]

{ #category : 'portable graph' }
CSModelGraph >> orderedNodes [
 | byId |
 byId := Dictionary new.
 (self snapshot at: 'nodes') do: [:node | byId at: (node at: 'id') put: node].
 ^ order collect: [:id | byId at: id]
]

{ #category : 'portable graph' }
CSModelGraph >> snapshot [
 ^ CSCanonicalCodec decode: canonical
]
