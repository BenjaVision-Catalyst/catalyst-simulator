Class {
	#name : 'CSRepastBatchExamples',
	#superclass : 'TestCase',
	#category : 'BVC-Simulator-Tests-Runtime',
	#package : 'BVC-Simulator-Tests-Runtime'
}

{ #category : 'repast tests' }
CSRepastBatchExamples >> testPreparedDoesNotPerformIO [
 <gtExample>
 | helper group driver transport transition |
 helper := CSAuthorityExamples new. group := helper externalGroup.
 helper apply: 'prepare' group: group payload: (helper target: 2).
 transport := CSRepastRecordingTransport new.
 driver := CSRepastBatchDriver new configuration: CSSimulationConfiguration new transport: transport; yourself.
 transition := driver nextFor: group view.
 self assert: (transition at: 'kind') equals: 'dispatch'.
 self assert: transport requests isEmpty
]

{ #category : 'repast tests' }
CSRepastBatchExamples >> testRecoveryQueriesOriginalBindingAndNeverLaunches [
 <gtExample>
 | helper group driver transport before transition |
 helper := CSAuthorityExamples new. group := helper externalGroup.
 helper apply: 'prepare' group: group payload: (helper target: 2). helper dispatch: group.
 before := group view.
 helper apply: 'recover' group: group payload: ((helper placement: 'external' owner: 5) at: 'reason' put: 'lost-reply'; yourself).
 transport := CSRepastRecordingTransport new reply: (Dictionary new at: 'state' put: 'missing'; yourself); yourself.
 driver := CSRepastBatchDriver new configuration: CSSimulationConfiguration new transport: transport; yourself.
 transition := driver nextFor: group view.
 self assert: transition isNil.
 self assert: (transport requests first at: 'action') equals: 'query'.
 self assert: (((transport requests first at: 'spec') at: 'binding') at: 'generation') equals: (before at: 'generation').
 self assert: (group view at: 'pending') equals: (before at: 'pending')
]

{ #category : 'repast tests' }
CSRepastBatchExamples >> testRepastConfigurationRoundTripAndPolicyFence [
 <gtExample>
 | cfg copy digest result |
 cfg := CSSimulationConfiguration new repastLauncher: '/native/launcher'; repastExecutable: '/native/exe'; repastMpi: '/native/mpirun'; repastDirectory: '/native/spool'; repastRanks: 4; yourself.
 copy := CRRuntimeConfigurationCodec decodeObject: (CRRuntimeConfigurationCodec encodeObject: cfg).
 self assert: copy repastPolicyDigest equals: cfg repastPolicyDigest.
 self assert: copy repastRanks equals: 4.
 digest := copy repastPolicyDigest. copy repastRanks: 2.
 self deny: digest = copy repastPolicyDigest.
 result := CRRuntimeConfigurationValidationResult new. copy repastDirectory: 'relative'; validateRepastOn: result.
 self deny: result isValid
]

{ #category : 'repast tests' }
CSRepastBatchExamples >> testRestoreCannotAdvanceAndLocalReturnValidates [
 <gtExample>
 | helper group view driver transport observation |
 helper := CSAuthorityExamples new. group := helper group.
 helper apply: 'transfer' group: group payload: (helper placement: 'external' owner: 4). view := group view.
 transport := CSRepastRecordingTransport new. driver := CSRepastBatchDriver new configuration: CSSimulationConfiguration new transport: transport; yourself.
 observation := Dictionary new at: 'state' put: 'complete'; at: 'binding' put: (driver bindingFor: view);
  at: 'checkpoint' put: (view at: 'checkpoint'); at: 'checkpointDigest' put: (view at: 'checkpointDigest'); yourself.
 transport reply: observation.
 self assert: ((driver nextFor: view) at: 'kind') equals: 'activate'.
 helper apply: 'activate' group: group payload: ((driver nextFor: view) at: 'payload').
 helper apply: 'transfer' group: group payload: (helper placement: 'smalltalk' owner: 5).
 self assert: ((driver nextFor: group view) at: 'kind') equals: 'activate'.
 self assert: transport requests size equals: 2
]

{ #category : 'repast tests' }
CSRepastBatchExamples >> testResultDigestAndFencing [
 <gtExample>
 | helper group driver transport checkpoint observation transition before |
 helper := CSAuthorityExamples new. group := helper externalGroup.
 helper apply: 'prepare' group: group payload: (helper target: 2). helper dispatch: group.
 before := group view. checkpoint := (CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: (before at: 'checkpoint'))) advanceThrough: 2; snapshot.
 transport := CSRepastRecordingTransport new.
 driver := CSRepastBatchDriver new configuration: CSSimulationConfiguration new transport: transport; yourself.
 observation := Dictionary new at: 'state' put: 'complete'; at: 'binding' put: (driver bindingFor: before);
  at: 'checkpoint' put: checkpoint; at: 'checkpointDigest' put: (CSSha256 hexDigestOf: (CSCanonicalCodec encode: checkpoint)); yourself.
 transport reply: observation. transition := driver nextFor: before.
 self assert: (transition at: 'kind') equals: 'result'.
 helper apply: 'result' group: group payload: (transition at: 'payload').
 self assert: ((group view at: 'checkpoint') at: 'tick') equals: 2.
 observation at: 'checkpointDigest' put: (String new: 64 withAll: $0).
 self should: [driver validatedCheckpoint: observation for: before] raise: CSAuthorityError.
 observation at: 'binding' put: (Dictionary new).
 self should: [driver validatedCheckpoint: observation for: before] raise: CSAuthorityError
]
