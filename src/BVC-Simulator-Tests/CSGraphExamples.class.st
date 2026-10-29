"
Portable graph, digest and compatibility contracts shared by GT and native GemStone.
"
Class {
	#name : 'CSGraphExamples',
	#superclass : 'TestCase',
	#category : 'BVC-Simulator-Tests',
	#package : 'BVC-Simulator-Tests'
}

{ #category : 'tests' }
CSGraphExamples >> builderFor: model named: modelName [
 | builder raw |
 raw := model snapshot.
 builder := CSModelBuilder named: modelName.
 builder tickMilliseconds: raw third; limitsEntities: raw fourth events: raw fifth evaluations: (raw sixth at: 'maxNodeEvaluations').
 (raw sixth at: 'nodes') do: [:node | builder addNode: node].
 ^ builder
]

{ #category : 'conformance' }
CSGraphExamples >> compatibilityFixtures [
 | fixtures raw model capabilities |
 fixtures := OrderedCollection new.
 #('missing-operation' 'version' 'unknown' 'type' 'budget' 'value-budget') do: [:kind |
  raw := self conditionalModel snapshot. capabilities := CSOperationRegistry portable.
  kind = 'missing-operation' ifTrue: [
   capabilities := CSOperationRegistry supporting: (CSOperationRegistry definitions keys reject: [:name | name = 'core.random.draw'])].
  kind = 'version' ifTrue: [(self node: 'move' in: raw) at: 'version' put: 2].
  kind = 'unknown' ifTrue: [(self node: 'move' in: raw) at: 'operation' put: 'future.move'].
  kind = 'type' ifTrue: [(self node: 'move' in: raw) at: 'inputs' put: #('quantity')].
  kind = 'value-budget' ifTrue: [raw := self valueBudgetModel snapshot].
  kind = 'budget' ifTrue: [raw sixth at: 'maxNodeEvaluations' put: 1].
  model := CSModelBundle fromSnapshot: raw.
  fixtures add: (Dictionary new
   at: 'name' put: kind; at: 'model' put: model canonicalBytes;
   at: 'operations' put: (capabilities snapshot keys asArray sorted: [:a :b | CSKernelMath string: a precedes: b]);
   at: 'report' put: (model compatibilityReportFor: capabilities); yourself)].
 ^ fixtures asArray
]

{ #category : 'tests' }
CSGraphExamples >> conditionalModel [
 | builder |
 builder := CSModelBuilder named: 'conditional-graph'.
 builder limitsEntities: 16 events: 32 evaluations: 256.
 self constant: 'enabled' value: true type: 'bool' in: builder stage: 'events'.
 builder node: 'events' operation: 'core.events.apply' stage: 'events' scope: 'world' type: 'void' inputs: #() after: #() parameters: Dictionary new.
 self constant: 'active' value: 'active' type: 'string' in: builder stage: 'decide'.
 self constant: 'charge' value: 'charge' type: 'string' in: builder stage: 'decide'.
 self constant: 'one' value: 1 type: 'i64' in: builder stage: 'decide'.
 self constant: 'velocity' value: #(10 0 0) type: 'vec3' in: builder stage: 'decide'.
 self constant: 'running' value: 'running' type: 'string' in: builder stage: 'decide'.
 builder node: 'mode-read' operation: 'core.entity.field' stage: 'decide' scope: 'entity' type: 'string' inputs: #() after: #() parameters: (Dictionary new at: 'field' put: 'mode'; yourself).
 builder node: 'is-active' operation: 'core.string.equal' stage: 'decide' scope: 'entity' type: 'bool' inputs: #('mode-read' 'active') after: #() parameters: Dictionary new.
 builder node: 'quantity' operation: 'core.i64.add' stage: 'decide' scope: 'world' type: 'i64' inputs: #('one' 'one') after: #() parameters: Dictionary new.
 builder node: 'set-velocity' operation: 'core.velocity.set' stage: 'decide' scope: 'entity' type: 'void' inputs: #('is-active' 'velocity') after: #() parameters: Dictionary new.
 builder node: 'request' operation: 'core.resource.request' stage: 'decide' scope: 'entity' type: 'void' inputs: #('is-active' 'charge' 'quantity') after: #() parameters: Dictionary new.
 builder node: 'set-mode' operation: 'core.mode.set' stage: 'decide' scope: 'entity' type: 'void' inputs: #('is-active' 'running') after: #('request') parameters: Dictionary new.
 builder node: 'move' operation: 'core.motion.integrate' stage: 'motion' scope: 'entity' type: 'void' inputs: #('enabled') after: #() parameters: Dictionary new.
 builder node: 'resolve' operation: 'core.resource.resolve' stage: 'resolve' scope: 'world' type: 'void' inputs: #() after: #() parameters: Dictionary new.
 builder node: 'random' operation: 'core.random.draw' stage: 'random' scope: 'entity' type: 'void' inputs: #('enabled') after: #() parameters: (Dictionary new at: 'stream' put: 7; yourself).
 ^ builder build
]

{ #category : 'conformance' }
CSGraphExamples >> conformanceFixture [
 | cases registry |
 cases := OrderedCollection new.
 self fixtureWorlds keysAndValuesDo: [:name :backend | | record checkpoints |
  record := Dictionary new at: 'name' put: name; at: 'model' put: backend model canonicalBytes;
   at: 'modelDigest' put: backend model digest; at: 'initial' put: backend checkpoint; yourself.
  checkpoints := Dictionary new.
  1 to: 6 do: [:tick |
   backend advance. (#(1 2 6) includes: tick) ifTrue: [checkpoints at: tick printString put: backend checkpoint]].
  record at: 'checkpoints' put: checkpoints.
  cases add: record].
 registry := CSOperationRegistry portable.
 ^ Dictionary new
  at: 'profile' put: 'simulation-portable-1/graph-1';
  at: 'registry' put: registry snapshot; at: 'registryDigest' put: registry digest;
  at: 'models' put: (cases asArray sorted: [:a :b | CSKernelMath string: (a at: 'name') precedes: (b at: 'name')]);
  at: 'compatibility' put: self compatibilityFixtures; yourself
]

{ #category : 'tests' }
CSGraphExamples >> constant: id value: value type: type in: builder stage: stage [
 builder node: id operation: 'core.constant' stage: stage scope: 'world' type: type inputs: #() after: #() parameters: (Dictionary new at: 'value' put: value; yourself)
]

{ #category : 'tests' }
CSGraphExamples >> expressionModel [
 | builder raw |
 builder := self builderFor: self conditionalModel named: 'expression-graph'.
 self constant: 'limit' value: 3 type: 'i64' in: builder stage: 'decide'.
 self constant: 'u32-constant' value: 4294967295 type: 'u32' in: builder stage: 'decide'.
 builder node: 'now' operation: 'core.tick' stage: 'decide' scope: 'world' type: 'i64' inputs: #() after: #() parameters: Dictionary new.
 builder node: 'early' operation: 'core.i64.less' stage: 'decide' scope: 'world' type: 'bool' inputs: #('now' 'limit') after: #() parameters: Dictionary new.
 builder node: 'late' operation: 'core.bool.not' stage: 'decide' scope: 'world' type: 'bool' inputs: #('early') after: #() parameters: Dictionary new.
 builder node: 'both' operation: 'core.bool.and' stage: 'decide' scope: 'entity' type: 'bool' inputs: #('is-active' 'late') after: #() parameters: Dictionary new.
 builder node: 'selected' operation: 'core.select.i64' stage: 'decide' scope: 'world' type: 'i64' inputs: #('early' 'one' 'quantity') after: #() parameters: Dictionary new.
 raw := builder build snapshot.
 #('set-velocity' 'set-mode') do: [:id | (self node: id in: raw) at: 'inputs' put: {'both'. (id = 'set-mode' ifTrue: ['running'] ifFalse: ['velocity'])}].
 (self node: 'request' in: raw) at: 'inputs' put: #('both' 'charge' 'selected').
 ^ CSModelBundle fromSnapshot: raw
]

{ #category : 'conformance' }
CSGraphExamples >> fixtureWorlds [
 | worlds probe |
 worlds := Dictionary new.
 probe := self worldFor: self probeModel.
 #(1 2) do: [:i | probe requestResource: 'charge' quantity: 2 for: (CSKernelExamples new id: i)].
 worlds at: 'graph-probe' put: probe;
  at: 'conditional-graph' put: (self worldFor: self conditionalModel);
  at: 'expression-graph' put: (self worldFor: self expressionModel).
 ^ worlds
]

{ #category : 'tests' }
CSGraphExamples >> node: id in: rawModel [
 ^ (rawModel sixth at: 'nodes') detect: [:node | (node at: 'id') = id]
]

{ #category : 'tests' }
CSGraphExamples >> probeModel [
 | builder |
 builder := CSModelBuilder named: 'graph-probe'.
 self constant: 'enabled' value: true type: 'bool' in: builder stage: 'events'.
 builder node: 'events' operation: 'core.events.apply' stage: 'events' scope: 'world' type: 'void' inputs: #() after: #() parameters: Dictionary new.
 builder node: 'move' operation: 'core.motion.integrate' stage: 'motion' scope: 'entity' type: 'void' inputs: #('enabled') after: #() parameters: Dictionary new.
 builder node: 'resolve' operation: 'core.resource.resolve' stage: 'resolve' scope: 'world' type: 'void' inputs: #() after: #() parameters: Dictionary new.
 builder node: 'random' operation: 'core.random.draw' stage: 'random' scope: 'entity' type: 'void' inputs: #('enabled') after: #() parameters: (Dictionary new at: 'stream' put: 0; yourself).
 ^ builder build
]

{ #category : 'tests' }
CSGraphExamples >> testCanonicalGraphIdentityAndIsolation [
 | first raw reordered changed digestCopy |
 first := self conditionalModel. raw := first snapshot.
 raw sixth at: 'nodes' put: (raw sixth at: 'nodes') reversed.
 (self node: 'set-mode' in: raw) at: 'after' put: #('quantity' 'request').
 changed := CSModelBundle fromSnapshot: raw.
 (self node: 'set-mode' in: raw) at: 'after' put: #('request' 'quantity').
 reordered := CSModelBundle fromSnapshot: raw.
 self assert: changed canonicalBytes equals: reordered canonicalBytes.
 self assert: changed digest equals: reordered digest.
 raw := first snapshot. raw sixth at: 'nodes' put: (raw sixth at: 'nodes') reversed.
 reordered := CSModelBundle fromSnapshot: raw.
 self assert: first digest equals: reordered digest.
 digestCopy := first digest. digestCopy at: 1 put: $x.
 self deny: first digest first = $x.
 (self node: 'velocity' in: raw) at: 'parameters' put: (Dictionary new at: 'value' put: #(20 0 0); yourself).
 changed := CSModelBundle fromSnapshot: raw.
 self deny: changed digest = first digest.
 self assert: ((self node: 'velocity' in: first snapshot) at: 'parameters') equals: (Dictionary new at: 'value' put: #(10 0 0); yourself)
]

{ #category : 'tests' }
CSGraphExamples >> testCompatibilityBeforeLaunchAndRestore [
 | model names limited report backend |
 model := self conditionalModel.
 names := CSOperationRegistry definitions keys reject: [:name | name = 'core.random.draw'].
 limited := CSOperationRegistry supporting: names.
 report := model compatibilityReportFor: limited.
 self deny: (report at: 'compatible').
 self assert: (report at: 'issues') first equals: (Dictionary new at: 'path' put: 'model/graph/nodes/random/operation'; at: 'code' put: 'unsupported-operation'; at: 'message' put: 'Backend does not implement core.random.draw'; yourself).
 self assert: (report at: 'modelDigest') equals: model digest.
 self should: [CSSmalltalkBackend model: model seed: 0 registry: limited] raise: CSKernelError.
 backend := self worldFor: model.
 self should: [CSSmalltalkBackend fromCheckpoint: backend checkpoint registry: limited] raise: CSKernelError.
 self assert: backend tick equals: 0
]

{ #category : 'tests' }
CSGraphExamples >> testConditionalGraphAndContinuation [
 | backend restored entity |
 backend := self worldFor: self conditionalModel.
 backend advance.
 self assert: (backend snapshot at: 'resources' ) values asArray equals: #(3).
 restored := CSSmalltalkBackend fromCheckpoint: backend checkpoint.
 backend advanceThrough: 6. restored advanceThrough: 6.
 self assert: backend checkpoint equals: restored checkpoint.
 entity := (backend snapshot at: 'entities') at: (CSKernelExamples new id: 1).
 self assert: entity sixth equals: 'running'.
 self assert: entity second equals: #(5 -1 0).
 self assert: (backend snapshot at: 'resources') values asArray equals: #(1).
 self assert: entity seventh equals: 6
]

{ #category : 'tests' }
CSGraphExamples >> testDigestTamperingAndSchemaFence [
 | backend state before |
 backend := self worldFor: self conditionalModel. before := backend checkpoint.
 state := backend snapshot. state at: 'modelDigest' put: (String new: 64 withAll: $0).
 self should: [CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: state)] raise: CSKernelError.
 state := backend snapshot. state at: 'version' put: 1.
 self should: [CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: state)] raise: CSKernelError.
 state := backend snapshot. state removeKey: 'model'.
 self should: [CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: state)] raise: CSKernelError.
 self assert: backend checkpoint equals: before
]

{ #category : 'tests' }
CSGraphExamples >> testGraphFailureKeepsAcceptedState [
 | raw backend before |
 raw := self conditionalModel snapshot.
 (self node: 'one' in: raw) at: 'parameters' put: (Dictionary new at: 'value' put: 9223372036854775807; yourself).
 backend := self worldFor: (CSModelBundle fromSnapshot: raw).
 before := backend checkpoint.
 2 timesRepeat: [
  self should: [backend advance] raise: CSKernelError.
  self assert: backend checkpoint equals: before.
  self assert: backend tick equals: 0]
]

{ #category : 'tests' }
CSGraphExamples >> testGraphMatchesLegacyMechanics [
 | graph legacy left right |
 graph := self worldFor: self probeModel.
 legacy := CSKernelExamples new probe.
 graph schedule: (CSKernelExamples new id: 8) at: 2 entity: (CSKernelExamples new id: 1) mode: 'ready'.
 #(1 2) do: [:i | graph requestResource: 'charge' quantity: 2 for: (CSKernelExamples new id: i)].
 "Rescheduling changes queue history, so compare entity/resource/outcome semantics."
 6 timesRepeat: [
  graph advance. legacy advance.
  left := graph snapshot. right := legacy snapshot.
  #('entities' 'resources' 'outcomes' 'tick') do: [:key | self assert: (left at: key) equals: (right at: key)]]
]

{ #category : 'tests' }
CSGraphExamples >> testInvalidGraphStructure [
 | raw node |
 #('duplicate' 'missing' 'cycle' 'backward' 'scope' 'void') do: [:kind |
  raw := self conditionalModel snapshot.
  kind = 'duplicate' ifTrue: [raw sixth at: 'nodes' put: (raw sixth at: 'nodes'), { (raw sixth at: 'nodes') first }].
  kind = 'missing' ifTrue: [(self node: 'move' in: raw) at: 'inputs' put: #('missing')].
  kind = 'cycle' ifTrue: [(self node: 'is-active' in: raw) at: 'after' put: #('set-mode')].
  kind = 'backward' ifTrue: [(self node: 'events' in: raw) at: 'after' put: #('random')].
  kind = 'scope' ifTrue: [(self node: 'quantity' in: raw) at: 'inputs' put: #('is-active' 'one')].
  kind = 'void' ifTrue: [(self node: 'is-active' in: raw) at: 'inputs' put: #('request' 'active')].
  self should: [CSModelBundle fromSnapshot: raw] raise: CSKernelError].
 raw := self conditionalModel snapshot. node := self node: 'events' in: raw.
 node at: 'after' put: #('events').
 self should: [CSModelBundle fromSnapshot: raw] raise: CSKernelError
]

{ #category : 'tests' }
CSGraphExamples >> testOperationValidation [
 | raw model report expected |
 #('version' 'unknown' 'input' 'parameter' 'stage' 'scope' 'field' 'budget' 'events' 'duplicate-effect') do: [:kind |
  raw := self conditionalModel snapshot. expected := nil.
  kind = 'version' ifTrue: [(self node: 'move' in: raw) at: 'version' put: 2. expected := 'unsupported-version'].
  kind = 'unknown' ifTrue: [(self node: 'move' in: raw) at: 'operation' put: 'future.move'. expected := 'unsupported-operation'].
  kind = 'input' ifTrue: [(self node: 'move' in: raw) at: 'inputs' put: #('quantity'). expected := 'input-type'].
  kind = 'parameter' ifTrue: [(self node: 'velocity' in: raw) at: 'parameters' put: (Dictionary new at: 'value' put: 1; yourself). expected := 'parameter-type'].
  kind = 'stage' ifTrue: [(self node: 'move' in: raw) at: 'stage' put: 'resolve'. expected := 'stage-mismatch'].
  kind = 'scope' ifTrue: [(self node: 'move' in: raw) at: 'scope' put: 'world'. expected := 'scope-mismatch'].
  kind = 'field' ifTrue: [(self node: 'mode-read' in: raw) at: 'parameters' put: (Dictionary new at: 'field' put: 'arbitrary'; yourself). expected := 'output-type'].
  kind = 'budget' ifTrue: [raw sixth at: 'maxNodeEvaluations' put: 1. expected := 'evaluation-budget'].
  kind = 'events' ifTrue: [raw sixth at: 'nodes' put: ((raw sixth at: 'nodes') reject: [:n | (n at: 'id') = 'events']). expected := 'event-drain'].
  kind = 'duplicate-effect' ifTrue: [| extra |
   extra := CSCanonicalCodec copy: (self node: 'move' in: raw). extra at: 'id' put: 'move-again'.
   raw sixth at: 'nodes' put: (raw sixth at: 'nodes'), {extra}. expected := 'duplicate-effect'].
  model := CSModelBundle fromSnapshot: raw.
  report := model compatibilityReportFor: CSOperationRegistry portable.
  self assert: ((report at: 'issues') anySatisfy: [:issue | (issue at: 'code') = expected]).
  self should: [CSSmalltalkBackend model: model seed: 0] raise: CSKernelError]
]

{ #category : 'tests' }
CSGraphExamples >> testRegistryAndBuilderIsolation [
 | registry snapshot builder value first changed |
 registry := CSOperationRegistry portable. snapshot := registry snapshot.
 (snapshot at: 'core.constant') at: 1 put: 2.
 self assert: (registry snapshot at: 'core.constant') first equals: 1.
 self assert: registry digest equals: CSOperationRegistry portable digest.
 self should: [CSOperationRegistry supporting: #('unregistered.op')] raise: CSKernelError.
 builder := self builderFor: self probeModel named: 'authoring-isolation'.
 value := #(1 2 3) copy.
 self constant: 'vector' value: value type: 'vec3' in: builder stage: 'decide'.
 first := builder build. value at: 1 put: 99.
 changed := builder build.
 self assert: first digest equals: changed digest.
 builder tickMilliseconds: 200.
 self deny: first digest = builder build digest
]

{ #category : 'portable graph' }
CSGraphExamples >> testRetainedValueByteBudget [
 | model report |
 model := self valueBudgetModel.
 report := model compatibilityReportFor: CSOperationRegistry portable.
 self deny: (report at: 'compatible').
 self assert: ((report at: 'issues') first at: 'code') equals: 'value-budget'.
 self should: [CSSmalltalkBackend model: model seed: 0] raise: CSKernelError
]

{ #category : 'tests' }
CSGraphExamples >> testSha256KnownAnswers [
 self assert: (CSSha256 hexDigestOf: '') equals: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'.
 self assert: (CSSha256 hexDigestOf: 'abc') equals: 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'.
 self assert: (CSSha256 hexDigestOf: 'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq') equals: '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1'
]

{ #category : 'tests' }
CSGraphExamples >> testStageReadsRemainImmutable [
 | builder backend entity |
 builder := self builderFor: self conditionalModel named: 'stage-read-probe'.
 self constant: 'marker' value: 'stage-start-observed' type: 'string' in: builder stage: 'decide'.
 builder node: 'mode-after' operation: 'core.entity.field' stage: 'decide' scope: 'entity' type: 'string' inputs: #() after: #('set-mode') parameters: (Dictionary new at: 'field' put: 'mode'; yourself).
 builder node: 'old-active' operation: 'core.string.equal' stage: 'decide' scope: 'entity' type: 'bool' inputs: #('mode-after' 'active') after: #() parameters: Dictionary new.
 builder node: 'stage-check' operation: 'core.mode.set' stage: 'decide' scope: 'entity' type: 'void' inputs: #('old-active' 'marker') after: #('set-mode') parameters: Dictionary new.
 backend := self worldFor: builder build. backend advanceThrough: 2.
 entity := (backend snapshot at: 'entities') at: (CSKernelExamples new id: 1).
 self assert: entity sixth equals: 'stage-start-observed'
]

{ #category : 'tests' }
CSGraphExamples >> testStructuralBudgets [
 | raw enabled |
 raw := self probeModel snapshot. enabled := self node: 'enabled' in: raw.
 raw sixth at: 'nodes' put: ((1 to: 129) collect: [:i | | node |
  node := CSCanonicalCodec copy: enabled. node at: 'id' put: 'n', i printString. node]) asArray.
 self should: [CSModelBundle fromSnapshot: raw] raise: CSKernelError.
 raw := self probeModel snapshot. (self node: 'move' in: raw) at: 'inputs' put: (Array new: 33 withAll: 'enabled').
 self should: [CSModelBundle fromSnapshot: raw] raise: CSKernelError.
 raw := self probeModel snapshot. raw sixth at: 'maxNodeEvaluations' put: 0.
 self should: [CSModelBundle fromSnapshot: raw] raise: CSKernelError
]

{ #category : 'tests' }
CSGraphExamples >> testTypedExpressionsDriveEffects [
 | backend entity |
 backend := self worldFor: self expressionModel.
 backend advanceThrough: 2.
 entity := (backend snapshot at: 'entities') at: (CSKernelExamples new id: 1).
 self assert: entity sixth equals: 'active'.
 self assert: (backend snapshot at: 'resources') values asArray equals: #(3).
 backend advanceThrough: 6.
 entity := (backend snapshot at: 'entities') at: (CSKernelExamples new id: 1).
 self assert: entity sixth equals: 'running'.
 self assert: entity second equals: #(4 -1 0).
 self assert: (backend snapshot at: 'resources') values asArray equals: #(1)
]

{ #category : 'portable graph' }
CSGraphExamples >> valueBudgetModel [
 | builder |
 builder := self builderFor: self probeModel named: 'value-budget-probe'.
 #('large-a' 'large-b') do: [:id |
  builder node: id operation: 'core.constant' stage: 'decide' scope: 'entity' type: 'string' inputs: #() after: #() parameters: (Dictionary new at: 'value' put: (String new: 4096 withAll: $a); yourself)].
 ^ builder build
]

{ #category : 'tests' }
CSGraphExamples >> worldFor: model [
 | backend |
 backend := CSSmalltalkBackend model: model seed: 42.
 backend addResource: 'charge' quantity: 3.
 #(2 1) do: [:i |
  backend addEntity: (CSKernelExamples new id: i) position: #(0 0 0) velocity: #(3 -3 0)].
 backend schedule: (CSKernelExamples new id: 8) at: 2 entity: (CSKernelExamples new id: 1) mode: 'active'.
 ^ backend
]
