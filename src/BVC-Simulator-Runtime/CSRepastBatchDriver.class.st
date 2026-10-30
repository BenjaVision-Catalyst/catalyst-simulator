Class {
	#name : 'CSRepastBatchDriver',
	#superclass : 'Object',
	#instVars : [
		'configuration',
		'transport'
	],
	#category : 'BVC-Simulator-Runtime',
	#package : 'BVC-Simulator-Runtime'
}

{ #category : 'repast integration' }
CSRepastBatchDriver >> activationFor: view [
 ^ self transition: 'activate' payload: (Dictionary new at: 'checkpointDigest' put: (view at: 'checkpointDigest'); at: 'modelDigest' put: (view at: 'modelDigest'); yourself)
]

{ #category : 'repast integration' }
CSRepastBatchDriver >> bindingFor: view [
 | pending checkpoint binding |
 pending := view at: 'pending'. checkpoint := view at: 'checkpoint'.
 binding := Dictionary new at: 'version' put: 1; at: 'world' put: (view at: 'world'); at: 'group' put: (view at: 'group');
  at: 'generation' put: (pending ifNil: [view at: 'generation'] ifNotNil: [pending at: 'generation']);
  at: 'owner' put: (pending ifNil: [view at: 'owner'] ifNotNil: [pending at: 'owner']);
  at: 'modelDigest' put: (view at: 'modelDigest'); at: 'checkpointDigest' put: (view at: 'checkpointDigest');
  at: 'fromTick' put: (checkpoint at: 'tick');
  at: 'targetTick' put: (pending ifNil: [checkpoint at: 'tick'] ifNotNil: [pending at: 'targetTick']); yourself.
 pending
  ifNil: [binding at: 'batch' put: (CSSha256 hexDigestOf: 'CatalystSimulation-Restore-1:', (CSCanonicalCodec encode: binding)).
   binding at: 'inputDigest' put: (view at: 'checkpointDigest')]
  ifNotNil: [binding at: 'batch' put: (pending at: 'batch'); at: 'inputDigest' put: (pending at: 'inputDigest')].
 ^ binding
]

{ #category : 'repast integration' }
CSRepastBatchDriver >> configuration: cfg transport: instance [
 configuration := cfg. transport := instance
]

{ #category : 'repast integration' }
CSRepastBatchDriver >> nextFor: view [
 | pending observation checkpoint payload |
 pending := view at: 'pending'.
 (view at: 'phase') = 'handover' ifTrue: [
  (view at: 'backend') = 'smalltalk' ifTrue: [CSAuthorityChecks checkpoint: (view at: 'checkpoint'). ^ self activationFor: view].
  observation := self observationFor: view.
  (observation at: 'state') = 'complete' ifFalse: [^ nil].
  checkpoint := self validatedCheckpoint: observation for: view.
  CSAuthorityChecks require: checkpoint = (view at: 'checkpoint') code: 'restore-mutated-checkpoint'.
  ^ self activationFor: view].
 pending ifNil: [^ nil].
 payload := Dictionary new at: 'batch' put: (pending at: 'batch'); at: 'inputDigest' put: (pending at: 'inputDigest'); yourself.
 ((view at: 'phase') = 'active' and: [(pending at: 'phase') = 'prepared']) ifTrue: [^ self transition: 'dispatch' payload: payload].
 observation := self observationFor: view.
 (observation at: 'state') = 'complete' ifFalse: [^ nil].
 payload at: 'checkpoint' put: (self validatedCheckpoint: observation for: view).
 (view at: 'phase') = 'reconciling' ifTrue: [
  payload at: 'decision' put: 'confirmed-result'; at: 'proof' put: 'native-receipt-', (observation at: 'checkpointDigest').
  ^ self transition: 'reconcile' payload: payload].
 ^ self transition: 'result' payload: payload
]

{ #category : 'repast integration' }
CSRepastBatchDriver >> observationFor: view [
 | request |
 request := Dictionary new at: 'action' put: ((view at: 'phase') = 'reconciling' ifTrue: ['query'] ifFalse: ['ensure']);
 at: 'spec' put: (self specificationFor: view); at: 'executable' put: configuration repastExecutable;
 at: 'mpi' put: configuration repastMpi; at: 'ranks' put: configuration repastRanks; yourself.
 ^ transport invoke: request configuration: configuration
]

{ #category : 'repast integration' }
CSRepastBatchDriver >> specificationFor: view [
 ^ Dictionary new at: 'binding' put: (self bindingFor: view); at: 'checkpoint' put: (view at: 'checkpoint');
 at: 'registry' put: CSOperationRegistry portable snapshot; yourself
]

{ #category : 'repast integration' }
CSRepastBatchDriver >> transition: kind payload: payload [
 ^ Dictionary new at: 'kind' put: kind; at: 'payload' put: payload; yourself
]

{ #category : 'repast integration' }
CSRepastBatchDriver >> validatedCheckpoint: observation for: view [
 | checkpoint backend |
 CSAuthorityChecks require: (observation at: 'binding') = (self bindingFor: view) code: 'external-binding-mismatch'.
 checkpoint := observation at: 'checkpoint'. backend := CSAuthorityChecks checkpoint: checkpoint.
 CSAuthorityChecks require: (CSSha256 hexDigestOf: backend checkpoint) = (observation at: 'checkpointDigest') code: 'external-checksum-mismatch'.
 CSAuthorityChecks require: (backend model digest = (view at: 'modelDigest') and: [backend tick = ((self bindingFor: view) at: 'targetTick') and: [(checkpoint at: 'seed') = ((view at: 'checkpoint') at: 'seed')]]) code: 'external-frontier-mismatch'.
 ^ checkpoint
]
