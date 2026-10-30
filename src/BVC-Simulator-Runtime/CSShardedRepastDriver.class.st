Class {
	#name : 'CSShardedRepastDriver',
	#superclass : 'CSRepastResidentDriver',
	#instVars : [
		'remoteRoots',
		'remoteCursors',
		'columnarFallbacks'
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

{ #category : 'columnar transport' }
CSShardedRepastDriver >> canonicalFallbackFor: root [
 ^ columnarFallbacks notNil and: [columnarFallbacks includes: root]
]

{ #category : 'columnar transport' }
CSShardedRepastDriver >> ensureRemote: view [
 | root observation missing objects cursor frame |
 remoteRoots ifNil: [remoteRoots := Set new].
 root := view at: 'checkpointDigest'. (remoteRoots includes: root) ifTrue: [^ true].
 observation := transport invoke: (Dictionary new at: 'action' put: 'missing'; at: 'root' put: root; yourself) configuration: configuration.
 missing := observation at: 'missing'.
 missing isEmpty ifTrue: [remoteRoots add: root. ^ true].
 ((self typedView: view) and: [(self canonicalFallbackFor: root) not]) ifTrue: [
  remoteCursors ifNil: [remoteCursors := Dictionary new]. cursor := remoteCursors at: root ifAbsent: [0].
  frame := [CSColumnarCodec frame: root base: nil cursor: cursor store: (self artifactsFor: view)]
   on: CSAuthorityError do: [:error | error messageText = 'columnar-bucket-too-large' ifTrue: [nil] ifFalse: [error pass]].
  frame ifNil: [self fallbackToCanonical: root] ifNotNil: [
   observation := transport invoke: (Dictionary new at: 'action' put: 'putColumnar'; at: 'frame' put: frame; yourself) configuration: configuration.
   CSAuthorityChecks require: ((observation at: 'root') = root and: [(observation at: 'next') = (frame at: 'next') and: [(observation at: 'total') = (frame at: 'total')]]) code: 'columnar-offer-response'.
   remoteCursors at: root put: (frame at: 'next').
   (frame at: 'next') = (frame at: 'total') ifTrue: [remoteRoots add: root. remoteCursors removeKey: root]. ^ false]].
 objects := (self artifactsFor: view) boundedObjects: missing.
 transport invoke: (Dictionary new at: 'action' put: 'putObjects'; at: 'objects' put: objects; yourself) configuration: configuration.
 ^ false
]

{ #category : 'columnar transport' }
CSShardedRepastDriver >> fallbackToCanonical: root [
 columnarFallbacks ifNil: [columnarFallbacks := Set new]. columnarFallbacks add: root
]

{ #category : 'columnar transport' }
CSShardedRepastDriver >> nextFor: view [
 | pending observation payload root missing objects frame cursor |
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
 ((self typedView: view) and: [(self canonicalFallbackFor: root) not and: [(pending at: 'columnarComplete' ifAbsent: [false]) not]]) ifTrue: [
  cursor := pending at: 'columnarCursor' ifAbsent: [0].
  observation := transport invoke: (Dictionary new at: 'action' put: 'getColumnar'; at: 'root' put: root; at: 'base' put: (view at: 'checkpointDigest'); at: 'cursor' put: cursor; yourself) configuration: configuration.
  (observation at: 'state') = 'unsupported'
   ifTrue: [self fallbackToCanonical: root]
   ifFalse: [CSAuthorityChecks require: (observation at: 'state') = 'frame' code: 'columnar-response'.
    frame := observation at: 'frame'.
    CSColumnarCodec validateFrame: frame base: (view at: 'checkpointDigest') cursor: cursor.
    CSAuthorityChecks require: (frame at: 'root') = root code: 'columnar-root'.
    payload at: 'root' put: root; at: 'frame' put: frame. ^ self transition: 'stage' payload: payload]].
 missing := (self artifactsFor: view) missingFor: root limit: 32.
 missing notEmpty ifTrue: [
  objects := (transport invoke: (Dictionary new at: 'action' put: 'getObjects'; at: 'hashes' put: missing; yourself) configuration: configuration) at: 'objects'.
  CSAuthorityChecks require: (objects notEmpty and: [(objects collect: [:object | object at: 'hash']) asSet size = objects size and: [objects allSatisfy: [:object | missing includes: (object at: 'hash')]]]) code: 'artifact-fetch-mismatch'.
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

{ #category : 'columnar transport' }
CSShardedRepastDriver >> typedView: view [
 | store node |
 store := self artifactsFor: view. node := store objectAt: (view at: 'checkpointDigest').
 ^ (CSModelBundle fromSnapshot: (store valueAt: (node at: 'model'))) isTyped
]
