"
Stable named Runtime endpoint for local and external execution. Persistent group records own revisions, placement fencing and pending batches. Executable services, capabilities, scheduling and client publishers stay activation-local.
"
Class {
	#name : 'CSSimulationService',
	#superclass : 'CRWorkerService',
	#instVars : [
		'port',
		'routing',
		'identity',
		'driveSchedule',
		'drivePending'
	],
	#category : 'BVC-Simulator-Runtime',
	#package : 'BVC-Simulator-Runtime'
}

{ #category : 'simulation runtime' }
CSSimulationService class >> configurationClass [
 ^ CSSimulationConfiguration
]

{ #category : 'simulation runtime' }
CSSimulationService class >> requiredCapabilities [
 ^ {CRServiceActivationCapability. CRRoutingCapability. CRWorkerIdentityCapability}
]

{ #category : 'simulation runtime' }
CSSimulationService >> assertAuthoritative [
 ((self isCurrentResultEpoch: self resultEpoch) and: [configuration notNil and: [configuration isAuthoritative]])
 ifFalse: [CRCapabilityDeniedException signal: 'Current authoritative Simulation service required']
]

{ #category : 'simulation runtime' }
CSSimulationService >> authorize: principal operation: kind [
 | permitted |
 CSAuthorityChecks text: principal.
 permitted := (#('dispatch' 'result') includes: kind)
  ifTrue: [principal = configuration executorPrincipal]
  ifFalse: [(#('view' 'checkpoint' 'changes' 'outcome' 'recovery') includes: kind)
   ifTrue: [principal = configuration controlPrincipal or: [principal = configuration executorPrincipal]]
   ifFalse: [principal = configuration controlPrincipal]].
 permitted ifFalse: [CRCapabilityDeniedException signal: 'Simulation principal is not authorized for this operation']
]

{ #category : 'simulation runtime' }
CSSimulationService >> driveIn: context [
 | repository |
 self assertAuthoritative.
 (port verifiesExecution: context) ifFalse: [CRCapabilityDeniedException signal: 'Runtime-owned Simulation progress required'].
 configuration driveThroughTick = 0 ifTrue: [^ 0].
 repository := CSSimulationRepository named: configuration repositoryName. repository ifNil: [^ 0].
 repository views do: [:view | | tick key prior request envelope payload |
  tick := (view at: 'checkpoint') at: 'tick'. key := (view at: 'world'), '/', (view at: 'group').
  prior := drivePending at: key ifAbsent: [nil].
  (prior notNil and: [prior ~= (view at: 'revision')]) ifTrue: [drivePending removeKey: key. prior := nil].
  (prior isNil and: [(view at: 'backend') = 'smalltalk' and: [(view at: 'phase') = 'active' and: [(view at: 'pending') isNil and: [tick < configuration driveThroughTick]]]]) ifTrue: [
   payload := Dictionary new at: 'targetTick' put: ((tick + configuration maximumSteps) min: configuration driveThroughTick); at: 'policyDigest' put: configuration drivePolicyDigest; yourself.
   request := Dictionary new at: 'world' put: (view at: 'world'); at: 'group' put: (view at: 'group');
    at: 'sequence' put: (view at: 'sequence') + 1; at: 'expectedRevision' put: (view at: 'revision');
    at: 'generation' put: (view at: 'generation'); at: 'owner' put: (view at: 'owner');
    at: 'id' put: 'drive-', (view at: 'generation') printString, '-', (view at: 'revision') printString; at: 'payload' put: payload; yourself.
   envelope := (CSScheduledSimulationAdvanceWorkUnit request: request principal: configuration controlPrincipal) asEnvelope serviceIdentifier: port serviceIdentifier; yourself.
   envelope address: (CRWorkUnitAddress hostIdentifier: identity hostIdentifier workerIdentifier: identity workerIdentifier).
   routing enqueue: envelope. drivePending at: key put: (view at: 'revision')]].
 ^ drivePending size
]

{ #category : 'simulation runtime' }
CSSimulationService >> execute: kind request: supplied principal: principal [
 | request repository group actualKind |
 self assertAuthoritative. self authorize: principal operation: kind.
 request := CSCanonicalCodec copy: supplied.
 kind = 'create' ifTrue: [
  repository := CSSimulationRepository ensureNamed: configuration repositoryName maximumGroups: configuration maximumGroups retention: configuration journalLimit.
  ^ repository create: request principal: principal].
 repository := CSSimulationRepository named: configuration repositoryName.
 repository ifNil: [CSAuthorityError signal: 'unknown-repository'].
 group := repository groupFor: request.
 (#('view' 'checkpoint' 'changes' 'outcome' 'recovery') includes: kind) ifTrue: [^ self query: kind request: request group: group].
 actualKind := kind.
 kind = 'scheduledAdvance' ifTrue: [
  CSAuthorityChecks keys: (request at: 'payload') exactly: #('targetTick' 'policyDigest').
  CSAuthorityChecks require: ((request at: 'payload') at: 'policyDigest') = configuration drivePolicyDigest code: 'obsolete-drive-policy'.
  CSAuthorityChecks require: ((request at: 'payload') at: 'targetTick') <= configuration driveThroughTick code: 'drive-target-changed'.
  (request at: 'payload') removeKey: 'policyDigest'. actualKind := 'advance'].
 ^ group apply: actualKind request: request principal: principal maxSteps: configuration maximumSteps
]

{ #category : 'simulation runtime' }
CSSimulationService >> query: kind request: request group: group [
 | view minimum |
 CSAuthorityChecks keys: request exactly: #('world' 'group' 'minimumRevision' 'argument').
 minimum := request at: 'minimumRevision'. CSKernelMath nonnegative: minimum.
 view := group view.
 CSAuthorityChecks require: (view at: 'revision') >= minimum code: 'read-view-unavailable'.
 (#('view' 'checkpoint') includes: kind) ifTrue: [CSAuthorityChecks require: (request at: 'argument') isNil code: 'invalid-query'. ^ view].
 kind = 'outcome' ifTrue: [^ group receiptAt: (request at: 'argument')].
 kind = 'changes' ifTrue: [^ group changesAfter: (request at: 'argument')].
 CSAuthorityChecks require: (request at: 'argument') isNil code: 'invalid-query'.
 ^ group recoveryPlan
]

{ #category : 'simulation runtime' }
CSSimulationService >> start [
 (configuration isKindOf: CSSimulationConfiguration) ifFalse: [CSAuthorityError signal: 'simulation-configuration-required'].
 super start.
 port := self capability: CRServiceActivationCapability.
 routing := self capability: CRRoutingCapability. identity := self capability: CRWorkerIdentityCapability.
 drivePending := Dictionary new.
 port activateRecords: 4 bytes: 262144.
 self provideCapability: CSSimulationCapability instance: (CSSimulationCapability service: self).
 configuration driveThroughTick > 0 ifTrue: [driveSchedule := port scheduleProgress: CSSimulationDriveWork new key: #simulationDrive idleIntervalMillis: configuration driveIntervalMillis].
 ^ self
]

{ #category : 'simulation runtime' }
CSSimulationService >> stop [
 port ifNotNil: [port deactivate].
 driveSchedule := nil. drivePending := nil. routing := nil. identity := nil. port := nil.
 ^ super stop
]
