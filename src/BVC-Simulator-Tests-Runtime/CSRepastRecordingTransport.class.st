Class {
	#name : 'CSRepastRecordingTransport',
	#superclass : 'Object',
	#instVars : [
		'reply',
		'requests'
	],
	#category : 'BVC-Simulator-Tests-Runtime',
	#package : 'BVC-Simulator-Tests-Runtime'
}

{ #category : 'repast tests' }
CSRepastRecordingTransport >> invoke: request configuration: cfg [
 requests ifNil: [requests := OrderedCollection new].
 requests add: request.
 ^ reply
]

{ #category : 'repast tests' }
CSRepastRecordingTransport >> reply: value [
 reply := value
]

{ #category : 'repast tests' }
CSRepastRecordingTransport >> requests [
 ^ requests ifNil: [#()]
]
