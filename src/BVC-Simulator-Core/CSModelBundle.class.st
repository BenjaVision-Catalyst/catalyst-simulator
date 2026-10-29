"
CatalystSimulation P0/P1 portable probe foundation. Generic mechanisms only; ecosystem rules and UE content belong to domain components.
"
Class {
	#name : 'CSModelBundle',
	#superclass : 'Object',
	#instVars : [
		'canonical'
	],
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'portable kernel' }
CSModelBundle class >> fromSnapshot: value [
 ^ self new initializeFrom: value
]

{ #category : 'portable kernel' }
CSModelBundle class >> probe [
 ^ self fromSnapshot: #('simulation-portable-1/probe-1' 'portable-probe' 100 10000 10000 #('events' 'move' 'contend' 'random'))
]

{ #category : 'portable kernel' }
CSModelBundle >> compatibilityIssues [
 | stages |
 stages := self snapshot sixth.
 stages = #('events' 'move' 'contend' 'random') ifTrue: [ ^ #() ].
 ^ { { 'model/stages'. 'probe-1 requires events, move, contend, random in that order' } }
]

{ #category : 'portable kernel' }
CSModelBundle >> entityLimit [
 ^ self snapshot fourth
]

{ #category : 'portable kernel' }
CSModelBundle >> eventLimit [
 ^ self snapshot fifth
]

{ #category : 'portable kernel' }
CSModelBundle >> initializeFrom: value [
 CSKernelMath require: (value class == Array and: [ value size = 6 ]) message: 'Model requires six fields'.
 CSKernelMath require: (value first = 'simulation-portable-1/probe-1') message: 'Unsupported model profile'.
 CSKernelMath require: (value second isString and: [ value second notEmpty ]) message: 'Model identity required'.
 CSKernelMath int64: (value at: 3).
 CSKernelMath require: ((value at: 3) between: 1 and: 1000) message: 'Tick duration must be 1..1000 milliseconds'.
 4 to: 5 do: [ :i | CSKernelMath int64: (value at: i). CSKernelMath require: ((value at: i) between: 1 and: 10000) message: 'Model capacity must be 1..10000' ].
 CSKernelMath require: (value sixth class == Array and: [ value sixth allSatisfy: [ :stage | stage isString ] ]) message: 'Stages must be described names'.
 canonical := CSCanonicalCodec encode: value. ^ self
]

{ #category : 'portable kernel' }
CSModelBundle >> snapshot [
 ^ CSCanonicalCodec decode: canonical
]

{ #category : 'portable kernel' }
CSModelBundle >> tickMilliseconds [
 ^ self snapshot third
]
