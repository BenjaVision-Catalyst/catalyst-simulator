Class {
	#name : 'CSSimulationEvidence',
	#superclass : 'Object',
	#classVars : [
		'Records'
	],
	#category : 'BVC-Simulator-Tests-Runtime',
	#package : 'BVC-Simulator-Tests-Runtime'
}

{ #category : 'simulation qualification' }
CSSimulationEvidence class >> at: key [
 ^ Records ifNil: [nil] ifNotNil: [Records at: key ifAbsent: [nil]]
]

{ #category : 'simulation qualification' }
CSSimulationEvidence class >> record: key value: value [
 Records ifNil: [Records := Dictionary new].
 Records at: key copy put: (CSCanonicalCodec copy: value)
]

{ #category : 'simulation qualification' }
CSSimulationEvidence class >> removePrefix: prefix [
 Records ifNotNil: [(Records keys select: [:key | key beginsWith: prefix]) do: [:key | Records removeKey: key]]
]
