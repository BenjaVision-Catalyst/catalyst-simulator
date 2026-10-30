Class {
	#name : 'CSShardedExecutionGroup',
	#superclass : 'CSExecutionGroup',
	#instVars : [
		'artifacts'
	],
	#category : 'BVC-Simulator-Authority',
	#package : 'BVC-Simulator-Authority'
}

{ #category : 'sharded authority' }
CSShardedExecutionGroup class >> create: request principal: principal retention: limit artifacts: store [
 ^ self new artifacts: store; initializeRequest: request principal: principal retention: limit
]

{ #category : 'sharded authority' }
CSShardedExecutionGroup >> acceptRoot: payload candidate: candidate [
 | pending root before after |
 pending := candidate at: 'pending'.
 CSAuthorityChecks require: (pending notNil and: [(payload at: 'batch') = (pending at: 'batch') and: [(payload at: 'inputDigest') = (pending at: 'inputDigest')]]) code: 'wrong-batch'.
 root := payload at: 'root'. artifacts assertHash: root.
 CSAuthorityChecks require: (pending at: 'resultRoot' ifAbsent: [root]) = root code: 'result-root-changed'.
 before := artifacts objectAt: (candidate at: 'checkpoint').
 after := artifacts validateCheckpoint: root base: (candidate at: 'checkpoint').
 CSAuthorityChecks require: ((after at: 'tick') = (pending at: 'targetTick') and: [(after at: 'modelDigest') = (candidate at: 'modelDigest') and: [(after at: 'seed') = (before at: 'seed')]]) code: 'invalid-result-frontier'.
 self updateRoot: root candidate: candidate.
 candidate at: 'pending' put: nil; at: 'phase' put: 'active'
]

{ #category : 'sharded authority' }
CSShardedExecutionGroup >> artifacts [
 ^ artifacts
]

{ #category : 'sharded authority' }
CSShardedExecutionGroup >> artifacts: store [
 artifacts := store
]

{ #category : 'typed population' }
CSShardedExecutionGroup >> backendAt: root [
 | node model |
 node := artifacts objectAt: root. model := CSModelBundle fromSnapshot: (artifacts valueAt: (node at: 'model')).
 model isTyped ifTrue: [^ artifacts typedBackendAt: root].
 ^ CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: (artifacts materialize: root))
]

{ #category : 'columnar transport' }
CSShardedExecutionGroup >> change: kind payload: payload request: request candidate: candidate maxSteps: maximum [
 | node pending target model backend root roots |
 node := artifacts objectAt: (candidate at: 'checkpoint').
 ((#('advance' 'command' 'prepare') includes: kind) and: [(candidate at: 'pending') isNil and: [artifacts count > 49152]]) ifTrue: [self collectIdleArtifacts: candidate].
 kind = 'stage' ifTrue: [
  CSAuthorityChecks keys: payload exactly: ((payload includesKey: 'frame') ifTrue: [#('batch' 'inputDigest' 'root' 'frame')] ifFalse: [#('batch' 'inputDigest' 'root' 'objects')]).
  pending := candidate at: 'pending'.
  CSAuthorityChecks require: (pending notNil and: [(pending at: 'phase') = 'uncertain' and: [#('active' 'reconciling') includes: (candidate at: 'phase')]]) code: 'batch-unresolved'.
  CSAuthorityChecks require: ((pending at: 'batch') = (payload at: 'batch') and: [(pending at: 'inputDigest') = (payload at: 'inputDigest')]) code: 'wrong-batch'.
  artifacts assertHash: (payload at: 'root').
  CSAuthorityChecks require: (pending at: 'resultRoot' ifAbsent: [payload at: 'root']) = (payload at: 'root') code: 'result-root-changed'.
  (payload includesKey: 'frame')
   ifTrue: [self stageColumnar: payload candidate: candidate]
   ifFalse: [artifacts upload: (payload at: 'objects')].
  artifacts cacheComplete: (payload at: 'root'). pending at: 'resultRoot' put: (payload at: 'root'). ^ self].
 kind = 'collect' ifTrue: [
  self requireIdle: candidate. CSAuthorityChecks require: payload isNil code: 'invalid-collection'.
  roots := Set with: (candidate at: 'checkpoint').
  (candidate at: 'projections') do: [:entry | roots add: (entry at: 'baseRoot'); add: (entry at: 'root')].
  artifacts collectKeeping: roots asArray. ^ self].
 (#('advance' 'command') includes: kind) ifTrue: [
  self requireIdle: candidate. CSAuthorityChecks require: (candidate at: 'backend') = 'smalltalk' code: 'wrong-backend'.
  backend := self backendAt: (candidate at: 'checkpoint').
  kind = 'advance' ifTrue: [backend advanceThrough: (self target: payload backend: backend maximum: maximum)]
   ifFalse: [self applyCommands: payload to: backend].
  root := artifacts checkpoint: backend snapshot.
  artifacts validateCheckpoint: root base: (candidate at: 'checkpoint').
  self updateRoot: root candidate: candidate. ^ self].
 kind = 'prepare' ifTrue: [
  self requireIdle: candidate. CSAuthorityChecks require: (candidate at: 'backend') = 'external' code: 'wrong-backend'.
  CSAuthorityChecks keys: payload exactly: #('targetTick').
  target := payload at: 'targetTick'. CSKernelMath nonnegative: target.
  CSAuthorityChecks require: (target > (node at: 'tick') and: [target - (node at: 'tick') <= maximum and: [maximum between: 1 and: 64]]) code: 'advance-budget'.
  root := CSSha256 hexDigestOf: 'CatalystSimulation-Batch-1:', (CSCanonicalCodec encode: {(candidate at: 'world'). (candidate at: 'group'). (candidate at: 'generation'). (candidate at: 'owner'). (candidate at: 'revision'). (candidate at: 'checkpoint'). target}).
  candidate at: 'pending' put: (Dictionary new at: 'batch' put: root; at: 'inputDigest' put: root; at: 'phase' put: 'prepared';
   at: 'generation' put: (candidate at: 'generation'); at: 'owner' put: (candidate at: 'owner'); at: 'inputRevision' put: (candidate at: 'revision');
   at: 'fromTick' put: (node at: 'tick'); at: 'targetTick' put: target; yourself). ^ self].
 kind = 'dispatch' ifTrue: [
  CSAuthorityChecks keys: payload exactly: #('batch' 'inputDigest'). pending := candidate at: 'pending'.
  CSAuthorityChecks require: (pending notNil and: [(candidate at: 'phase') = 'active' and: [(pending at: 'generation') = (candidate at: 'generation')]]) code: 'batch-unresolved'.
  CSAuthorityChecks require: ((pending at: 'phase') = 'prepared' and: [(pending at: 'batch') = (payload at: 'batch') and: [(pending at: 'inputDigest') = (payload at: 'inputDigest')]]) code: 'dispatch-already-uncertain'.
  pending at: 'phase' put: 'uncertain'. ^ self].
 kind = 'result' ifTrue: [
  CSAuthorityChecks keys: payload exactly: #('batch' 'inputDigest' 'root'). pending := candidate at: 'pending'.
  CSAuthorityChecks require: (pending notNil and: [(candidate at: 'phase') = 'active' and: [(pending at: 'phase') = 'uncertain' and: [(pending at: 'generation') = (candidate at: 'generation')]]]) code: 'obsolete-result'.
  self acceptRoot: payload candidate: candidate. ^ self].
 (#('transfer' 'recover') includes: kind) ifTrue: [
  kind = 'transfer' ifTrue: [self requireIdle: candidate. CSAuthorityChecks keys: payload exactly: #('backend' 'owner' 'operations')]
   ifFalse: [CSAuthorityChecks keys: payload exactly: #('backend' 'owner' 'operations' 'reason'). CSAuthorityChecks text: (payload at: 'reason')].
  model := CSModelBundle fromSnapshot: (artifacts valueAt: (node at: 'model')).
  CSAuthorityChecks placement: payload model: model.
  CSAuthorityChecks require: (payload at: 'owner') ~= (candidate at: 'owner') code: 'owner-token-must-change'.
  (candidate at: 'pending') ifNotNil: [CSAuthorityChecks require: (payload at: 'backend') = (candidate at: 'backend') code: 'reconcile-before-switch'].
  (payload at: 'backend') = 'smalltalk' ifTrue: [self backendAt: (candidate at: 'checkpoint')].
  candidate at: 'placement' put: (kind = 'transfer' ifTrue: [Dictionary new at: 'previousBackend' put: (candidate at: 'backend'); at: 'previousOwner' put: (candidate at: 'owner'); at: 'sourceDigest' put: (candidate at: 'checkpoint'); yourself] ifFalse: [nil]);
   at: 'backend' put: (payload at: 'backend'); at: 'owner' put: (payload at: 'owner');
   at: 'generation' put: (candidate at: 'generation') + 1;
   at: 'phase' put: (kind = 'transfer' ifTrue: ['handover'] ifFalse: [(candidate at: 'pending') ifNil: ['active'] ifNotNil: ['reconciling']]). ^ self].
 kind = 'activate' ifTrue: [
  CSAuthorityChecks keys: payload exactly: #('checkpointDigest' 'modelDigest').
  CSAuthorityChecks require: ((candidate at: 'phase') = 'handover' and: [(payload at: 'checkpointDigest') = (candidate at: 'checkpoint') and: [(payload at: 'modelDigest') = (candidate at: 'modelDigest')]]) code: 'placement-not-ready'.
  candidate at: 'phase' put: 'active'; at: 'placement' put: nil. ^ self].
 kind = 'reconcile' ifTrue: [
  CSAuthorityChecks keys: payload exactly: #('decision' 'proof' 'batch' 'inputDigest' 'root').
  CSAuthorityChecks text: (payload at: 'proof').
  pending := candidate at: 'pending'.
  CSAuthorityChecks require: ((candidate at: 'phase') = 'reconciling' and: [pending notNil]) code: 'not-reconciling'.
  CSAuthorityChecks require: ((pending at: 'batch') = (payload at: 'batch') and: [(pending at: 'inputDigest') = (payload at: 'inputDigest')]) code: 'wrong-batch'.
  (payload at: 'decision') = 'confirmed-result' ifTrue: [self acceptRoot: payload candidate: candidate. ^ self].
  CSAuthorityChecks require: ((payload at: 'decision') = 'confirmed-absent' and: [(payload at: 'root') isNil]) code: 'invalid-reconciliation'.
  candidate at: 'pending' put: nil; at: 'phase' put: 'active'. ^ self].
 CSAuthorityError signal: 'unsupported-operation'
]

{ #category : 'typed scale' }
CSShardedExecutionGroup >> collectIdleArtifacts: candidate [
 | roots |
 self requireIdle: candidate. roots := Set with: (candidate at: 'checkpoint').
 (candidate at: 'projections') do: [:entry | roots add: (entry at: 'baseRoot'); add: (entry at: 'root')].
 ^ artifacts collectKeeping: roots asArray
]

{ #category : 'sharded authority' }
CSShardedExecutionGroup >> initializeRequest: supplied principal: principal retention: limit [
 | request payload node model |
 state ifNotNil: [CSAuthorityError signal: 'already-initialized'].
 request := CSAuthorityChecks request: supplied. payload := request at: 'payload'.
 CSAuthorityChecks require: ((request at: 'sequence') = 1 and: [(request at: 'expectedRevision') = 0 and: [(request at: 'generation') = 0 and: [(request at: 'owner') = '']]]) code: 'invalid-create-frontier'.
 CSAuthorityChecks keys: payload exactly: #('root' 'backend' 'owner' 'operations').
 node := artifacts validateCheckpoint: (payload at: 'root') base: nil.
 model := CSModelBundle fromSnapshot: (artifacts valueAt: (node at: 'model')).
 CSAuthorityChecks placement: payload model: model.
 CSAuthorityChecks require: (limit isInteger and: [limit between: 1 and: 64]) code: 'invalid-retention'.
 state := Dictionary new at: 'schemaVersion' put: 2; at: 'world' put: (request at: 'world'); at: 'group' put: (request at: 'group');
 at: 'checkpoint' put: (payload at: 'root'); at: 'modelDigest' put: model digest; at: 'revision' put: 1; at: 'dataRevision' put: 1;
 at: 'generation' put: 1; at: 'owner' put: (payload at: 'owner'); at: 'backend' put: (payload at: 'backend'); at: 'phase' put: 'active';
 at: 'sequence' put: 0; at: 'journal' put: OrderedCollection new; at: 'retention' put: limit; at: 'projections' put: OrderedCollection new;
 at: 'pending' put: nil; at: 'placement' put: nil; yourself.
 self record: 'createSharded' request: request principal: principal candidate: state. ^ self
]

{ #category : 'sharded authority' }
CSShardedExecutionGroup >> projection: argument [
 | root revision result node |
 CSAuthorityChecks keys: argument exactly: #('root' 'bucket' 'after' 'limit').
 root := argument at: 'root'. revision := self retainedRoot: root.
 (argument at: 'after') ifNotNil: [CSKernelMath identifier: (argument at: 'after')].
 result := artifacts projectionPage: root bucket: (argument at: 'bucket') after: (argument at: 'after') limit: (argument at: 'limit').
 node := artifacts objectAt: root.
 result at: 'world' put: (state at: 'world'); at: 'group' put: (state at: 'group'); at: 'root' put: root; at: 'revision' put: revision; at: 'tick' put: (node at: 'tick').
 ^ result
]

{ #category : 'sharded authority' }
CSShardedExecutionGroup >> projectionChangesAfter: revision [
 | history floor result |
 CSKernelMath nonnegative: revision.
 CSAuthorityChecks require: revision <= (state at: 'dataRevision') code: 'future-revision'.
 history := state at: 'projections'. floor := history isEmpty ifTrue: [state at: 'dataRevision'] ifFalse: [history first at: 'baseRevision'].
 result := Dictionary new at: 'world' put: (state at: 'world'); at: 'group' put: (state at: 'group');
 at: 'revision' put: (state at: 'dataRevision'); at: 'root' put: (state at: 'checkpoint'); at: 'resnapshot' put: revision < floor;
 at: 'changes' put: ((history select: [:entry | (entry at: 'revision') > revision]) asArray); yourself.
 ^ CSCanonicalCodec copy: result
]

{ #category : 'columnar transport' }
CSShardedExecutionGroup >> record: kind request: request principal: principal candidate: candidate [
 | input entry journal node |
 node := artifacts objectAt: (candidate at: 'checkpoint').
 input := CSCanonicalCodec copy: (request at: 'payload').
 (input isKindOf: Dictionary) ifTrue: [(input includesKey: 'objects') ifTrue: [input at: 'objects' put: ((input at: 'objects') collect: [:object | object at: 'hash'])]].
 (input isKindOf: Dictionary) ifTrue: [(input includesKey: 'frame') ifTrue: [| frame |
  frame := input at: 'frame'. input at: 'frame' put: (Dictionary new at: 'digest' put: (CSSha256 hexDigestOf: (CSCanonicalCodec encode: frame));
   at: 'cursor' put: (frame at: 'cursor'); at: 'next' put: (frame at: 'next'); at: 'total' put: (frame at: 'total'); yourself)]].
 entry := Dictionary new at: 'status' put: 'accepted'; at: 'kind' put: kind; at: 'id' put: (request at: 'id');
 at: 'sequence' put: (request at: 'sequence'); at: 'fingerprint' put: (self fingerprint: kind request: request principal: principal);
 at: 'world' put: (candidate at: 'world'); at: 'group' put: (candidate at: 'group'); at: 'modelDigest' put: (candidate at: 'modelDigest');
 at: 'revision' put: (candidate at: 'revision'); at: 'dataRevision' put: (candidate at: 'dataRevision'); at: 'generation' put: (candidate at: 'generation');
 at: 'owner' put: (candidate at: 'owner'); at: 'tick' put: (node at: 'tick'); at: 'backend' put: (candidate at: 'backend');
 at: 'checkpointDigest' put: (candidate at: 'checkpoint'); at: 'principal' put: principal copy; at: 'input' put: input; yourself.
 journal := candidate at: 'journal'. journal add: entry.
 [journal size > (candidate at: 'retention')] whileTrue: [journal removeFirst].
 candidate at: 'sequence' put: (request at: 'sequence')
]

{ #category : 'sharded authority' }
CSShardedExecutionGroup >> retainedRoot: root [
 root = (state at: 'checkpoint') ifTrue: [^ state at: 'dataRevision'].
 (state at: 'projections') do: [:entry |
  root = (entry at: 'root') ifTrue: [^ entry at: 'revision'].
  root = (entry at: 'baseRoot') ifTrue: [^ entry at: 'baseRevision']].
 CSAuthorityError signal: 'accepted-view-expired-resnapshot'
]

{ #category : 'columnar transport' }
CSShardedExecutionGroup >> stageColumnar: payload candidate: candidate [
 | frame pending cursor total result |
 frame := payload at: 'frame'. pending := candidate at: 'pending'.
 CSAuthorityChecks require: (frame at: 'root') = (payload at: 'root') code: 'columnar-root'.
 cursor := pending at: 'columnarCursor' ifAbsent: [0].
 total := pending at: 'columnarTotal' ifAbsent: [frame at: 'total'].
 CSAuthorityChecks require: (frame at: 'total') = total code: 'columnar-plan-changed'.
 result := artifacts importColumnar: frame base: (candidate at: 'checkpoint') cursor: cursor.
 pending at: 'columnarCursor' put: (frame at: 'next'); at: 'columnarTotal' put: total;
  at: 'columnarComplete' put: (frame at: 'next') = total;
  at: 'columnarFrames' put: (pending at: 'columnarFrames' ifAbsent: [0]) + 1;
  at: 'columnarRows' put: (pending at: 'columnarRows' ifAbsent: [0]) + (result at: 'rows')
]

{ #category : 'sharded authority' }
CSShardedExecutionGroup >> updateRoot: root candidate: candidate [
 | before after oldIndex newIndex changed journal revision |
 before := artifacts objectAt: (candidate at: 'checkpoint'). after := artifacts objectAt: root.
 oldIndex := artifacts indexAt: (before at: 'projection'). newIndex := artifacts indexAt: (after at: 'projection').
 changed := (oldIndex keys asSet union: newIndex keys asSet) asArray sorted select: [:key | (oldIndex at: key ifAbsent: [nil]) ~= (newIndex at: key ifAbsent: [nil])].
 revision := (candidate at: 'revision') + 1.
 journal := (candidate at: 'projections') copy.
 journal add: (Dictionary new at: 'baseRevision' put: (candidate at: 'dataRevision'); at: 'revision' put: revision;
 at: 'baseRoot' put: (candidate at: 'checkpoint'); at: 'root' put: root; at: 'tick' put: (after at: 'tick'); at: 'changedBuckets' put: changed; yourself).
 [journal size > (candidate at: 'retention')] whileTrue: [journal removeFirst].
 candidate at: 'checkpoint' put: root; at: 'dataRevision' put: revision; at: 'projections' put: journal
]

{ #category : 'sharded authority' }
CSShardedExecutionGroup >> view [
 | view node |
 view := Dictionary new. node := artifacts objectAt: (state at: 'checkpoint').
 #('schemaVersion' 'world' 'group' 'modelDigest' 'revision' 'dataRevision' 'generation' 'owner' 'backend' 'phase' 'sequence' 'pending' 'placement') do: [:key | view at: key put: (CSCanonicalCodec copy: (state at: key))].
 view at: 'profile' put: 'checkpoint-1'; at: 'checkpointDigest' put: (state at: 'checkpoint'); at: 'retryFloor' put: self retryFloor;
 at: 'tick' put: (node at: 'tick'); at: 'seed' put: (node at: 'seed'); at: 'entityCount' put: (node at: 'entityCount'); at: 'projectionRoot' put: (node at: 'projection').
 ^ view
]
