Class {
	#name : 'CSRepastResidentDriver',
	#superclass : 'CSRepastBatchDriver',
	#category : 'BVC-Simulator-Runtime',
	#package : 'BVC-Simulator-Runtime'
}

{ #category : 'resident Repast' }
CSRepastResidentDriver >> nextFor: view [
 | observation |
 ((view at: 'backend') = 'smalltalk' and: [(view at: 'phase') = 'handover']) ifTrue: [
  observation := transport invoke: (self requestFor: view action: 'retire') configuration: configuration.
  (observation at: 'state') = 'retired' ifFalse: [^ nil].
  CSAuthorityChecks checkpoint: (view at: 'checkpoint'). ^ self activationFor: view].
 ((view at: 'backend') = 'external' and: [(view at: 'phase') = 'active' and: [(view at: 'pending') isNil]]) ifTrue: [
  transport invoke: (self requestFor: view action: 'synchronize') configuration: configuration. ^ nil].
 ^ super nextFor: view
]

{ #category : 'resident Repast' }
CSRepastResidentDriver >> observationFor: view [
 ^ transport invoke: (self requestFor: view action: ((view at: 'phase') = 'reconciling' ifTrue: ['query'] ifFalse: ['ensure'])) configuration: configuration
]

{ #category : 'resident Repast' }
CSRepastResidentDriver >> requestFor: view action: action [
 ^ Dictionary new at: 'action' put: action; at: 'spec' put: (self specificationFor: view);
 at: 'executable' put: configuration repastExecutable; at: 'mpi' put: configuration repastMpi;
 at: 'ranks' put: configuration repastRanks; at: 'acceptedRevision' put: (view at: 'revision'); yourself
]
