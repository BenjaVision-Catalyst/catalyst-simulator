"
Persistent optimistic write guard and accepted execution-group state. One copy-on-write state replacement is the GemStone conflict boundary. No executable activation or simulator process is retained.
"
Class {
	#name : 'CSExecutionGroup',
	#superclass : 'Object',
	#instVars : [
		'state'
	],
	#category : 'BVC-Simulator-Authority',
	#package : 'BVC-Simulator-Authority'
}

{ #category : 'simulation authority' }
CSExecutionGroup class >> create: request principal: principal retention: limit [
 ^ self new initializeRequest: request principal: principal retention: limit
]

{ #category : 'simulation authority' }
CSExecutionGroup >> acceptCheckpoint: payload candidate: candidate [
 | pending backend before |
 pending := candidate at: 'pending'.
 CSAuthorityChecks require: pending notNil code: 'no-pending-batch'.
 CSAuthorityChecks require: ((payload at: 'batch') = (pending at: 'batch') and: [(payload at: 'inputDigest') = (pending at: 'inputDigest')]) code: 'wrong-batch'.
 backend := CSAuthorityChecks checkpoint: (payload at: 'checkpoint').
 before := CSSmalltalkBackend fromCheckpoint: (candidate at: 'checkpoint').
 CSAuthorityChecks require: (backend model digest = (candidate at: 'modelDigest') and: [backend tick = (pending at: 'targetTick') and: [(backend snapshot at: 'seed') = (before snapshot at: 'seed')]]) code: 'invalid-result-frontier'.
 candidate at: 'checkpoint' put: backend checkpoint; at: 'pending' put: nil; at: 'phase' put: 'active'
]

{ #category : 'simulation authority' }
CSExecutionGroup >> apply: kind request: supplied principal: principal maxSteps: maximum [
 | request sequence prior candidate |
 request := CSAuthorityChecks request: supplied. sequence := request at: 'sequence'.
 ((request at: 'world') = (state at: 'world') and: [(request at: 'group') = (state at: 'group')]) ifFalse: [CSAuthorityError signal: 'wrong-group'].
 sequence <= (state at: 'sequence') ifTrue: [
  prior := self receiptAt: sequence.
  CSAuthorityChecks require: (prior at: 'status') ~= 'expired' code: 'retry-window-expired'.
  CSAuthorityChecks require: (prior at: 'fingerprint') = (self fingerprint: kind request: request principal: principal) code: 'sequence-reused'.
  ^ prior].
 CSAuthorityChecks require: sequence = ((state at: 'sequence') + 1) code: 'sequence-gap'.
 self checkFrontier: request.
 candidate := state copy.
 candidate at: 'journal' put: (state at: 'journal') copy.
 (candidate at: 'pending') ifNotNil: [candidate at: 'pending' put: (CSCanonicalCodec copy: (candidate at: 'pending'))].
 self change: kind payload: (request at: 'payload') request: request candidate: candidate maxSteps: maximum.
 candidate at: 'revision' put: (CSKernelMath nonnegative: (state at: 'revision') + 1).
 self record: kind request: request principal: principal candidate: candidate.
 state := candidate.
 ^ self receiptAt: sequence
]

{ #category : 'simulation authority' }
CSExecutionGroup >> applyCommands: commands to: backend [
 CSAuthorityChecks require: (commands class == Array and: [commands size between: 1 and: 64]) code: 'command-budget'.
 CSAuthorityChecks require: (CSCanonicalCodec encode: commands) size <= 8192 code: 'command-byte-limit'.
 commands do: [:command | | kind |
  CSAuthorityChecks require: (command class == Array and: [command notEmpty]) code: 'invalid-command'.
  kind := command first.
  (#('request' 'schedule' 'cancel') includes: kind) ifFalse: [CSAuthorityError signal: 'unsupported-command'].
  kind = 'request' ifTrue: [
   CSAuthorityChecks require: command size = 4 code: 'invalid-command'.
   backend requestResource: command second quantity: command third for: command fourth].
  kind = 'schedule' ifTrue: [
   CSAuthorityChecks require: command size = 5 code: 'invalid-command'.
   backend schedule: command second at: command third entity: command fourth mode: command fifth].
  kind = 'cancel' ifTrue: [
   CSAuthorityChecks require: command size = 2 code: 'invalid-command'. backend cancel: command second]]
]

{ #category : 'simulation authority' }
CSExecutionGroup >> change: kind payload: payload request: request candidate: candidate maxSteps: maximum [
 | backend target pending |
 backend := CSSmalltalkBackend fromCheckpoint: (candidate at: 'checkpoint').
 kind = 'command' ifTrue: [self requireIdle: candidate. self applyCommands: payload to: backend. candidate at: 'checkpoint' put: backend checkpoint. ^ self].
 kind = 'advance' ifTrue: [
  self requireIdle: candidate. CSAuthorityChecks require: (candidate at: 'backend') = 'smalltalk' code: 'wrong-backend'.
  target := self target: payload backend: backend maximum: maximum.
  backend advanceThrough: target. candidate at: 'checkpoint' put: backend checkpoint. ^ self].
 kind = 'prepare' ifTrue: [
  self requireIdle: candidate. CSAuthorityChecks require: (candidate at: 'backend') = 'external' code: 'wrong-backend'.
  target := self target: payload backend: backend maximum: maximum.
  pending := Dictionary new at: 'batch' put: (request at: 'id'); at: 'phase' put: 'prepared'; at: 'generation' put: (candidate at: 'generation');
   at: 'owner' put: (candidate at: 'owner'); at: 'inputRevision' put: (candidate at: 'revision'); at: 'fromTick' put: backend tick; at: 'targetTick' put: target;
   at: 'inputDigest' put: (CSSha256 hexDigestOf: 'CatalystSimulation-Batch-1:', (CSCanonicalCodec encode: {(candidate at: 'world'). (candidate at: 'group'). (candidate at: 'generation'). (candidate at: 'owner'). (candidate at: 'revision'). (CSSha256 hexDigestOf: backend checkpoint). target})); yourself.
  pending at: 'batch' put: (pending at: 'inputDigest'). candidate at: 'pending' put: pending. ^ self].
 kind = 'dispatch' ifTrue: [
  CSAuthorityChecks keys: payload exactly: #('batch' 'inputDigest').
  pending := candidate at: 'pending'.
  CSAuthorityChecks require: (pending notNil and: [(candidate at: 'phase') = 'active' and: [(pending at: 'generation') = (candidate at: 'generation')]]) code: 'batch-unresolved'.
  CSAuthorityChecks require: ((pending at: 'batch') = (payload at: 'batch') and: [(pending at: 'inputDigest') = (payload at: 'inputDigest') and: [(pending at: 'phase') = 'prepared']]) code: 'dispatch-already-uncertain'.
  pending at: 'phase' put: 'uncertain'. ^ self].
 kind = 'result' ifTrue: [
  CSAuthorityChecks keys: payload exactly: #('batch' 'inputDigest' 'checkpoint').
  pending := candidate at: 'pending'.
  CSAuthorityChecks require: (pending notNil and: [(candidate at: 'phase') = 'active' and: [(pending at: 'phase') = 'uncertain' and: [(pending at: 'generation') = (candidate at: 'generation')]]]) code: 'obsolete-result'.
  self acceptCheckpoint: payload candidate: candidate. ^ self].
 kind = 'transfer' ifTrue: [
  self requireIdle: candidate.
  CSAuthorityChecks keys: payload exactly: #('backend' 'owner' 'operations').
  CSAuthorityChecks placement: payload model: backend model.
  CSAuthorityChecks require: (payload at: 'owner') ~= (candidate at: 'owner') code: 'owner-token-must-change'.
  candidate at: 'placement' put: (Dictionary new at: 'previousBackend' put: (candidate at: 'backend'); at: 'previousOwner' put: (candidate at: 'owner'); at: 'sourceDigest' put: (CSSha256 hexDigestOf: backend checkpoint); yourself);
   at: 'backend' put: (payload at: 'backend'); at: 'owner' put: (payload at: 'owner'); at: 'phase' put: 'handover';
   at: 'generation' put: (CSKernelMath nonnegative: (candidate at: 'generation') + 1). ^ self].
 kind = 'activate' ifTrue: [
  CSAuthorityChecks keys: payload exactly: #('checkpointDigest' 'modelDigest').
  CSAuthorityChecks require: ((candidate at: 'phase') = 'handover' and: [(payload at: 'checkpointDigest') = (CSSha256 hexDigestOf: backend checkpoint) and: [(payload at: 'modelDigest') = backend model digest]]) code: 'placement-not-ready'.
  candidate at: 'phase' put: 'active'; at: 'placement' put: nil. ^ self].
 kind = 'recover' ifTrue: [
  CSAuthorityChecks keys: payload exactly: #('backend' 'owner' 'operations' 'reason').
  CSAuthorityChecks text: (payload at: 'reason').
  CSAuthorityChecks placement: payload model: backend model.
  CSAuthorityChecks require: (payload at: 'owner') ~= (candidate at: 'owner') code: 'owner-token-must-change'.
  (candidate at: 'pending') ifNotNil: [CSAuthorityChecks require: (candidate at: 'backend') = (payload at: 'backend') code: 'reconcile-before-switch'].
  candidate at: 'generation' put: (CSKernelMath nonnegative: (candidate at: 'generation') + 1);
   at: 'owner' put: (payload at: 'owner'); at: 'backend' put: (payload at: 'backend'); at: 'placement' put: nil;
   at: 'phase' put: ((candidate at: 'pending') ifNil: ['active'] ifNotNil: ['reconciling']). ^ self].
 kind = 'reconcile' ifTrue: [
  CSAuthorityChecks keys: payload exactly: #('decision' 'proof' 'batch' 'inputDigest' 'checkpoint').
  CSAuthorityChecks text: (payload at: 'proof').
  CSAuthorityChecks require: ((candidate at: 'phase') = 'reconciling' and: [(candidate at: 'pending') notNil]) code: 'not-reconciling'.
  pending := candidate at: 'pending'.
  CSAuthorityChecks require: ((payload at: 'batch') = (pending at: 'batch') and: [(payload at: 'inputDigest') = (pending at: 'inputDigest')]) code: 'wrong-batch'.
  (payload at: 'decision') = 'confirmed-result' ifTrue: [self acceptCheckpoint: payload candidate: candidate. ^ self].
  CSAuthorityChecks require: ((payload at: 'decision') = 'confirmed-absent' and: [(payload at: 'checkpoint') isNil]) code: 'invalid-reconciliation'.
  candidate at: 'pending' put: nil; at: 'phase' put: 'active'. ^ self].
 CSAuthorityError signal: 'unsupported-operation'
]

{ #category : 'simulation authority' }
CSExecutionGroup >> changesAfter: revision [
 | current result |
 CSKernelMath nonnegative: revision. current := state at: 'revision'.
 CSAuthorityChecks require: revision <= current code: 'future-revision'.
 result := Dictionary new at: 'revision' put: current; at: 'world' put: (state at: 'world'); at: 'group' put: (state at: 'group');
 at: 'generation' put: (state at: 'generation'); at: 'resnapshot' put: (revision < (((state at: 'journal') first at: 'revision') - 1));
 at: 'changes' put: ((state at: 'journal') select: [:entry | (entry at: 'revision') > revision]) asArray; yourself.
 ^ CSCanonicalCodec copy: result
]

{ #category : 'simulation authority' }
CSExecutionGroup >> checkFrontier: request [
 CSAuthorityChecks require: ((request at: 'world') = (state at: 'world') and: [(request at: 'group') = (state at: 'group')]) code: 'wrong-group'.
 CSAuthorityChecks require: (request at: 'expectedRevision') = (state at: 'revision') code: 'stale-revision'.
 CSAuthorityChecks require: ((request at: 'generation') = (state at: 'generation') and: [(request at: 'owner') = (state at: 'owner')]) code: 'obsolete-placement'
]

{ #category : 'simulation authority' }
CSExecutionGroup >> fingerprint: kind request: request principal: principal [
 ^ CSSha256 hexDigestOf: 'CatalystSimulation-Request-1:', (CSCanonicalCodec encode: {kind. principal. request})
]

{ #category : 'simulation authority' }
CSExecutionGroup >> initializeRequest: supplied principal: principal retention: limit [
 | request payload backend |
 state ifNotNil: [CSAuthorityError signal: 'already-initialized'].
 request := CSAuthorityChecks request: supplied. payload := request at: 'payload'.
 CSAuthorityChecks require: ((request at: 'sequence') = 1 and: [(request at: 'expectedRevision') = 0 and: [(request at: 'generation') = 0 and: [(request at: 'owner') = '']]]) code: 'invalid-create-frontier'.
 CSAuthorityChecks keys: payload exactly: #('checkpoint' 'backend' 'owner' 'operations').
 backend := CSAuthorityChecks checkpoint: (payload at: 'checkpoint').
 CSAuthorityChecks placement: payload model: backend model.
 CSAuthorityChecks require: (limit isInteger and: [limit between: 1 and: 64]) code: 'invalid-retention'.
 state := Dictionary new at: 'schemaVersion' put: 1; at: 'world' put: (request at: 'world'); at: 'group' put: (request at: 'group');
 at: 'checkpoint' put: backend checkpoint; at: 'modelDigest' put: backend model digest; at: 'revision' put: 1; at: 'generation' put: 1;
 at: 'owner' put: (payload at: 'owner'); at: 'backend' put: (payload at: 'backend'); at: 'phase' put: 'active';
 at: 'sequence' put: 0; at: 'journal' put: OrderedCollection new; at: 'retention' put: limit;
 at: 'pending' put: nil; at: 'placement' put: nil; yourself.
 self record: 'create' request: request principal: principal candidate: state.
 ^ self
]

{ #category : 'simulation authority' }
CSExecutionGroup >> receiptAt: sequence [
 | entry |
 CSKernelMath nonnegative: sequence.
 entry := (state at: 'journal') detect: [:each | (each at: 'sequence') = sequence] ifNone: [nil].
 entry ifNotNil: [^ CSCanonicalCodec copy: entry].
 ^ Dictionary new at: 'status' put: (sequence <= (state at: 'sequence') ifTrue: ['expired'] ifFalse: ['unknown']);
 at: 'sequence' put: sequence; at: 'retryFloor' put: self retryFloor; yourself
]

{ #category : 'simulation authority' }
CSExecutionGroup >> record: kind request: request principal: principal candidate: candidate [
 | entry input journal checkpoint |
 checkpoint := CSSmalltalkBackend fromCheckpoint: (candidate at: 'checkpoint').
 input := CSCanonicalCodec copy: (request at: 'payload').
 (input isKindOf: Dictionary) ifTrue: [(input includesKey: 'checkpoint') ifTrue: [input at: 'checkpoint' put: (CSSha256 hexDigestOf: (CSCanonicalCodec encode: (input at: 'checkpoint')))]].
 entry := Dictionary new at: 'status' put: 'accepted'; at: 'kind' put: kind; at: 'id' put: (request at: 'id');
 at: 'sequence' put: (request at: 'sequence'); at: 'fingerprint' put: (self fingerprint: kind request: request principal: principal);
 at: 'world' put: (candidate at: 'world'); at: 'group' put: (candidate at: 'group');
 at: 'modelDigest' put: (candidate at: 'modelDigest'); at: 'revision' put: (candidate at: 'revision'); at: 'generation' put: (candidate at: 'generation');
 at: 'owner' put: (candidate at: 'owner'); at: 'tick' put: checkpoint tick; at: 'backend' put: (candidate at: 'backend');
 at: 'checkpointDigest' put: (CSSha256 hexDigestOf: checkpoint checkpoint);
 at: 'principal' put: principal copy; at: 'input' put: input; yourself.
 journal := candidate at: 'journal'. journal add: entry.
 [journal size > (candidate at: 'retention')] whileTrue: [journal removeFirst].
 candidate at: 'sequence' put: (request at: 'sequence')
]

{ #category : 'simulation authority' }
CSExecutionGroup >> recoveryPlan [
 | pending action |
 pending := state at: 'pending'.
 action := pending
  ifNil: [(state at: 'phase') = 'handover' ifTrue: ['validate-placement'] ifFalse: ['resume-frontier']]
  ifNotNil: [(state at: 'phase') = 'reconciling' ifTrue: ['review-fenced-batch'] ifFalse: [(pending at: 'phase') = 'prepared' ifTrue: ['reserve-dispatch'] ifFalse: ['query-result']]].
 ^ Dictionary new at: 'action' put: action; at: 'automaticReplay' put: false; at: 'view' put: self view; yourself
]

{ #category : 'simulation authority' }
CSExecutionGroup >> requireIdle: candidate [
 CSAuthorityChecks require: (candidate at: 'phase') = 'active' code: 'placement-not-active'.
 CSAuthorityChecks require: (candidate at: 'pending') isNil code: 'batch-unresolved'
]

{ #category : 'simulation authority' }
CSExecutionGroup >> retryFloor [
 ^ (state at: 'sequence') - (state at: 'journal') size + 1
]

{ #category : 'simulation authority' }
CSExecutionGroup >> target: payload backend: backend maximum: maximum [
 | target |
 CSAuthorityChecks keys: payload exactly: #('targetTick').
 target := payload at: 'targetTick'. CSKernelMath nonnegative: target.
 CSAuthorityChecks require: (target > backend tick and: [target - backend tick <= maximum and: [maximum between: 1 and: 64]]) code: 'advance-budget'.
 ^ target
]

{ #category : 'simulation authority' }
CSExecutionGroup >> view [
 | view |
 view := Dictionary new.
 #('schemaVersion' 'world' 'group' 'modelDigest' 'revision' 'generation' 'owner' 'backend' 'phase' 'sequence' 'pending' 'placement') do: [:key | view at: key put: (CSCanonicalCodec copy: (state at: key))].
 view at: 'checkpoint' put: (CSCanonicalCodec decode: (state at: 'checkpoint')); at: 'checkpointDigest' put: (CSSha256 hexDigestOf: (state at: 'checkpoint'));
 at: 'retryFloor' put: self retryFloor.
 ^ view
]
