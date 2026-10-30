Class {
	#name : 'CSSimulationConfiguration',
	#superclass : 'CRServiceConfiguration',
	#instVars : [
		'repositoryName',
		'controlPrincipal',
		'executorPrincipal',
		'maximumGroups',
		'journalLimit',
		'maximumSteps',
		'driveThroughTick',
		'driveIntervalMillis'
	],
	#category : 'BVC-Simulator-Runtime',
	#package : 'BVC-Simulator-Runtime'
}

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> controlPrincipal [
 ^ controlPrincipal
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> controlPrincipal: value [
 controlPrincipal := value
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> descriptionControlPrincipal [
 <magritteDescription>
 ^ MAStringDescription new accessor: #controlPrincipal; label: 'controlPrincipal'; beRequired; cfSerializable: true; yourself
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> descriptionDriveIntervalMillis [
 <magritteDescription>
 ^ MANumberDescription new accessor: #driveIntervalMillis; label: 'driveIntervalMillis'; kind: Integer; min: 0; beRequired; cfSerializable: true; yourself
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> descriptionDriveThroughTick [
 <magritteDescription>
 ^ MANumberDescription new accessor: #driveThroughTick; label: 'driveThroughTick'; kind: Integer; min: 0; beRequired; cfSerializable: true; yourself
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> descriptionExecutorPrincipal [
 <magritteDescription>
 ^ MAStringDescription new accessor: #executorPrincipal; label: 'executorPrincipal'; beRequired; cfSerializable: true; yourself
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> descriptionJournalLimit [
 <magritteDescription>
 ^ MANumberDescription new accessor: #journalLimit; label: 'journalLimit'; kind: Integer; min: 0; beRequired; cfSerializable: true; yourself
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> descriptionMaximumGroups [
 <magritteDescription>
 ^ MANumberDescription new accessor: #maximumGroups; label: 'maximumGroups'; kind: Integer; min: 0; beRequired; cfSerializable: true; yourself
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> descriptionMaximumSteps [
 <magritteDescription>
 ^ MANumberDescription new accessor: #maximumSteps; label: 'maximumSteps'; kind: Integer; min: 0; beRequired; cfSerializable: true; yourself
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> descriptionRepositoryName [
 <magritteDescription>
 ^ MAStringDescription new accessor: #repositoryName; label: 'repositoryName'; beRequired; cfSerializable: true; yourself
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> driveIntervalMillis [
 ^ driveIntervalMillis
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> driveIntervalMillis: value [
 driveIntervalMillis := value
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> drivePolicyDigest [
 ^ CSSha256 hexDigestOf: (CSCanonicalCodec encode: {repositoryName. controlPrincipal. executorPrincipal. maximumGroups. journalLimit. maximumSteps. driveThroughTick. driveIntervalMillis})
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> driveThroughTick [
 ^ driveThroughTick
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> driveThroughTick: value [
 driveThroughTick := value
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> executorPrincipal [
 ^ executorPrincipal
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> executorPrincipal: value [
 executorPrincipal := value
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> initialize [
 super initialize.
 serviceClass := CSSimulationService. repositoryName := 'simulations'.
 controlPrincipal := 'simulation-admin'. executorPrincipal := 'simulation-executor'.
 maximumGroups := 16. journalLimit := 16. maximumSteps := 8. driveThroughTick := 0. driveIntervalMillis := 1000
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> journalLimit [
 ^ journalLimit
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> journalLimit: value [
 journalLimit := value
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> maximumGroups [
 ^ maximumGroups
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> maximumGroups: value [
 maximumGroups := value
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> maximumSteps [
 ^ maximumSteps
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> maximumSteps: value [
 maximumSteps := value
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> repositoryName [
 ^ repositoryName
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> repositoryName: value [
 repositoryName := value
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> validateSemanticsOn: result [
 super validateSemanticsOn: result.
 [CSAuthorityChecks text: repositoryName. CSAuthorityChecks text: controlPrincipal. CSAuthorityChecks text: executorPrincipal.
 CSAuthorityChecks require: controlPrincipal ~= executorPrincipal code: 'distinct-principals-required'.
 CSAuthorityChecks require: (maximumGroups isInteger and: [maximumGroups between: 1 and: 128]) code: 'invalid-group-limit'.
 CSAuthorityChecks require: (journalLimit isInteger and: [journalLimit between: 1 and: 64]) code: 'invalid-retention'.
 CSAuthorityChecks require: (maximumSteps isInteger and: [maximumSteps between: 1 and: 64]) code: 'invalid-step-limit'.
 CSKernelMath nonnegative: driveThroughTick.
 CSAuthorityChecks require: (driveIntervalMillis isInteger and: [driveIntervalMillis between: 10 and: 60000]) code: 'invalid-drive-interval']
 on: CSKernelError do: [:error | result addError: error messageText]
]
