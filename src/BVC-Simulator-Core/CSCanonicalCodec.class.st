"
CatalystSimulation P0/P1 portable probe foundation. Generic mechanisms only; ecosystem rules and UE content belong to domain components.
"
Class {
	#name : 'CSCanonicalCodec',
	#superclass : 'Object',
	#instVars : [
		'text',
		'index',
		'atoms',
		'output'
	],
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'portable kernel' }
CSCanonicalCodec class >> copy: value [
 ^ self decode: (self encode: value)
]

{ #category : 'portable kernel' }
CSCanonicalCodec class >> decode: value [
 ^ self new decode: value
]

{ #category : 'portable kernel' }
CSCanonicalCodec class >> encode: value [
 ^ self new encode: value
]

{ #category : 'portable kernel' }
CSCanonicalCodec >> billDepth: depth [
 atoms := atoms + 1.
 CSKernelMath require: (depth <= 16 and: [atoms <= 500000]) message: 'Canonical value budget exceeded'.
 output ifNotNil: [ CSKernelMath require: output position <= 8388608 message: 'Canonical byte budget exceeded' ]
]

{ #category : 'portable kernel' }
CSCanonicalCodec >> decimalUntil: delimiter [
 | start token ch sign |
 start := index. ch := self take.
 [ch = delimiter] whileFalse: [
  CSKernelMath require: index - start <= 21 message: 'Integer token too long'. ch := self take].
 token := text copyFrom: start to: index - 2.
 CSKernelMath require: (token notEmpty and: [(token first = $- ifTrue: [token size > 1 and: [(token allButFirst) allSatisfy: [:c | c between: $0 and: $9]]] ifFalse: [token allSatisfy: [:c | c between: $0 and: $9]])]) message: 'Invalid decimal token'.
 sign := 1.
 token first = $- ifTrue: [sign := -1. token := token allButFirst].
 ^ sign * (token inject: 0 into: [:sum :digit | sum * 10 + digit asciiValue - 48])
]

{ #category : 'portable kernel' }
CSCanonicalCodec >> decode: encoded [
 | value |
 CSKernelMath require: (encoded isString and: [encoded size <= 8388608]) message: 'Invalid canonical bytes'.
 text := encoded. index := 1. atoms := 0.
 value := self readDepth: 0.
 CSKernelMath require: (index = (text size + 1) and: [(self class encode: value) = text]) message: 'Noncanonical or trailing input'.
 ^ value
]

{ #category : 'portable kernel' }
CSCanonicalCodec >> encode: value [
 atoms := 0. output := WriteStream on: String new.
 self write: value depth: 0.
 CSKernelMath require: output position <= 8388608 message: 'Canonical byte budget exceeded'.
 ^ output contents
]

{ #category : 'portable kernel' }
CSCanonicalCodec >> readDepth: depth [
 | tag count value key |
 self billDepth: depth. tag := self take.
 tag = $n ifTrue: [^ nil]. tag = $t ifTrue: [^ true]. tag = $f ifTrue: [^ false].
 tag = $i ifTrue: [^ self decimalUntil: $;].
 count := self decimalUntil: $:.
 CSKernelMath require: (count between: 0 and: 100000) message: 'Canonical collection bound'.
 tag = $s ifTrue: [
  CSKernelMath require: (count <= 4096 and: [index + count - 1 <= text size]) message: 'Truncated or oversized string'.
  value := text copyFrom: index to: index + count - 1. index := index + count. self validateString: value. ^ value].
 tag = $a ifTrue: [
  value := Array new: count. 1 to: count do: [:i | value at: i put: (self readDepth: depth + 1)]. ^ value].
 tag = $d ifTrue: [
  value := Dictionary new.
  1 to: count do: [:i |
   key := self readDepth: depth + 1.
   CSKernelMath require: (key isString and: [(value includesKey: key) not]) message: 'Invalid or duplicate map key'.
   value at: key put: (self readDepth: depth + 1)]. ^ value].
 CSKernelError signal: 'Unknown canonical tag'
]

{ #category : 'portable kernel' }
CSCanonicalCodec >> take [
 | value |
 CSKernelMath require: index <= text size message: 'Truncated canonical input'.
 value := text at: index. index := index + 1. ^ value
]

{ #category : 'portable kernel' }
CSCanonicalCodec >> validateString: value [
 CSKernelMath require: (value size <= 4096 and: [value allSatisfy: [:ch | ch asciiValue between: 32 and: 126]]) message: 'Printable ASCII string required'
]

{ #category : 'portable kernel' }
CSCanonicalCodec >> write: value depth: depth [
 | keys |
 self billDepth: depth.
 value isNil ifTrue: [output nextPut: $n. ^ self].
 value == true ifTrue: [output nextPut: $t. ^ self].
 value == false ifTrue: [output nextPut: $f. ^ self].
 value isInteger ifTrue: [
  CSKernelMath require: (value between: -9223372036854775808 and: 18446744073709551615) message: 'Canonical integer out of range'.
  output nextPut: $i; nextPutAll: value printString; nextPut: $;. ^ self].
 (value isString and: [ value isSymbol not ]) ifTrue: [
  self validateString: value.
  output nextPut: $s; nextPutAll: value size printString; nextPut: $:; nextPutAll: value. ^ self].
 value class == Array ifTrue: [
  CSKernelMath require: value size <= 100000 message: 'Array budget exceeded'.
  output nextPut: $a; nextPutAll: value size printString; nextPut: $:.
  value do: [:each | self write: each depth: depth + 1]. ^ self].
 (value isKindOf: Dictionary) ifTrue: [
  CSKernelMath require: value size <= 100000 message: 'Map budget exceeded'.
  value keys do: [:key | CSKernelMath require: key isString message: 'Map keys must be strings'].
  keys := value keys asSortedCollection: [:a :b | CSKernelMath string: a precedes: b].
  output nextPut: $d; nextPutAll: value size printString; nextPut: $:.
  keys do: [:key | self write: key depth: depth + 1. self write: (value at: key) depth: depth + 1]. ^ self].
 CSKernelError signal: 'Unsupported canonical value'
]
