Class {
	#name : 'CSColumnarScratchStore',
	#superclass : 'CSArtifactStore',
	#instVars : [
		'expandedBytes'
	],
	#category : 'BVC-Simulator-Authority',
	#package : 'BVC-Simulator-Authority'
}

{ #category : 'columnar transport' }
CSColumnarScratchStore >> put: node [
 | raw hash added bucket |
 self validateNode: node. raw := CSCanonicalCodec encode: node.
 CSAuthorityChecks require: raw size <= 16384 code: 'artifact-integrity'.
 hash := CSSha256 hexDigestOf: raw. added := (self includes: hash) ifTrue: [0] ifFalse: [raw size].
 CSAuthorityChecks require: (expandedBytes ifNil: [0]) + added <= 4194304 code: 'columnar-expanded-budget'.
 bucket := buckets at: (hash first: 2) ifAbsentPut: [Dictionary new].
 (bucket includesKey: hash) ifTrue: [CSAuthorityChecks require: (bucket at: hash) = raw code: 'artifact-collision']
  ifFalse: [CSAuthorityChecks require: self count < 65536 code: 'artifact-capacity-collect-required'. bucket at: hash put: raw].
 expandedBytes := (expandedBytes ifNil: [0]) + added. ^ hash
]

{ #category : 'columnar transport' }
CSColumnarScratchStore >> putRaw: raw hash: hash [
 | added result |
 added := (self includes: hash) ifTrue: [0] ifFalse: [raw size].
 CSAuthorityChecks require: (expandedBytes ifNil: [0]) + added <= 4194304 code: 'columnar-expanded-budget'.
 result := super putRaw: raw hash: hash.
 expandedBytes := (expandedBytes ifNil: [0]) + added. ^ result
]
