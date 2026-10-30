Class {
	#name : 'CSArtifactEntityIndex',
	#superclass : 'Object',
	#instVars : [
		'store',
		'index',
		'count'
	],
	#category : 'BVC-Simulator-Authority',
	#package : 'BVC-Simulator-Authority'
}

{ #category : 'sharded checkpoints' }
CSArtifactEntityIndex >> includesKey: id [
 (id isString and: [id size = 32]) ifFalse: [^ false].
 ^ index at: (id last: 2) ifPresent: [:root | (store row: id at: root) notNil] ifAbsent: [false]
]

{ #category : 'sharded checkpoints' }
CSArtifactEntityIndex >> size [
 ^ count
]

{ #category : 'sharded checkpoints' }
CSArtifactEntityIndex >> store: aStore index: roots count: size [
 store := aStore. index := roots. count := size
]
