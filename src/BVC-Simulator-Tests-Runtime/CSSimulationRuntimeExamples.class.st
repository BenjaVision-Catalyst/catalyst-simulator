Class {
	#name : 'CSSimulationRuntimeExamples',
	#superclass : 'TestCase',
	#category : 'BVC-Simulator-Tests-Runtime',
	#package : 'BVC-Simulator-Tests-Runtime'
}

{ #category : 'simulation tests' }
CSSimulationRuntimeExamples >> configuration [
 ^ CSSimulationConfiguration new identifier: #simulation; label: 'Simulation'; authoritative: true;
 repositoryName: 'runtime-example'; controlPrincipal: 'admin'; executorPrincipal: 'executor'; yourself
]

{ #category : 'simulation tests' }
CSSimulationRuntimeExamples >> createOn: worker [
 ^ self execute: (CSCreateSimulationWorkUnit request: CSAuthorityExamples new createRequest principal: 'admin') on: worker named: 'simulation'
]

{ #category : 'simulation tests' }
CSSimulationRuntimeExamples >> execute: unit on: worker named: identifier [
 | execution |
 execution := CRWorkUnitExecution envelope: (unit asEnvelope serviceIdentifier: identifier; yourself).
 worker prepareWorkUnitExecution: execution.
 ^ unit executeInContext: execution context
]

{ #category : 'simulation tests' }
CSSimulationRuntimeExamples >> queryRequest [
 ^ Dictionary new at: 'world' put: (CSAuthorityExamples new id: 1); at: 'group' put: (CSAuthorityExamples new id: 2);
 at: 'minimumRevision' put: 0; at: 'argument' put: nil; yourself
]

{ #category : 'simulation tests' }
CSSimulationRuntimeExamples >> testChangedDrivePolicyRejectsQueuedProgression [
 <gtExample>
 | helper |
 helper := CSAuthorityExamples new.
 self withWorkerDo: [:worker | | group request payload service |
  self createOn: worker. group := (CSSimulationRepository named: 'runtime-example') groupFor: helper createRequest.
  payload := helper target: 1. payload at: 'policyDigest' put: 'obsolete'.
  request := helper requestFor: group id: 'scheduled' payload: payload.
  self should: [self execute: (CSScheduledSimulationAdvanceWorkUnit request: request principal: 'admin') on: worker named: 'simulation'] raise: CSAuthorityError.
  self assert: (group view at: 'revision') equals: 1.
  service := worker services serviceAtIdentifier: 'simulation'.
  self should: [service driveIn: nil] raise: CRCapabilityDeniedException]
]

{ #category : 'simulation tests' }
CSSimulationRuntimeExamples >> testCommittedCompletionPublishesAfterFinalization [
 <gtExample>
 | publisher completion envelope |
 publisher := CSSimulationRecordingPublisher new. completion := CSSimulationCommittedCompletion publisher: publisher.
 self assert: completion afterCommit. self assert: completion afterFinalization.
 self withWorkerDo: [:worker |
  envelope := (CSCreateSimulationWorkUnit request: CSAuthorityExamples new createRequest principal: 'admin') asEnvelope serviceIdentifier: 'simulation'; resultCompletion: completion; yourself.
  (CRWorkRouter deploymentTopology: worker runtime deploymentTopology) enqueue: envelope.
  self assert: publisher results isEmpty.
  worker executeWorkUnitInEnvelope: worker workerHandle workQueue nextForExecutionOrNil.
  self assert: completion state equals: #completed.
  self assert: publisher results size equals: 1.
  self assert: (publisher results first at: 'revision') equals: 1.
  self assert: worker isWorkQueueEmpty]
]

{ #category : 'tests' }
CSSimulationRuntimeExamples >> testConfigurationRoundTripAndBounds [
 <gtExample>
 | cfg copied result |
 cfg := self configuration.
 copied := CRRuntimeConfigurationCodec decodeObject: (CRRuntimeConfigurationCodec encodeObject: cfg).
 self assert: copied class equals: CSSimulationConfiguration.
 self assert: copied repositoryName equals: cfg repositoryName.
 self assert: copied drivePolicyDigest equals: cfg drivePolicyDigest.
 self deny: copied == cfg.
 result := CRRuntimeConfigurationValidationResult new. cfg validateSemanticsOn: result.
 self assert: result isValid.
 cfg maximumSteps: 0; controlPrincipal: cfg executorPrincipal.
 result := CRRuntimeConfigurationValidationResult new. cfg validateSemanticsOn: result.
 self deny: result isValid
]

{ #category : 'simulation tests' }
CSSimulationRuntimeExamples >> testEpochExpiresAndNonAuthoritativeConfigurationRefuses [
 <gtExample>
 self withWorkerDo: [:worker | | service old current |
  self createOn: worker. service := worker services serviceAtIdentifier: 'simulation'.
  old := service providedCapabilityIfPresent: CSSimulationCapability.
  worker services stopService: service.
  self should: [old execute: 'view' request: self queryRequest principal: 'admin'] raise: CRCapabilityDeniedException.
  worker services startServiceIdentifier: 'simulation'.
  self should: [old execute: 'view' request: self queryRequest principal: 'admin'] raise: CRCapabilityDeniedException.
  current := service providedCapabilityIfPresent: CSSimulationCapability.
  self assert: ((current execute: 'view' request: self queryRequest principal: 'admin') at: 'revision') equals: 1.
  worker services applyConfiguration: (self configuration authoritative: false; yourself) serviceIdentifier: 'simulation' version: 2.
  self should: [(service providedCapabilityIfPresent: CSSimulationCapability) execute: 'view' request: self queryRequest principal: 'admin'] raise: CRCapabilityDeniedException]
]

{ #category : 'tests' }
CSSimulationRuntimeExamples >> testFailedPipelineDoesNotPublishResult [
 <gtExample>
 | publisher completion envelope |
 publisher := CSSimulationRecordingPublisher new. completion := CSSimulationCommittedCompletion publisher: publisher.
 self withWorkerDo: [:worker |
  worker failAt: #activation.
  envelope := (CSCreateSimulationWorkUnit request: CSAuthorityExamples new createRequest principal: 'admin') asEnvelope serviceIdentifier: 'simulation'; resultCompletion: completion; yourself.
  (CRWorkRouter deploymentTopology: worker runtime deploymentTopology) enqueue: envelope.
  self should: [worker executeWorkUnitInEnvelope: worker workerHandle workQueue nextForExecutionOrNil] raise: Error.
  self assert: publisher results isEmpty.
  self assert: completion state equals: #abandoned]
]

{ #category : 'simulation tests' }
CSSimulationRuntimeExamples >> testMinimumReadRevisionAndOutcomeQuery [
 <gtExample>
 self withWorkerDo: [:worker | | query view |
  self createOn: worker. query := self queryRequest. query at: 'minimumRevision' put: 99.
  self should: [self execute: (CSReadSimulationWorkUnit request: query principal: 'admin') on: worker named: 'simulation'] raise: CSAuthorityError.
  query at: 'minimumRevision' put: 0; at: 'argument' put: 1.
  view := self execute: (CSQuerySimulationOutcomeWorkUnit request: query principal: 'admin') on: worker named: 'simulation'.
  self assert: (view at: 'status') equals: 'accepted'.
  self assert: (view at: 'revision') equals: 1]
]

{ #category : 'simulation tests' }
CSSimulationRuntimeExamples >> testNamedServiceAndCommonLocalExternalReadEndpoint [
 <gtExample>
 | helper |
 helper := CSAuthorityExamples new.
 self withWorkerDo: [:worker | | group view |
  self createOn: worker. group := (CSSimulationRepository named: 'runtime-example') groupFor: helper createRequest.
  view := self execute: (CSReadSimulationWorkUnit request: self queryRequest principal: 'admin') on: worker named: 'simulation'.
  self assert: (view at: 'backend') equals: 'smalltalk'.
  self should: [self execute: (CSReadSimulationWorkUnit request: self queryRequest principal: 'admin') on: worker named: 'other'] raise: CSAuthorityError.
  self execute: (CSMigrateSimulationWorkUnit request: (helper requestFor: group id: 'transfer' payload: (helper placement: 'external' owner: 4)) principal: 'admin') on: worker named: 'simulation'.
  view := group view.
  self execute: (CSActivateSimulationPlacementWorkUnit request: (helper requestFor: group id: 'activate' payload: (Dictionary new at: 'checkpointDigest' put: (view at: 'checkpointDigest'); at: 'modelDigest' put: (view at: 'modelDigest'); yourself)) principal: 'admin') on: worker named: 'simulation'.
  view := self execute: (CSReadSimulationWorkUnit request: self queryRequest principal: 'executor') on: worker named: 'simulation'.
  self assert: (view at: 'backend') equals: 'external'.
  self assert: (view at: 'checkpoint') equals: helper checkpoint.
  self assert: (view at: 'generation') equals: 2]
]

{ #category : 'simulation tests' }
CSSimulationRuntimeExamples >> testPrincipalAndCapabilityAuthority [
 <gtExample>
 self withWorkerDo: [:worker | | service capability |
  service := worker services serviceAtIdentifier: 'simulation'.
  capability := service providedCapabilityIfPresent: CSSimulationCapability.
  self should: [capability execute: 'create' request: CSAuthorityExamples new createRequest principal: 'executor'] raise: CRCapabilityDeniedException.
  self should: [capability execute: 'create' request: CSAuthorityExamples new createRequest principal: 'stranger'] raise: CRCapabilityDeniedException.
  self should: [self execute: CSSimulationDeniedWorkUnit new on: worker named: 'simulation'] raise: CRCapabilityDeniedException.
  self deny: (CSSimulationCapability canBeGrantedToServiceClass: CSSimulationService).
  self deny: (CSSimulationCapability canBeGrantedToWorkUnitClass: CSSimulationWorkUnit).
  self should: [capability driveIn: nil] raise: CRCapabilityDeniedException]
]

{ #category : 'simulation tests' }
CSSimulationRuntimeExamples >> testRequestCapturesOnlyCanonicalData [
 <gtExample>
 | data work |
 data := CSAuthorityExamples new createRequest.
 work := CSCreateSimulationWorkUnit request: data principal: 'admin'.
 (data at: 'payload') at: 'owner' put: (CSAuthorityExamples new id: 9).
 self deny: work request = data.
 self should: [CSCreateSimulationWorkUnit request: (Dictionary new at: 'closure' put: [42]; yourself) principal: 'admin'] raise: CSKernelError.
 self assert: work class requiresTransaction. self deny: work class allowsConflictReplay
]

{ #category : 'sharded tests' }
CSSimulationRuntimeExamples >> testShardedUploadAndAcceptedProjectionEndpoint [
 <gtExample>
 | helper source root objects request read group bucket response |
 helper := CSAuthorityExamples new. source := CSArtifactStore new. root := source checkpoint: helper checkpoint.
 objects := source objects: (source closure: root) asArray sorted.
 self withWorkerDo: [:worker |
  request := Dictionary new at: 'world' put: (helper id: 1); at: 'group' put: (helper id: 2); at: 'objects' put: (objects first: 1); yourself.
  self should: [self execute: (CSUploadSimulationArtifactsWorkUnit request: request principal: 'executor') on: worker named: 'simulation'] raise: CRCapabilityDeniedException.
  1 to: objects size by: 8 do: [:start |
   request at: 'objects' put: (objects copyFrom: start to: ((start + 7) min: objects size)).
   self execute: (CSUploadSimulationArtifactsWorkUnit request: request principal: 'admin') on: worker named: 'simulation'].
  request := helper createRequest.
  request at: 'payload' put: ((helper placement: 'smalltalk' owner: 3) at: 'root' put: root; yourself).
  self execute: (CSCreateShardedSimulationWorkUnit request: request principal: 'admin') on: worker named: 'simulation'.
  group := (CSSimulationRepository named: 'runtime-example') groupFor: request.
  read := self queryRequest. read at: 'argument' put: (Dictionary new at: 'root' put: root; yourself).
  response := self execute: (CSReadSimulationManifestWorkUnit request: read principal: 'admin') on: worker named: 'simulation'.
  self assert: ((response at: 'manifest') at: 'entityCount') equals: 2.
  bucket := (helper checkpoint at: 'entities') keys asArray sorted first last: 2.
  read at: 'argument' put: (Dictionary new at: 'root' put: root; at: 'bucket' put: bucket; at: 'after' put: nil; at: 'limit' put: 64; yourself).
  response := self execute: (CSReadSimulationProjectionWorkUnit request: read principal: 'executor') on: worker named: 'simulation'.
  self assert: (response at: 'entities') notEmpty. self assert: group artifacts materializations equals: 0.
  read at: 'argument' put: 0.
  response := self execute: (CSReadSimulationProjectionChangesWorkUnit request: read principal: 'admin') on: worker named: 'simulation'.
  self assert: (response at: 'resnapshot') == true.
  self should: [self execute: (CSUploadSimulationArtifactsWorkUnit request: (Dictionary new at: 'world' put: (helper id: 1); at: 'group' put: (helper id: 2); at: 'objects' put: (objects first: 1); yourself) principal: 'admin') on: worker named: 'simulation'] raise: CSAuthorityError]
]

{ #category : 'simulation tests' }
CSSimulationRuntimeExamples >> withWorkerDo: block [
 | worker result other |
 worker := CRFinalizedResultTestWorker new.
 worker workerHandle workerIdentifier: #simulationTest.
 worker bindRuntime: CRRuntime new hostIdentifier: #simulationTest.
 worker services installServiceClass: CSSimulationService serviceIdentifier: 'simulation' configuration: self configuration.
 other := self configuration identifier: #other; repositoryName: 'runtime-other'; yourself.
 worker services installServiceClass: CSSimulationService serviceIdentifier: 'other' configuration: other.
 worker start. worker workerHandle lifecycleStatus: CRStatus running.
 worker services startAll. worker publishHandleToTopology.
 [result := block value: worker] ensure: [
  [worker isWorkQueueEmpty] whileFalse: [worker executeWorkUnitInEnvelope: worker workerHandle workQueue nextForExecutionOrNil].
  worker stopAndUninstallServices. worker unpublishHandleFromTopology.
  CSSimulationRepository removeNamed: 'runtime-example'. CSSimulationRepository removeNamed: 'runtime-other'].
 ^ result
]
