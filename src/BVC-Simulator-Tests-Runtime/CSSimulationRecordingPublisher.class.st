Class {
	#name : 'CSSimulationRecordingPublisher',
	#superclass : 'Object',
	#instVars : [
		'results'
	],
	#category : 'BVC-Simulator-Tests-Runtime',
	#package : 'BVC-Simulator-Tests-Runtime'
}

{ #category : 'simulation tests' }
CSSimulationRecordingPublisher >> initialize [
 super initialize. results := OrderedCollection new
]

{ #category : 'simulation tests' }
CSSimulationRecordingPublisher >> publishSimulationResult: value [
 results add: value
]

{ #category : 'simulation tests' }
CSSimulationRecordingPublisher >> results [
 ^ results asArray
]
