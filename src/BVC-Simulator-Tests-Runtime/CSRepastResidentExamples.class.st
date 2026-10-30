Class {
	#name : 'CSRepastResidentExamples',
	#superclass : 'TestCase',
	#category : 'BVC-Simulator-Tests-Runtime',
	#package : 'BVC-Simulator-Tests-Runtime'
}

{ #category : 'resident Repast tests' }
CSRepastResidentExamples >> testConfigurationModeRoundTripAndPolicyFence [
 <gtExample>
 | cfg copy digest result |
 cfg := CSSimulationConfiguration new.
 self assert: cfg repastMode equals: 'batch'. digest := cfg repastPolicyDigest.
 cfg repastMode: 'resident'. self deny: cfg repastPolicyDigest = digest.
 copy := CRRuntimeConfigurationCodec decodeObject: (CRRuntimeConfigurationCodec encodeObject: cfg).
 self assert: copy repastMode equals: 'resident'.
 result := CRRuntimeConfigurationValidationResult new. copy repastMode: 'unknown'; validateRepastOn: result.
 self deny: result isValid
]

{ #category : 'resident Repast tests' }
CSRepastResidentExamples >> testFencedRecoveryOnlyQueriesOriginalBinding [
 <gtExample>
 | helper group driver transport before |
 helper := CSAuthorityExamples new. group := helper externalGroup.
 helper apply: 'prepare' group: group payload: (helper target: 2). helper dispatch: group. before := group view.
 helper apply: 'recover' group: group payload: ((helper placement: 'external' owner: 5) at: 'reason' put: 'resident failed'; yourself).
 transport := CSRepastRecordingTransport new reply: (Dictionary new at: 'state' put: 'unknown'; yourself); yourself.
 driver := CSRepastResidentDriver new configuration: CSSimulationConfiguration new transport: transport; yourself.
 self assert: (driver nextFor: group view) isNil.
 self assert: (transport requests first at: 'action') equals: 'query'.
 self assert: ((((transport requests first at: 'spec') at: 'binding') at: 'generation')) equals: (before at: 'generation')
]

{ #category : 'resident Repast tests' }
CSRepastResidentExamples >> testIdleExternalSynchronizesAcceptedFrontier [
 <gtExample>
 | group driver transport before |
 group := CSAuthorityExamples new externalGroup. before := group view.
 transport := CSRepastRecordingTransport new reply: (Dictionary new at: 'state' put: 'resident'; yourself); yourself.
 driver := CSRepastResidentDriver new configuration: CSSimulationConfiguration new transport: transport; yourself.
 self assert: (driver nextFor: before) isNil.
 self assert: (transport requests first at: 'action') equals: 'synchronize'.
 self assert: (transport requests first at: 'acceptedRevision') equals: (before at: 'revision').
 self assert: group view equals: before
]

{ #category : 'resident Repast tests' }
CSRepastResidentExamples >> testLocalReturnWaitsUntilResidentIsReaped [
 <gtExample>
 | helper group driver transport before |
 helper := CSAuthorityExamples new. group := helper externalGroup.
 helper apply: 'transfer' group: group payload: (helper placement: 'smalltalk' owner: 5).
 before := group view.
 transport := CSRepastRecordingTransport new reply: (Dictionary new at: 'state' put: 'retiring'; yourself); yourself.
 driver := CSRepastResidentDriver new configuration: CSSimulationConfiguration new transport: transport; yourself.
 self assert: (driver nextFor: before) isNil.
 self assert: (transport requests first at: 'action') equals: 'retire'.
 transport reply: (Dictionary new at: 'state' put: 'retired'; yourself).
 self assert: ((driver nextFor: before) at: 'kind') equals: 'activate'.
 self assert: group view equals: before
]

{ #category : 'resident Repast tests' }
CSRepastResidentExamples >> testPreparedNeverLaunchesResidentIO [
 <gtExample>
 | helper group driver transport transition |
 helper := CSAuthorityExamples new. group := helper externalGroup.
 helper apply: 'prepare' group: group payload: (helper target: 2).
 transport := CSRepastRecordingTransport new.
 driver := CSRepastResidentDriver new configuration: CSSimulationConfiguration new transport: transport; yourself.
 transition := driver nextFor: group view.
 self assert: (transition at: 'kind') equals: 'dispatch'. self assert: transport requests isEmpty
]
