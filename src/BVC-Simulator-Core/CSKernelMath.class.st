"
CatalystSimulation P0/P1 portable probe foundation. Generic mechanisms only; ecosystem rules and UE content belong to domain components.
"
Class {
	#name : 'CSKernelMath',
	#superclass : 'Object',
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'portable kernel' }
CSKernelMath class >> hexInteger: value [
 self identifier: value.
 ^ value inject: 0 into: [:sum :ch | sum * 16 + ('0123456789abcdef' indexOf: ch) - 1]
]

{ #category : 'portable kernel' }
CSKernelMath class >> identifier: value [
 self require: (value isString and: [value size = 32 and: [value allSatisfy: [:ch | '0123456789abcdef' includes: ch]]]) message: 'Canonical 128-bit lower-hex identity required'. ^ value
]

{ #category : 'portable kernel' }
CSKernelMath class >> int64: value [
 self require: (value isInteger and: [value between: -9223372036854775808 and: 9223372036854775807]) message: 'Signed 64-bit integer required'. ^ value
]

{ #category : 'portable kernel' }
CSKernelMath class >> less: first than: second [
 first = second ifTrue: [^ false].
 first isInteger ifTrue: [^ first < second].
 first isString ifTrue: [^ self string: first precedes: second].
 self require: (first class == Array and: [second class == Array]) message: 'Unordered value'.
 1 to: (first size min: second size) do: [:i | (first at: i) = (second at: i) ifFalse: [^ self less: (first at: i) than: (second at: i)]].
 ^ first size < second size
]

{ #category : 'portable kernel' }
CSKernelMath class >> nonnegative: value [
 self int64: value. self require: value >= 0 message: 'Nonnegative integer required'. ^ value
]

{ #category : 'portable kernel' }
CSKernelMath class >> require: condition message: message [
 condition == true ifFalse: [ CSKernelError signal: message ]
]

{ #category : 'portable kernel' }
CSKernelMath class >> string: first precedes: second [
 1 to: (first size min: second size) do: [:i |
  (first at: i) asciiValue = (second at: i) asciiValue ifFalse: [^ (first at: i) asciiValue < (second at: i) asciiValue]].
 ^ first size < second size
]

{ #category : 'portable kernel' }
CSKernelMath class >> uint32: value [
 self require: (value isInteger and: [value between: 0 and: 4294967295]) message: 'Unsigned 32-bit integer required'. ^ value
]

{ #category : 'portable kernel' }
CSKernelMath class >> uint64: value [
 self require: (value isInteger and: [value between: 0 and: 18446744073709551615]) message: 'Unsigned 64-bit integer required'. ^ value
]

{ #category : 'portable kernel' }
CSKernelMath class >> vector: vector [
 self require: (vector class == Array and: [vector size = 3]) message: 'Three integer coordinates required'.
 vector do: [:each | self int64: each]. ^ vector
]
