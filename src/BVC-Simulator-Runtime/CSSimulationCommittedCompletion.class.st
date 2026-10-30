Class {
	#name : 'CSSimulationCommittedCompletion',
	#superclass : 'CRWorkUnitResultCompletion',
	#instVars : [
		'publisher'
	],
	#category : 'BVC-Simulator-Runtime',
	#package : 'BVC-Simulator-Runtime'
}

{ #category : 'simulation runtime' }
CSSimulationCommittedCompletion class >> publisher: receiver [
 ^ self new initializePublisher: receiver
]

{ #category : 'simulation runtime' }
CSSimulationCommittedCompletion >> acceptResult: result in: execution onWorker: worker [
 publisher publishSimulationResult: (CSCanonicalCodec copy: result)
]

{ #category : 'simulation runtime' }
CSSimulationCommittedCompletion >> acceptsInMemoryFinalization [
 ^ true
]

{ #category : 'simulation runtime' }
CSSimulationCommittedCompletion >> afterCommit [
 ^ true
]

{ #category : 'simulation runtime' }
CSSimulationCommittedCompletion >> afterFinalization [
 ^ true
]

{ #category : 'simulation runtime' }
CSSimulationCommittedCompletion >> initializePublisher: receiver [
 (receiver respondsTo: #publishSimulationResult:) ifFalse: [self error: 'Simulation result publisher required'].
 publisher := receiver. ^ self
]

{ #category : 'simulation runtime' }
CSSimulationCommittedCompletion >> releaseCompletion [
 publisher := nil
]
