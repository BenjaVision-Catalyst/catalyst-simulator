"
Immutable versioned operation declarations and backend capabilities. Domain models compose generic operations; no ecosystem policy lives here.
"
Class {
	#name : 'CSOperationRegistry',
	#superclass : 'Object',
	#instVars : [
		'canonical'
	],
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'portable graph' }
CSOperationRegistry class >> definitions [
 | specs catalog |
 specs := #(
 ('core.constant' 1 'either' 'any' #() 'declared' #('value' 'declared'))
 ('core.tick' 1 'world' 'any' #() 'i64' #())
 ('core.entity.field' 1 'entity' 'any' #() 'field' #('field' 'string'))
 ('core.i64.add' 1 'either' 'any' #('i64' 'i64') 'i64' #())
 ('core.i64.less' 1 'either' 'any' #('i64' 'i64') 'bool' #())
 ('core.select.i64' 1 'either' 'any' #('bool' 'i64' 'i64') 'i64' #())
 ('core.string.equal' 1 'either' 'any' #('string' 'string') 'bool' #())
 ('core.bool.and' 1 'either' 'any' #('bool' 'bool') 'bool' #())
 ('core.bool.not' 1 'either' 'any' #('bool') 'bool' #())
 ('core.events.apply' 1 'world' 'events' #() 'void' #())
 ('core.velocity.set' 1 'entity' 'decide' #('bool' 'vec3') 'void' #())
 ('core.mode.set' 1 'entity' 'decide' #('bool' 'string') 'void' #())
 ('core.resource.request' 1 'entity' 'decide' #('bool' 'string' 'i64') 'void' #())
 ('core.motion.integrate' 1 'entity' 'motion' #('bool') 'void' #())
 ('core.resource.resolve' 1 'world' 'resolve' #() 'void' #())
 ('core.random.draw' 1 'entity' 'random' #('bool') 'void' #('stream' 'u32'))).
 catalog := Dictionary new.
 specs do: [:spec | | params row |
  params := Dictionary new.
  1 to: spec seventh size by: 2 do: [:i | params at: (spec seventh at: i) put: (spec seventh at: i + 1)].
  row := {spec second. spec third. spec fourth. spec fifth. spec sixth. params}.
  catalog at: spec first put: row].
 ^ catalog
]

{ #category : 'portable graph' }
CSOperationRegistry class >> portable [
 ^ self supporting: self definitions keys asArray
]

{ #category : 'portable graph' }
CSOperationRegistry class >> supporting: operationNames [
 ^ self new initializeSupporting: operationNames
]

{ #category : 'portable graph' }
CSOperationRegistry >> digest [
 ^ CSSha256 hexDigestOf: 'CatalystSimulation-Registry-1:', canonical
]

{ #category : 'portable graph' }
CSOperationRegistry >> encodedValueBoundFor: graph entityLimit: maximum [
 | sizes total |
 sizes := Dictionary new at: 'void' put: 0; at: 'i64' put: 22; at: 'u32' put: 22;
  at: 'bool' put: 1; at: 'string' put: 4102; at: 'vec3' put: 69; yourself.
 total := 16.
 (graph snapshot at: 'nodes') do: [:node | | bytes |
  bytes := sizes at: (node at: 'type').
  bytes > 0 ifTrue: [
   total := total + 100 + ((node at: 'scope') = 'world'
    ifTrue: [bytes] ifFalse: [(36 + bytes) * maximum])]].
 ^ total
]

{ #category : 'portable graph' }
CSOperationRegistry >> fieldTypes [
 ^ Dictionary new
  at: 'id' put: 'string';
  at: 'position' put: 'vec3';
  at: 'velocity' put: 'vec3';
  at: 'requestedResource' put: 'string';
  at: 'requestedQuantity' put: 'i64';
  at: 'mode' put: 'string';
  at: 'drawIndex' put: 'u32';
  at: 'sample' put: 'u32';
  at: 'motionRemainders' put: 'vec3';
  yourself
]

{ #category : 'portable graph' }
CSOperationRegistry >> initializeSupporting: names [
 | all selected |
 all := self class definitions. selected := Dictionary new.
 names do: [:name |
  CSKernelMath require: (all includesKey: name) message: 'Cannot register an unknown executable operation'.
  selected at: name put: (all at: name)].
 canonical := CSCanonicalCodec encode: selected. ^ self
]

{ #category : 'portable graph' }
CSOperationRegistry >> issueAt: path code: code message: message [
 ^ Dictionary new at: 'path' put: path; at: 'code' put: code; at: 'message' put: message; yourself
]

{ #category : 'portable graph' }
CSOperationRegistry >> issuesFor: graph entityLimit: maximum [
 | issues nodes byId catalog worldCount entityCount |
 issues := OrderedCollection new. nodes := graph snapshot at: 'nodes'.
 byId := Dictionary new. nodes do: [:node | byId at: (node at: 'id') put: node].
 catalog := self snapshot. worldCount := 0. entityCount := 0.
 nodes do: [:node | | path op descriptor params expected output |
  path := 'model/graph/nodes/', (node at: 'id').
  op := node at: 'operation'.
  (node at: 'scope') = 'world' ifTrue: [worldCount := worldCount + 1] ifFalse: [entityCount := entityCount + 1].
  descriptor := catalog at: op ifAbsent: [nil].
  descriptor
   ifNil: [issues add: (self issueAt: path, '/operation' code: 'unsupported-operation' message: 'Backend does not implement ', op)]
   ifNotNil: [
    (node at: 'version') = descriptor first ifFalse: [issues add: (self issueAt: path, '/version' code: 'unsupported-version' message: 'Backend requires operation version ', descriptor first printString)].
    (descriptor second = 'either' or: [descriptor second = (node at: 'scope')]) ifFalse: [issues add: (self issueAt: path, '/scope' code: 'scope-mismatch' message: 'Operation requires scope ', descriptor second)].
    (descriptor third = 'any' or: [descriptor third = (node at: 'stage')]) ifFalse: [issues add: (self issueAt: path, '/stage' code: 'stage-mismatch' message: 'Operation requires stage ', descriptor third)].
    expected := descriptor fourth.
    (node at: 'inputs') size = expected size
     ifFalse: [issues add: (self issueAt: path, '/inputs' code: 'input-count' message: 'Operation input count differs')]
     ifTrue: [1 to: expected size do: [:i |
      ((byId at: ((node at: 'inputs') at: i)) at: 'type') = (expected at: i)
       ifFalse: [issues add: (self issueAt: path, '/inputs/', i printString code: 'input-type' message: 'Expected ', (expected at: i))]]].
    params := node at: 'parameters'.
    params keys asSet = descriptor sixth keys asSet
     ifFalse: [issues add: (self issueAt: path, '/parameters' code: 'parameter-schema' message: 'Operation parameter keys differ')]
     ifTrue: [descriptor sixth keysAndValuesDo: [:key :type |
      (self matches: (params at: key) type: (type = 'declared' ifTrue: [node at: 'type'] ifFalse: [type]))
       ifFalse: [issues add: (self issueAt: path, '/parameters/', key code: 'parameter-type' message: 'Parameter value has incompatible type')]]].
    output := descriptor fifth.
    output = 'declared'
     ifTrue: [output := node at: 'type'. output = 'void' ifTrue: [issues add: (self issueAt: path, '/type' code: 'output-type' message: 'Constant requires a value type')]].
    output = 'field' ifTrue: [
     output := self fieldTypes at: (params at: 'field' ifAbsent: ['']) ifAbsent: ['unknown']].
    output = (node at: 'type') ifFalse: [issues add: (self issueAt: path, '/type' code: 'output-type' message: 'Operation output type differs')]]].
 (nodes count: [:node | (node at: 'operation') = 'core.events.apply']) = 1
  ifFalse: [issues add: (self issueAt: 'model/graph/nodes' code: 'event-drain' message: 'Exactly one core.events.apply node is required')].
 #('core.resource.resolve' 'core.motion.integrate' 'core.random.draw') do: [:op |
  (nodes count: [:node | (node at: 'operation') = op]) > 1 ifTrue: [
   issues add: (self issueAt: 'model/graph/nodes' code: 'duplicate-effect' message: 'At most one ', op, ' node is supported')]].
 worldCount + (entityCount * maximum) > (graph snapshot at: 'maxNodeEvaluations')
  ifTrue: [issues add: (self issueAt: 'model/graph/maxNodeEvaluations' code: 'evaluation-budget' message: 'Worst-case node evaluations exceed the model budget')].
 (self encodedValueBoundFor: graph entityLimit: maximum) > 67108864
  ifTrue: [issues add: (self issueAt: 'model/graph/nodes' code: 'value-budget' message: 'Worst-case retained value encoding exceeds 64 MiB')].
 ^ issues asArray
]

{ #category : 'portable graph' }
CSOperationRegistry >> matches: value type: type [
 type = 'bool' ifTrue: [^ value == true or: [value == false]].
 type = 'i64' ifTrue: [^ value isInteger and: [value between: -9223372036854775808 and: 9223372036854775807]].
 type = 'u32' ifTrue: [^ value isInteger and: [value between: 0 and: 4294967295]].
 type = 'string' ifTrue: [^ value isString and: [value isSymbol not and: [value size <= 4096 and: [value allSatisfy: [:c | c asciiValue between: 32 and: 126]]]]].
 type = 'vec3' ifTrue: [^ value class == Array and: [value size = 3 and: [value allSatisfy: [:coordinate | self matches: coordinate type: 'i64']]]].
 ^ false
]

{ #category : 'portable graph' }
CSOperationRegistry >> snapshot [
 ^ CSCanonicalCodec decode: canonical
]
