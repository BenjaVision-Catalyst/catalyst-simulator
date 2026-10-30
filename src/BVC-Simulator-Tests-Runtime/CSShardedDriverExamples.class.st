Class {
	#name : 'CSShardedDriverExamples',
	#superclass : 'TestCase',
	#category : 'BVC-Simulator-Tests-Runtime',
	#package : 'BVC-Simulator-Tests-Runtime'
}

{ #category : 'sharded runtime tests' }
CSShardedDriverExamples >> testModeIsSerializedAndFencesQueuedPolicy [
 <gtExample>
 | cfg hash copy result |
 cfg := CSSimulationConfiguration new. hash := cfg repastPolicyDigest.
 cfg repastMode: 'sharded'. self deny: hash = cfg repastPolicyDigest.
 copy := CRRuntimeConfigurationCodec decodeObject: (CRRuntimeConfigurationCodec encodeObject: cfg).
 self assert: copy repastMode equals: 'sharded'.
 result := CRRuntimeConfigurationValidationResult new. copy validateRepastOn: result.
 self assert: result isValid
]

{ #category : 'sharded runtime tests' }
CSShardedDriverExamples >> testPreparedDispatchDoesNotPerformArtifactIO [
 <gtExample>
 | group helper transport driver |
 group := CSShardedAuthorityExamples new externalGroup. helper := CSAuthorityExamples new.
 helper apply: 'prepare' group: group payload: (helper target: 2).
 transport := CSRepastRecordingTransport new.
 driver := CSShardedRepastDriver new configuration: CSSimulationConfiguration new transport: transport; yourself.
 self assert: ((driver nextFor: group view) at: 'kind') equals: 'dispatch'.
 self assert: transport requests isEmpty
]

{ #category : 'sharded runtime tests' }
CSShardedDriverExamples >> testRecoveryQueriesOriginalManifestWithoutUploadOrLaunch [
 <gtExample>
 | group helper transport driver old |
 group := CSShardedAuthorityExamples new externalGroup. helper := CSAuthorityExamples new.
 helper apply: 'prepare' group: group payload: (helper target: 2). helper dispatch: group. old := group view.
 helper apply: 'recover' group: group payload: ((helper placement: 'external' owner: 5) at: 'reason' put: 'recover artifact result'; yourself).
 transport := CSRepastRecordingTransport new reply: (Dictionary new at: 'state' put: 'unknown'; yourself); yourself.
 driver := CSShardedRepastDriver new configuration: CSSimulationConfiguration new transport: transport; yourself.
 self assert: (driver nextFor: group view) isNil.
 self assert: transport requests size equals: 1.
 self assert: (transport requests first at: 'action') equals: 'query'.
 self assert: ((((transport requests first at: 'spec') at: 'binding') at: 'generation')) equals: (old at: 'generation').
 self deny: ((transport requests first at: 'spec') includesKey: 'checkpoint')
]
