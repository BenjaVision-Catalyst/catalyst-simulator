"
Named persistent Simulation catalogues. Create and mutate only within Runtime-owned transactions on GemStone; the GT implementation is explicitly volatile.
"
Class {
	#name : 'CSSimulationRepository',
	#superclass : 'Object',
	#instVars : [
		'groups',
		'maximumGroups',
		'journalLimit',
		'imports'
	],
	#classVars : [
		'Repositories'
	],
	#category : 'BVC-Simulator-Authority',
	#package : 'BVC-Simulator-Authority'
}

{ #category : 'simulation authority' }
CSSimulationRepository class >> ensureNamed: repositoryName maximumGroups: count retention: limit [
 | repository |
 CSAuthorityChecks text: repositoryName.
 CSAuthorityChecks require: (count isInteger and: [count between: 1 and: 128]) code: 'invalid-group-limit'.
 CSAuthorityChecks require: (limit isInteger and: [limit between: 1 and: 64]) code: 'invalid-retention'.
 Repositories ifNil: [Repositories := Dictionary new].
 repository := Repositories at: repositoryName ifAbsent: [nil].
 repository ifNil: [repository := self new initializeMaximum: count retention: limit. Repositories at: repositoryName copy put: repository].
 CSAuthorityChecks require: (repository maximumGroups = count and: [repository journalLimit = limit]) code: 'repository-policy-mismatch'.
 ^ repository
]

{ #category : 'simulation authority' }
CSSimulationRepository class >> named: repositoryName [
 CSAuthorityChecks text: repositoryName.
 ^ Repositories ifNil: [nil] ifNotNil: [Repositories at: repositoryName ifAbsent: [nil]]
]

{ #category : 'simulation authority' }
CSSimulationRepository class >> removeNamed: repositoryName [
 Repositories ifNotNil: [Repositories removeKey: repositoryName ifAbsent: []]
]

{ #category : 'simulation authority' }
CSSimulationRepository >> create: request principal: principal [
 | key existing created |
 key := self keyFor: request. existing := groups at: key ifAbsent: [nil].
 existing ifNotNil: [^ existing apply: 'create' request: request principal: principal maxSteps: 1].
 CSAuthorityChecks require: groups size < maximumGroups code: 'group-capacity'.
 created := CSExecutionGroup create: request principal: principal retention: journalLimit.
 groups at: key put: created.
 ^ created receiptAt: 1
]

{ #category : 'sharded authority' }
CSSimulationRepository >> createSharded: request principal: principal [
 | key store existing created |
 key := self keyFor: request. existing := groups at: key ifAbsent: [nil].
 existing ifNotNil: [^ existing apply: 'createSharded' request: request principal: principal maxSteps: 1].
 CSAuthorityChecks require: groups size < maximumGroups code: 'group-capacity'.
 store := imports ifNil: [CSAuthorityError signal: 'import-unavailable'] ifNotNil: [imports at: key ifAbsent: [CSAuthorityError signal: 'import-unavailable']].
 created := CSShardedExecutionGroup create: request principal: principal retention: journalLimit artifacts: store.
 groups at: key put: created. imports removeKey: key.
 ^ created receiptAt: 1
]

{ #category : 'simulation authority' }
CSSimulationRepository >> groupFor: request [
 ^ groups at: (self keyFor: request) ifAbsent: [CSAuthorityError signal: 'unknown-group']
]

{ #category : 'simulation authority' }
CSSimulationRepository >> initializeMaximum: count retention: limit [
 groups := Dictionary new. maximumGroups := count. journalLimit := limit. ^ self
]

{ #category : 'simulation authority' }
CSSimulationRepository >> journalLimit [
 ^ journalLimit
]

{ #category : 'simulation authority' }
CSSimulationRepository >> keyFor: request [
 CSKernelMath identifier: (request at: 'world'). CSKernelMath identifier: (request at: 'group').
 ^ (request at: 'world'), '/', (request at: 'group')
]

{ #category : 'simulation authority' }
CSSimulationRepository >> maximumGroups [
 ^ maximumGroups
]

{ #category : 'sharded authority' }
CSSimulationRepository >> upload: request [
 | key store |
 CSAuthorityChecks keys: request exactly: #('world' 'group' 'objects').
 key := self keyFor: request.
 CSAuthorityChecks require: (groups includesKey: key) not code: 'use-fenced-stage-for-existing-group'.
 imports ifNil: [imports := Dictionary new].
 CSAuthorityChecks require: ((imports includesKey: key) or: [imports size + groups size < maximumGroups]) code: 'group-capacity'.
 store := imports at: key ifAbsentPut: [CSArtifactStore new].
 ^ store upload: (request at: 'objects')
]

{ #category : 'simulation authority' }
CSSimulationRepository >> views [
 ^ (groups keys asArray sorted collect: [:key | (groups at: key) view]) asArray
]
