Class {
	#name : 'CSShardedRepastDriver',
	#superclass : 'CSRepastResidentDriver',
	#instVars : [
		'remoteRoots'
	],
	#category : 'BVC-Simulator-Runtime',
	#package : 'BVC-Simulator-Runtime'
}

{ #category : 'sharded runtime' }
CSShardedRepastDriver >> artifactsFor: view [
 ^ ((CSSimulationRepository named: configuration repositoryName) groupFor: view) artifacts
]

{ #category : 'sharded runtime' }
CSShardedRepastDriver >> bindingFor: view [
 | pending binding |
 pending := view at: 'pending'.
 binding := Dictionary new at: 'version' put: 1; at: 'world' put: (view at: 'world'); at: 'group' put: (view at: 'group');
 at: 'generation' put: (pending ifNil: [view at: 'generation'] ifNotNil: [pending at: 'generation']);
 at: 'owner' put: (pending ifNil: [view at: 'owner'] ifNotNil: [pending at: 'owner']);
 at: 'modelDigest' put: (view at: 'modelDigest'); at: 'checkpointDigest' put: (view at: 'checkpointDigest');
 at: 'fromTick' put: (view at: 'tick'); at: 'targetTick' put: (pending ifNil: [view at: 'tick'] ifNotNil: [pending at: 'targetTick']); yourself.
 pending ifNil: [
  binding at: 'batch' put: (CSSha256 hexDigestOf: 'CatalystSimulation-Restore-1:', (CSCanonicalCodec encode: binding)); at: 'inputDigest' put: (view at: 'checkpointDigest')]
 ifNotNil: [binding at: 'batch' put: (pending at: 'batch'); at: 'inputDigest' put: (pending at: 'inputDigest')].
 ^ binding
]

{ #category : 'sharded runtime' }
CSShardedRepastDriver >> ensureRemote: view [
 | root observation missing objects |
 remoteRoots ifNil: [remoteRoots := Set new].
 root := view at: 'checkpointDigest'. (remoteRoots includes: root) ifTrue: [^ true].
 observation := transport invoke: (Dictionary new at: 'action' put: 'missing'; at: 'root' put: root; yourself) configuration: configuration.
 missing := observation at: 'missing'.
 missing isEmpty ifTrue: [remoteRoots add: root. ^ true].
 objects := (self artifactsFor: view) objects: missing.
 transport invoke: (Dictionary new at: 'action' put: 'putObjects'; at: 'objects' put: objects; yourself) configuration: configuration.
 ^ false
]

{ #category : 'sharded runtime' }
CSShardedRepastDriver >> nextFor: view [
 | pending observation payload root missing objects |
 CSAuthorityChecks require: (view at: 'schemaVersion') = 2 code: 'sharded-profile-required'.
 ((view at: 'backend') = 'smalltalk' and: [(view at: 'phase') = 'handover']) ifTrue: [
  observation := transport invoke: (self requestFor: view action: 'retire') configuration: configuration.
  (observation at: 'state') = 'retired' ifFalse: [^ nil].
  ^ self activationFor: view].
 pending := view at: 'pending'.
 ((view at: 'backend') = 'external' and: [(view at: 'phase') = 'active' and: [pending isNil]]) ifTrue: [
  (self ensureRemote: view) ifFalse: [^ nil].
  transport invoke: (self requestFor: view action: 'synchronize') configuration: configuration. ^ nil].
 (pending isNil and: [(view at: 'phase') ~= 'handover']) ifTrue: [^ nil].
 payload := pending ifNil: [nil] ifNotNil: [Dictionary new at: 'batch' put: (pending at: 'batch'); at: 'inputDigest' put: (pending at: 'inputDigest'); yourself].
 ((view at: 'phase') = 'active' and: [pending notNil and: [(pending at: 'phase') = 'prepared']]) ifTrue: [^ self transition: 'dispatch' payload: payload].
 (view at: 'phase') = 'reconciling' ifFalse: [(self ensureRemote: view) ifFalse: [^ nil]].
 observation := self observationFor: view.
 (observation at: 'state') = 'complete' ifFalse: [^ nil].
 CSAuthorityChecks require: (observation at: 'binding') = (self bindingFor: view) code: 'external-binding-mismatch'.
 root := observation at: 'root'. (self artifactsFor: view) assertHash: root.
 (view at: 'phase') = 'handover' ifTrue: [
  CSAuthorityChecks require: root = (view at: 'checkpointDigest') code: 'restore-mutated-checkpoint'.
  ^ self activationFor: view].
 missing := (self artifactsFor: view) missingFor: root limit: 4.
 missing notEmpty ifTrue: [
  objects := (transport invoke: (Dictionary new at: 'action' put: 'getObjects'; at: 'hashes' put: missing; yourself) configuration: configuration) at: 'objects'.
  CSAuthorityChecks require: (objects collect: [:object | object at: 'hash']) asSet = missing asSet code: 'artifact-fetch-mismatch'.
  payload at: 'root' put: root; at: 'objects' put: objects.
  ^ self transition: 'stage' payload: payload].
 remoteRoots ifNil: [remoteRoots := Set new]. remoteRoots add: root.
 payload at: 'root' put: root.
 (view at: 'phase') = 'reconciling' ifTrue: [
  payload at: 'decision' put: 'confirmed-result'; at: 'proof' put: 'sharded-receipt-', root.
  ^ self transition: 'reconcile' payload: payload].
 ^ self transition: 'result' payload: payload
]

{ #category : 'sharded runtime' }
CSShardedRepastDriver >> specificationFor: view [
 ^ Dictionary new at: 'binding' put: (self bindingFor: view); at: 'root' put: (view at: 'checkpointDigest'); yourself
]
