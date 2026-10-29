"
Portable ASCII SHA-256 for canonical model identity; FIPS 180-4. No dialect-specific crypto dependency.
"
Class {
	#name : 'CSSha256',
	#superclass : 'Object',
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'portable graph' }
CSSha256 class >> constants [
 ^ #(16r428A2F98 16r71374491 16rB5C0FBCF 16rE9B5DBA5 16r3956C25B 16r59F111F1 16r923F82A4 16rAB1C5ED5
 16rD807AA98 16r12835B01 16r243185BE 16r550C7DC3 16r72BE5D74 16r80DEB1FE 16r9BDC06A7 16rC19BF174
 16rE49B69C1 16rEFBE4786 16r0FC19DC6 16r240CA1CC 16r2DE92C6F 16r4A7484AA 16r5CB0A9DC 16r76F988DA
 16r983E5152 16rA831C66D 16rB00327C8 16rBF597FC7 16rC6E00BF3 16rD5A79147 16r06CA6351 16r14292967
 16r27B70A85 16r2E1B2138 16r4D2C6DFC 16r53380D13 16r650A7354 16r766A0ABB 16r81C2C92E 16r92722C85
 16rA2BFE8A1 16rA81A664B 16rC24B8B70 16rC76C51A3 16rD192E819 16rD6990624 16rF40E3585 16r106AA070
 16r19A4C116 16r1E376C08 16r2748774C 16r34B0BCB5 16r391C0CB3 16r4ED8AA4A 16r5B9CCA4F 16r682E6FF3
 16r748F82EE 16r78A5636F 16r84C87814 16r8CC70208 16r90BEFFFA 16rA4506CEB 16rBEF9A3F7 16rC67178F2)
]

{ #category : 'portable graph' }
CSSha256 class >> hexDigestOf: ascii [
 | bytes bits state words working constants mask s0 s1 a b c d e f g h ch maj t1 t2 out |
 CSKernelMath require: (ascii isString and: [ascii size <= 8388608 and: [ascii allSatisfy: [:char | char asciiValue <= 127]]]) message: 'SHA-256 requires bounded ASCII bytes'.
 mask := 4294967295. bytes := OrderedCollection new.
 ascii do: [:char | bytes add: char asciiValue].
 bits := bytes size * 8. bytes add: 128.
 [bytes size \\ 64 = 56] whileFalse: [bytes add: 0].
 7 to: 0 by: -1 do: [:i | bytes add: ((bits bitShift: i * -8) bitAnd: 255)].
 state := #(16r6A09E667 16rBB67AE85 16r3C6EF372 16rA54FF53A 16r510E527F 16r9B05688C 16r1F83D9AB 16r5BE0CD19) copy.
 constants := self constants.
 0 to: bytes size - 1 by: 64 do: [:offset |
  words := Array new: 64.
  1 to: 16 do: [:i | | word | word := 0.
   1 to: 4 do: [:j | word := word * 256 + (bytes at: offset + ((i - 1) * 4) + j)].
   words at: i put: word].
  17 to: 64 do: [:i | | x y |
   x := words at: i - 15. y := words at: i - 2.
   s0 := ((self rotate: x by: 7) bitXor: (self rotate: x by: 18)) bitXor: (x bitShift: -3).
   s1 := ((self rotate: y by: 17) bitXor: (self rotate: y by: 19)) bitXor: (y bitShift: -10).
   words at: i put: (((words at: i - 16) + s0 + (words at: i - 7) + s1) bitAnd: mask)].
  working := state copy.
  1 to: 64 do: [:i |
   a := working first. b := working second. c := working third. d := working fourth.
   e := working fifth. f := working sixth. g := working seventh. h := working eighth.
   s1 := ((self rotate: e by: 6) bitXor: (self rotate: e by: 11)) bitXor: (self rotate: e by: 25).
   ch := (e bitAnd: f) bitXor: ((e bitXor: mask) bitAnd: g).
   t1 := (h + s1 + ch + (constants at: i) + (words at: i)) bitAnd: mask.
   s0 := ((self rotate: a by: 2) bitXor: (self rotate: a by: 13)) bitXor: (self rotate: a by: 22).
   maj := ((a bitAnd: b) bitXor: (a bitAnd: c)) bitXor: (b bitAnd: c).
   t2 := (s0 + maj) bitAnd: mask.
   working := { (t1 + t2) bitAnd: mask. a. b. c. (d + t1) bitAnd: mask. e. f. g }].
  1 to: 8 do: [:i | state at: i put: (((state at: i) + (working at: i)) bitAnd: mask)]].
 out := WriteStream on: String new.
 state do: [:word | 7 to: 0 by: -1 do: [:i | out nextPut: ('0123456789abcdef' at: ((word bitShift: i * -4) bitAnd: 15) + 1)]].
 ^ out contents
]

{ #category : 'portable graph' }
CSSha256 class >> rotate: word by: distance [
 ^ ((word bitShift: distance negated) bitOr: (word bitShift: 32 - distance)) bitAnd: 4294967295
]
