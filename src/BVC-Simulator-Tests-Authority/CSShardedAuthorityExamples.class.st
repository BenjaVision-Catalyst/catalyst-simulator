Class {
	#name : 'CSShardedAuthorityExamples',
	#superclass : 'TestCase',
	#category : 'BVC-Simulator-Tests-Authority',
	#package : 'BVC-Simulator-Tests-Authority'
}

{ #category : 'sharded tests' }
CSShardedAuthorityExamples >> externalGroup [
 | group helper view |
 group := self group. helper := CSAuthorityExamples new.
 helper apply: 'transfer' group: group payload: (helper placement: 'external' owner: 4).
 view := group view.
 helper apply: 'activate' group: group payload: (Dictionary new at: 'checkpointDigest' put: (view at: 'checkpointDigest'); at: 'modelDigest' put: (view at: 'modelDigest'); yourself).
 ^ group
]

{ #category : 'sharded tests' }
CSShardedAuthorityExamples >> group [
 | helper store request |
 helper := CSAuthorityExamples new. store := CSArtifactStore new.
 request := helper createRequest.
 request at: 'payload' put: ((helper placement: 'smalltalk' owner: 3) at: 'root' put: (store checkpoint: helper checkpoint); yourself).
 ^ CSShardedExecutionGroup create: request principal: 'admin' retention: 2 artifacts: store
]

{ #category : 'sharded tests' }
CSShardedAuthorityExamples >> payloadFor: group root: root [
 | pending |
 pending := group view at: 'pending'.
 ^ Dictionary new at: 'batch' put: (pending at: 'batch'); at: 'inputDigest' put: (pending at: 'inputDigest'); at: 'root' put: root; yourself
]

{ #category : 'sharded tests' }
CSShardedAuthorityExamples >> resultFor: group tick: tick [
 | source backend |
 source := CSArtifactStore new. backend := CSGraphExamples new fixtureWorlds at: 'conditional-graph'.
 backend advanceThrough: tick.
 ^ {source. source checkpoint: backend snapshot}
]

{ #category : 'sharded tests' }
CSShardedAuthorityExamples >> stage: result group: group [
 | helper missing pending payload |
 helper := CSAuthorityExamples new.
 [(missing := group artifacts missingFor: result second limit: 4) notEmpty] whileTrue: [
  pending := group view at: 'pending'.
  payload := Dictionary new at: 'batch' put: (pending at: 'batch'); at: 'inputDigest' put: (pending at: 'inputDigest');
   at: 'root' put: result second; at: 'objects' put: (result first objects: missing); yourself.
  helper apply: 'stage' group: group payload: payload]
]

{ #category : 'sharded tests' }
CSShardedAuthorityExamples >> testIncrementalAcceptIsAtomicWithoutMaterialization [
 <gtExample>
 | group helper before result payload |
 group := self externalGroup. helper := CSAuthorityExamples new. before := group view.
 helper apply: 'prepare' group: group payload: (helper target: 2). helper dispatch: group.
 result := self resultFor: group tick: 2. self stage: result group: group.
 self assert: (group view at: 'checkpointDigest') equals: (before at: 'checkpointDigest').
 self assert: (group view at: 'dataRevision') equals: 1.
 self assert: group artifacts materializations equals: 0.
 payload := self payloadFor: group root: result second.
 helper apply: 'result' group: group payload: payload.
 self assert: (group view at: 'tick') equals: 2.
 self assert: (group view at: 'dataRevision') equals: (group view at: 'revision').
 self assert: group artifacts materializations equals: 0.
 self assert: ((group projectionChangesAfter: 1) at: 'changes') size equals: 1
]

{ #category : 'sharded tests' }
CSShardedAuthorityExamples >> testPreparedRecoveryDoesNotAuthorizeStaging [
 <gtExample>
 | group helper result payload |
 group := self externalGroup. helper := CSAuthorityExamples new.
 helper apply: 'prepare' group: group payload: (helper target: 2).
 helper apply: 'recover' group: group payload: ((helper placement: 'external' owner: 5) at: 'reason' put: 'unconfirmed delivery'; yourself).
 result := self resultFor: group tick: 2. payload := self payloadFor: group root: result second.
 payload at: 'objects' put: (result first objects: {result second}).
 self should: [helper apply: 'stage' group: group payload: payload] raise: CSAuthorityError
]

{ #category : 'sharded tests' }
CSShardedAuthorityExamples >> testRecoveryPreservesStagingAndRejectsOldOwner [
 <gtExample>
 | group helper result prior request payload before |
 group := self externalGroup. helper := CSAuthorityExamples new.
 helper apply: 'prepare' group: group payload: (helper target: 2). helper dispatch: group.
 result := self resultFor: group tick: 2. self stage: result group: group. prior := group view.
 payload := self payloadFor: group root: result second.
 request := helper requestFor: group id: 'late' payload: payload.
 helper apply: 'recover' group: group payload: ((helper placement: 'external' owner: 5) at: 'reason' put: 'lost reply'; yourself).
 before := group view.
 self assert: (before at: 'pending') equals: (prior at: 'pending').
 request at: 'sequence' put: (before at: 'sequence') + 1; at: 'expectedRevision' put: (before at: 'revision').
 self should: [group apply: 'result' request: request principal: 'executor' maxSteps: 8] raise: CSAuthorityError.
 self assert: group view equals: before.
 payload at: 'decision' put: 'confirmed-result'; at: 'proof' put: 'queried immutable artifact receipt'.
 helper apply: 'reconcile' group: group payload: payload.
 self assert: (group view at: 'tick') equals: 2. self assert: group artifacts materializations equals: 0
]

{ #category : 'sharded tests' }
CSShardedAuthorityExamples >> testRetentionAndSafeArtifactCollection [
 <gtExample>
 | group helper original before payload |
 group := self group. helper := CSAuthorityExamples new. original := group view at: 'checkpointDigest'.
 1 to: 5 do: [:tick | helper apply: 'advance' group: group payload: (helper target: tick)].
 self assert: ((group projectionChangesAfter: 1) at: 'resnapshot').
 payload := Dictionary new at: 'root' put: original; at: 'bucket' put: '01'; at: 'after' put: nil; at: 'limit' put: 64; yourself.
 self should: [group projection: payload] raise: CSAuthorityError.
 before := group artifacts count. helper apply: 'collect' group: group payload: nil.
 self assert: group artifacts count < before.
 payload at: 'root' put: (group view at: 'checkpointDigest').
 self assert: (group projection: payload) notNil
]

{ #category : 'sharded tests' }
CSShardedAuthorityExamples >> testReturnToSmalltalkUsesAcceptedShards [
 <gtExample>
 | group helper result root view |
 group := self externalGroup. helper := CSAuthorityExamples new.
 helper apply: 'prepare' group: group payload: (helper target: 2). helper dispatch: group.
 result := self resultFor: group tick: 2. self stage: result group: group.
 helper apply: 'result' group: group payload: (self payloadFor: group root: result second). root := group view at: 'checkpointDigest'.
 helper apply: 'transfer' group: group payload: (helper placement: 'smalltalk' owner: 5).
 self assert: group artifacts materializations equals: 1. view := group view.
 self assert: (view at: 'checkpointDigest') equals: root.
 helper apply: 'activate' group: group payload: (Dictionary new at: 'checkpointDigest' put: root; at: 'modelDigest' put: (view at: 'modelDigest'); yourself).
 helper apply: 'advance' group: group payload: (helper target: 3).
 self assert: (group view at: 'tick') equals: 3
]
