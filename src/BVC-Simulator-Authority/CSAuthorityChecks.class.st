Class {
	#name : 'CSAuthorityChecks',
	#superclass : 'Object',
	#category : 'BVC-Simulator-Authority',
	#package : 'BVC-Simulator-Authority'
}

{ #category : 'simulation authority' }
CSAuthorityChecks class >> backend: kind owner: token [
 self require: (#('smalltalk' 'external') includes: kind) code: 'invalid-backend'.
 CSKernelMath identifier: token
]

{ #category : 'simulation authority' }
CSAuthorityChecks class >> checkpoint: value [
 | backend |
 backend := CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: value).
 self require: backend model isGraph code: 'graph-profile-required'.
 self require: backend checkpoint size <= 196608 code: 'checkpoint-byte-limit'.
 ^ backend
]

{ #category : 'simulation authority' }
CSAuthorityChecks class >> keys: object exactly: names [
 self require: ((object isKindOf: Dictionary) and: [object keys asSet = names asSet]) code: 'invalid-fields'
]

{ #category : 'simulation authority' }
CSAuthorityChecks class >> placement: payload model: model [
 self backend: (payload at: 'backend') owner: (payload at: 'owner').
 self require: ((payload at: 'operations') class == Array and: [(payload at: 'operations') size <= 16]) code: 'invalid-capabilities'.
 self require: ((model compatibilityReportFor: (CSOperationRegistry supporting: (payload at: 'operations'))) at: 'compatible') code: 'incompatible-placement'
]

{ #category : 'simulation authority' }
CSAuthorityChecks class >> request: request [
 self keys: request exactly: #('world' 'group' 'sequence' 'id' 'expectedRevision' 'generation' 'owner' 'payload').
 CSKernelMath identifier: (request at: 'world'). CSKernelMath identifier: (request at: 'group').
 self text: (request at: 'id').
 #('sequence' 'expectedRevision' 'generation') do: [:key | CSKernelMath nonnegative: (request at: key)].
 self require: (request at: 'sequence') > 0 code: 'invalid-sequence'.
 self require: (request at: 'owner') isString code: 'invalid-owner'.
 self require: (CSCanonicalCodec encode: request) size <= 262144 code: 'request-byte-limit'.
 ^ CSCanonicalCodec copy: request
]

{ #category : 'simulation authority' }
CSAuthorityChecks class >> require: condition code: code [
 condition ifFalse: [CSAuthorityError signal: code]
]

{ #category : 'simulation authority' }
CSAuthorityChecks class >> text: value [
 self require: (value isString and: [value size between: 1 and: 128]) code: 'invalid-text'.
 CSCanonicalCodec encode: value. ^ value copy
]
