Class {
	#name : 'CSAuthorityExamples',
	#superclass : 'TestCase',
	#category : 'BVC-Simulator-Tests-Authority',
	#package : 'BVC-Simulator-Tests-Authority'
}

{ #category : 'simulation authority' }
CSAuthorityExamples >> apply: kind group: group payload: payload [
 ^ group apply: kind request: (self requestFor: group id: kind, (group view at: 'sequence') printString payload: payload) principal: 'admin' maxSteps: 8
]

{ #category : 'tests' }
CSAuthorityExamples >> batchPayloadFor: group checkpoint: checkpoint [
 | pending |
 pending := group view at: 'pending'.
 ^ Dictionary new at: 'batch' put: (pending at: 'batch'); at: 'inputDigest' put: (pending at: 'inputDigest'); at: 'checkpoint' put: checkpoint; yourself
]

{ #category : 'simulation authority' }
CSAuthorityExamples >> checkpoint [
 ^ (CSGraphExamples new fixtureWorlds at: 'conditional-graph') snapshot
]

{ #category : 'simulation authority' }
CSAuthorityExamples >> createRequest [
 ^ Dictionary new at: 'world' put: (self id: 1); at: 'group' put: (self id: 2); at: 'sequence' put: 1; at: 'id' put: 'create';
 at: 'expectedRevision' put: 0; at: 'generation' put: 0; at: 'owner' put: '';
 at: 'payload' put: (Dictionary new at: 'checkpoint' put: self checkpoint; at: 'backend' put: 'smalltalk'; at: 'owner' put: (self id: 3);
 at: 'operations' put: CSOperationRegistry portable snapshot keys asArray sorted; yourself); yourself
]

{ #category : 'tests' }
CSAuthorityExamples >> dispatch: group [
 | pending |
 pending := group view at: 'pending'.
 self apply: 'dispatch' group: group payload: (Dictionary new at: 'batch' put: (pending at: 'batch'); at: 'inputDigest' put: (pending at: 'inputDigest'); yourself)
]

{ #category : 'simulation authority' }
CSAuthorityExamples >> externalGroup [
 | group view |
 group := self group. self apply: 'transfer' group: group payload: (self placement: 'external' owner: 4).
 view := group view.
 self apply: 'activate' group: group payload: (Dictionary new at: 'checkpointDigest' put: (view at: 'checkpointDigest'); at: 'modelDigest' put: (view at: 'modelDigest'); yourself).
 ^ group
]

{ #category : 'simulation authority' }
CSAuthorityExamples >> group [
 ^ CSExecutionGroup create: self createRequest principal: 'admin' retention: 4
]

{ #category : 'simulation authority' }
CSAuthorityExamples >> id: digit [
 ^ (String new: 31 withAll: $0), digit asString
]

{ #category : 'simulation authority' }
CSAuthorityExamples >> placement: kind owner: digit [
 ^ Dictionary new at: 'backend' put: kind; at: 'owner' put: (self id: digit); at: 'operations' put: CSOperationRegistry portable snapshot keys asArray sorted; yourself
]

{ #category : 'simulation authority' }
CSAuthorityExamples >> requestFor: group id: identifier payload: payload [
 | view |
 view := group view.
 ^ Dictionary new at: 'world' put: (view at: 'world'); at: 'group' put: (view at: 'group'); at: 'sequence' put: (view at: 'sequence') + 1;
 at: 'id' put: identifier; at: 'expectedRevision' put: (view at: 'revision'); at: 'generation' put: (view at: 'generation');
 at: 'owner' put: (view at: 'owner'); at: 'payload' put: payload; yourself
]

{ #category : 'simulation authority' }
CSAuthorityExamples >> target: tick [
 ^ Dictionary new at: 'targetTick' put: tick; yourself
]

{ #category : 'tests' }
CSAuthorityExamples >> testCatalogueBoundsIdentityAndPolicy [
 <gtExample>
 | repository first second |
 CSSimulationRepository removeNamed: 'authority-example'.
 [repository := CSSimulationRepository ensureNamed: 'authority-example' maximumGroups: 1 retention: 4.
 first := self createRequest. repository create: first principal: 'admin'.
 self assert: (repository create: first principal: 'admin') equals: ((repository groupFor: first) receiptAt: 1).
 second := self createRequest. second at: 'group' put: (self id: 9).
 self should: [repository create: second principal: 'admin'] raise: CSAuthorityError.
 self should: [CSSimulationRepository ensureNamed: 'authority-example' maximumGroups: 2 retention: 4] raise: CSAuthorityError.
 self assert: repository views size equals: 1]
 ensure: [CSSimulationRepository removeNamed: 'authority-example']
]

{ #category : 'tests' }
CSAuthorityExamples >> testDuplicateRetryRequiresExactPrincipalAndPayload [
 <gtExample>
 | group request altered receipt before |
 group := self group. request := self requestFor: group id: 'once' payload: (self target: 1).
 receipt := group apply: 'advance' request: request principal: 'admin' maxSteps: 8. before := group view.
 self assert: (group apply: 'advance' request: request principal: 'admin' maxSteps: 8) equals: receipt.
 self should: [group apply: 'advance' request: request principal: 'other' maxSteps: 8] raise: CSAuthorityError.
 altered := CSCanonicalCodec copy: request. altered at: 'payload' put: (self target: 2).
 self should: [group apply: 'advance' request: altered principal: 'admin' maxSteps: 8] raise: CSAuthorityError.
 self assert: group view equals: before
]

{ #category : 'tests' }
CSAuthorityExamples >> testExternalBatchAcceptsOnlyReservedMatchingResult [
 <gtExample>
 | group before backend payload malformed |
 group := self externalGroup. before := group view.
 self apply: 'prepare' group: group payload: (self target: 4).
 self assert: (group recoveryPlan at: 'action') equals: 'reserve-dispatch'.
 backend := CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: (before at: 'checkpoint')). backend advanceThrough: 4.
 payload := self batchPayloadFor: group checkpoint: backend snapshot.
 self should: [self apply: 'result' group: group payload: payload] raise: CSAuthorityError.
 self dispatch: group.
 self assert: (group recoveryPlan at: 'action') equals: 'query-result'.
 self deny: (group recoveryPlan at: 'automaticReplay').
 malformed := CSCanonicalCodec copy: payload. malformed at: 'inputDigest' put: 'wrong'.
 self should: [self apply: 'result' group: group payload: malformed] raise: CSAuthorityError.
 self should: [self apply: 'prepare' group: group payload: (self target: 6)] raise: CSAuthorityError.
 self apply: 'result' group: group payload: payload.
 self assert: (group view at: 'checkpoint') equals: backend snapshot.
 self assert: (group view at: 'pending') isNil.
 self assert: (group view at: 'backend') equals: 'external'
]

{ #category : 'tests' }
CSAuthorityExamples >> testExternalResultChecksModelSeedAndTarget [
 <gtExample>
 | group backend payload before |
 group := self externalGroup. self apply: 'prepare' group: group payload: (self target: 4). self dispatch: group.
 before := group view. backend := CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: (before at: 'checkpoint')). backend advanceThrough: 3.
 payload := self batchPayloadFor: group checkpoint: backend snapshot.
 self should: [self apply: 'result' group: group payload: payload] raise: CSAuthorityError.
 backend advance. payload := self batchPayloadFor: group checkpoint: backend snapshot.
 (payload at: 'checkpoint') at: 'seed' put: 99.
 self should: [self apply: 'result' group: group payload: payload] raise: CSAuthorityError.
 self assert: group view equals: before
]

{ #category : 'simulation authority' }
CSAuthorityExamples >> testLocalAcceptedRevisionAndIsolation [
 <gtExample>
 | group request receipt expected view |
 group := self group. request := self requestFor: group id: 'advance' payload: (self target: 6).
 receipt := group apply: 'advance' request: request principal: 'admin' maxSteps: 8.
 expected := CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: self checkpoint). expected advanceThrough: 6.
 self assert: (group view at: 'checkpoint') equals: expected snapshot.
 self assert: (receipt at: 'revision') equals: 2.
 view := group view. ((view at: 'checkpoint') at: 'entities') removeAll.
 self assert: (group view at: 'checkpoint') equals: expected snapshot.
 self assert: (group apply: 'advance' request: request principal: 'admin' maxSteps: 8) equals: receipt.
 self assert: (group view at: 'revision') equals: 2
]

{ #category : 'tests' }
CSAuthorityExamples >> testPlacementPreflightAndHandoverFenceOldOwner [
 <gtExample>
 | group stale bad before view payload |
 group := self group.
 stale := self requestFor: group id: 'old-owner' payload: (self target: 1).
 before := group view. bad := self placement: 'external' owner: 4.
 bad at: 'operations' put: #('core.constant').
 self should: [self apply: 'transfer' group: group payload: bad] raise: CSAuthorityError.
 self assert: group view equals: before.
 self apply: 'transfer' group: group payload: (self placement: 'external' owner: 4).
 view := group view.
 self assert: (view at: 'generation') equals: 2. self assert: (view at: 'phase') equals: 'handover'.
 stale at: 'expectedRevision' put: (view at: 'revision'); at: 'sequence' put: (view at: 'sequence') + 1.
 self should: [group apply: 'advance' request: stale principal: 'admin' maxSteps: 8] raise: CSAuthorityError.
 payload := Dictionary new at: 'modelDigest' put: (view at: 'modelDigest'); at: 'checkpointDigest' put: (String new: 64 withAll: $0); yourself.
 self should: [self apply: 'activate' group: group payload: payload] raise: CSAuthorityError.
 payload at: 'checkpointDigest' put: (view at: 'checkpointDigest').
 self apply: 'activate' group: group payload: payload.
 self assert: (group view at: 'phase') equals: 'active'.
 self assert: (group view at: 'checkpoint') equals: (before at: 'checkpoint').
 self should: [self apply: 'advance' group: group payload: (self target: 1)] raise: CSAuthorityError
]

{ #category : 'tests' }
CSAuthorityExamples >> testRecoveryConfirmedAbsentRequiresProofAndDoesNotAdvance [
 <gtExample>
 | group pending payload recovery before |
 group := self externalGroup. self apply: 'prepare' group: group payload: (self target: 4). self dispatch: group.
 before := group view. recovery := self placement: 'external' owner: 5. recovery at: 'reason' put: 'Reconcile restart'.
 self apply: 'recover' group: group payload: recovery.
 pending := group view at: 'pending'.
 payload := self batchPayloadFor: group checkpoint: nil.
 payload at: 'decision' put: 'confirmed-absent'; at: 'proof' put: ''.
 self should: [self apply: 'reconcile' group: group payload: payload] raise: CSAuthorityError.
 self assert: (group view at: 'pending') equals: pending.
 payload at: 'proof' put: 'Executor confirms no result and old process exited'.
 self apply: 'reconcile' group: group payload: payload.
 self assert: (group view at: 'checkpoint') equals: (before at: 'checkpoint').
 self assert: (group recoveryPlan at: 'action') equals: 'resume-frontier'
]

{ #category : 'tests' }
CSAuthorityExamples >> testRecoveryPreservesUncertainEvidenceAndFencesLateResult [
 <gtExample>
 | group backend late recovery before pending resolved |
 group := self externalGroup. self apply: 'prepare' group: group payload: (self target: 4). self dispatch: group.
 before := group view. pending := before at: 'pending'.
 backend := CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: (before at: 'checkpoint')). backend advanceThrough: 4.
 late := self requestFor: group id: 'late' payload: (self batchPayloadFor: group checkpoint: backend snapshot).
 recovery := self placement: 'external' owner: 5. recovery at: 'reason' put: 'Fresh owner after restart'.
 self apply: 'recover' group: group payload: recovery.
 self assert: (group view at: 'pending') equals: pending.
 self assert: (group recoveryPlan at: 'action') equals: 'review-fenced-batch'.
 late at: 'expectedRevision' put: (group view at: 'revision'); at: 'sequence' put: (group view at: 'sequence') + 1.
 self should: [group apply: 'result' request: late principal: 'admin' maxSteps: 8] raise: CSAuthorityError.
 self should: [self apply: 'prepare' group: group payload: (self target: 4)] raise: CSAuthorityError.
 resolved := self batchPayloadFor: group checkpoint: backend snapshot.
 resolved at: 'decision' put: 'confirmed-result'; at: 'proof' put: 'Executor queried by stable batch digest'.
 self apply: 'reconcile' group: group payload: resolved.
 self assert: (group view at: 'checkpoint') equals: backend snapshot.
 self assert: (group view at: 'generation') equals: 3.
 self assert: (group view at: 'pending') isNil
]

{ #category : 'tests' }
CSAuthorityExamples >> testRejectedCandidateDoesNotAdvanceOrKeepPartialCommands [
 <gtExample>
 | group before commands |
 group := self group. before := group view.
 commands := { {'schedule'. self id: 9. 5. self id: 1. 'later'}. {'request'. 'missing'. 1. self id: 1} }.
 self should: [self apply: 'command' group: group payload: commands] raise: CSKernelError.
 self assert: group view equals: before.
 self should: [self apply: 'advance' group: group payload: (self target: 100)] raise: CSAuthorityError.
 self assert: group view equals: before
]

{ #category : 'tests' }
CSAuthorityExamples >> testRetentionRejectsExpiredRetryAndSignalsSlowReaderGap [
 <gtExample>
 | group create |
 group := self group. create := self createRequest.
 1 to: 7 do: [:tick | self apply: 'advance' group: group payload: (self target: tick)].
 self assert: (group changesAfter: 0) keys asSet equals: #('revision' 'world' 'group' 'generation' 'resnapshot' 'changes') asSet.
 self assert: ((group changesAfter: 0) at: 'resnapshot').
 self assert: ((group changesAfter: 7) at: 'changes') size equals: 1.
 self assert: ((group receiptAt: 1) at: 'status') equals: 'expired'.
 self assert: ((group receiptAt: 99) at: 'status') equals: 'unknown'.
 self should: [group apply: 'create' request: create principal: 'admin' maxSteps: 8] raise: CSAuthorityError.
 self assert: (group view at: 'sequence') equals: 8.
 self assert: ((group changesAfter: 0) at: 'changes') size equals: 4
]

{ #category : 'tests' }
CSAuthorityExamples >> testRevisionGenerationAndIdentityChecks [
 <gtExample>
 | group request before |
 group := self group. before := group view.
 #('expectedRevision' 'generation' 'owner' 'world' 'sequence') do: [:key |
  request := self requestFor: group id: 'stale' payload: (self target: 1).
  request at: key put: ((#('world' 'owner') includes: key) ifTrue: [self id: 9] ifFalse: [99]).
  self should: [group apply: 'advance' request: request principal: 'admin' maxSteps: 8] raise: CSAuthorityError.
  self assert: group view equals: before]
]
