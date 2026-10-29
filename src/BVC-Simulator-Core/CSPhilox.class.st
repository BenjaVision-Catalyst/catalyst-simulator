"
CatalystSimulation P0/P1 portable probe foundation. Generic mechanisms only; ecosystem rules and UE content belong to domain components.
"
Class {
	#name : 'CSPhilox',
	#superclass : 'Object',
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'portable kernel' }
CSPhilox class >> sampleFor: entityId seed: seed stream: stream draw: draw [
 | identity mask |
 CSKernelMath uint64: seed. CSKernelMath uint32: stream. CSKernelMath uint32: draw.
 identity := CSKernelMath hexInteger: entityId. mask := 4294967295.
 ^ (self wordsFor: {draw. stream. identity bitAnd: mask. (identity bitShift: -32) bitAnd: mask}
  key: {((identity bitShift: -64) bitAnd: mask) bitXor: (seed bitAnd: mask).
   ((identity bitShift: -96) bitAnd: mask) bitXor: ((seed bitShift: -32) bitAnd: mask)}) first
]

{ #category : 'portable kernel' }
CSPhilox class >> wordsFor: counter key: key [
 | words keys p0 p1 mask |
 CSKernelMath require: (counter class == Array and: [counter size = 4 and: [key class == Array and: [key size = 2]]]) message: 'Philox shape'.
 counter do: [:v | CSKernelMath uint32: v]. key do: [:v | CSKernelMath uint32: v].
 words := counter copy. keys := key copy. mask := 4294967295.
 1 to: 10 do: [:round |
  p0 := 16rD2511F53 * words first. p1 := 16rCD9E8D57 * (words at: 3).
  words := {(((p1 bitShift: -32) bitXor: (words at: 2)) bitXor: keys first) bitAnd: mask.
   p1 bitAnd: mask.
   (((p0 bitShift: -32) bitXor: (words at: 4)) bitXor: keys second) bitAnd: mask.
   p0 bitAnd: mask}.
  keys at: 1 put: ((keys first + 16r9E3779B9) bitAnd: mask).
  keys at: 2 put: ((keys second + 16rBB67AE85) bitAnd: mask)].
 ^ words
]
