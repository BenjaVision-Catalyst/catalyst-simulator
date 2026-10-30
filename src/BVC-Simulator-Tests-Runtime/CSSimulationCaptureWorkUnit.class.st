Class {
	#name : 'CSSimulationCaptureWorkUnit',
	#superclass : 'CSSimulationWorkUnit',
	#instVars : [
		'operationName',
		'evidenceKey'
	],
	#category : 'BVC-Simulator-Tests-Runtime',
	#package : 'BVC-Simulator-Tests-Runtime'
}

{ #category : 'simulation qualification' }
CSSimulationCaptureWorkUnit class >> operation: kind request: data principal: identity evidence: key [
 ^ (self request: data principal: identity) initializeOperation: kind evidence: key
]

{ #category : 'simulation qualification' }
CSSimulationCaptureWorkUnit >> executeInContext: context [
 | result |
 result := super executeInContext: context.
 CSSimulationEvidence record: evidenceKey value: result. ^ result
]

{ #category : 'simulation qualification' }
CSSimulationCaptureWorkUnit >> initializeOperation: kind evidence: key [
 operationName := CSAuthorityChecks text: kind. evidenceKey := CSAuthorityChecks text: key. ^ self
]

{ #category : 'simulation qualification' }
CSSimulationCaptureWorkUnit >> operation [
 ^ operationName
]
