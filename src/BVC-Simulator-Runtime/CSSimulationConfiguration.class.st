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
		'driveIntervalMillis',
		'repastLauncher',
		'repastExecutable',
		'repastMpi',
		'repastDirectory',
		'repastRanks',
		'repastMode'
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

{ #category : 'repast integration' }
CSSimulationConfiguration >> descriptionRepastDirectory [
 <magritteDescription>
 ^ MAStringDescription new accessor: #repastDirectory; label: 'durable spool'; cfSerializable: true; yourself
]

{ #category : 'repast integration' }
CSSimulationConfiguration >> descriptionRepastExecutable [
 <magritteDescription>
 ^ MAStringDescription new accessor: #repastExecutable; label: 'native executable'; cfSerializable: true; yourself
]

{ #category : 'repast integration' }
CSSimulationConfiguration >> descriptionRepastLauncher [
 <magritteDescription>
 ^ MAStringDescription new accessor: #repastLauncher; label: 'launcher script'; cfSerializable: true; yourself
]

{ #category : 'resident Repast' }
CSSimulationConfiguration >> descriptionRepastMode [
 <magritteDescription>
 ^ MAStringDescription new accessor: #repastMode; label: 'Repast mode'; cfSerializable: true; yourself
]

{ #category : 'repast integration' }
CSSimulationConfiguration >> descriptionRepastMpi [
 <magritteDescription>
 ^ MAStringDescription new accessor: #repastMpi; label: 'MPI launcher'; cfSerializable: true; yourself
]

{ #category : 'repast integration' }
CSSimulationConfiguration >> descriptionRepastRanks [
 <magritteDescription>
 ^ MANumberDescription new accessor: #repastRanks; label: 'Repast ranks'; kind: Integer; cfSerializable: true; yourself
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

{ #category : 'repast integration' }
CSSimulationConfiguration >> repastDirectory [
 ^ repastDirectory ifNil: ['']
]

{ #category : 'repast integration' }
CSSimulationConfiguration >> repastDirectory: value [
 repastDirectory := value
]

{ #category : 'repast integration' }
CSSimulationConfiguration >> repastEnabled [
 ^ self repastLauncher notEmpty
]

{ #category : 'repast integration' }
CSSimulationConfiguration >> repastExecutable [
 ^ repastExecutable ifNil: ['']
]

{ #category : 'repast integration' }
CSSimulationConfiguration >> repastExecutable: value [
 repastExecutable := value
]

{ #category : 'repast integration' }
CSSimulationConfiguration >> repastLauncher [
 ^ repastLauncher ifNil: ['']
]

{ #category : 'repast integration' }
CSSimulationConfiguration >> repastLauncher: value [
 repastLauncher := value
]

{ #category : 'resident Repast' }
CSSimulationConfiguration >> repastMode [
 ^ repastMode ifNil: ['batch']
]

{ #category : 'resident Repast' }
CSSimulationConfiguration >> repastMode: value [
 repastMode := value
]

{ #category : 'repast integration' }
CSSimulationConfiguration >> repastMpi [
 ^ repastMpi ifNil: ['']
]

{ #category : 'repast integration' }
CSSimulationConfiguration >> repastMpi: value [
 repastMpi := value
]

{ #category : 'resident Repast' }
CSSimulationConfiguration >> repastPolicyDigest [
 ^ CSSha256 hexDigestOf: (CSCanonicalCodec encode: {self drivePolicyDigest. self repastLauncher. self repastExecutable. self repastMpi. self repastDirectory. self repastRanks. self repastMode})
]

{ #category : 'repast integration' }
CSSimulationConfiguration >> repastRanks [
 ^ repastRanks ifNil: [1]
]

{ #category : 'repast integration' }
CSSimulationConfiguration >> repastRanks: value [
 repastRanks := value
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> repositoryName [
 ^ repositoryName
]

{ #category : 'simulation runtime' }
CSSimulationConfiguration >> repositoryName: value [
 repositoryName := value
]

{ #category : 'resident Repast' }
CSSimulationConfiguration >> validateRepastOn: result [
 | paths |
 paths := {self repastLauncher. self repastExecutable. self repastMpi. self repastDirectory}.
 [(paths allSatisfy: [:path | path isEmpty]) ifFalse: [
  CSAuthorityChecks require: (paths allSatisfy: [:path | path isString and: [path notEmpty and: [path first = $/]]]) code: 'absolute-repast-paths-required'].
 CSAuthorityChecks require: (#(1 2 4) includes: self repastRanks) code: 'unqualified-repast-ranks'.
 CSAuthorityChecks require: (#('batch' 'resident') includes: self repastMode) code: 'unknown-repast-mode']
 on: CSKernelError do: [:error | result addError: error messageText]
]

{ #category : 'validation' }
CSSimulationConfiguration >> validateSemanticsOn: result [
 super validateSemanticsOn: result.
 [CSAuthorityChecks text: repositoryName. CSAuthorityChecks text: controlPrincipal. CSAuthorityChecks text: executorPrincipal.
 CSAuthorityChecks require: controlPrincipal ~= executorPrincipal code: 'distinct-principals-required'.
 CSAuthorityChecks require: (maximumGroups isInteger and: [maximumGroups between: 1 and: 128]) code: 'invalid-group-limit'.
 CSAuthorityChecks require: (journalLimit isInteger and: [journalLimit between: 1 and: 64]) code: 'invalid-retention'.
 CSAuthorityChecks require: (maximumSteps isInteger and: [maximumSteps between: 1 and: 64]) code: 'invalid-step-limit'.
 CSKernelMath nonnegative: driveThroughTick.
 CSAuthorityChecks require: (driveIntervalMillis isInteger and: [driveIntervalMillis between: 10 and: 60000]) code: 'invalid-drive-interval']
 on: CSKernelError do: [:error | result addError: error messageText].
 self validateRepastOn: result
]
