Class {
	#name : 'CSTypedPopulationExamples',
	#superclass : 'TestCase',
	#category : 'BVC-Simulator-Tests-Authority',
	#package : 'BVC-Simulator-Tests-Authority'
}

{ #category : 'typed qualification' }
CSTypedPopulationExamples >> scaleState: count [
 | state model population helper id |
 helper := CSArtifactExamples new. state := helper sparseSnapshot: 1.
 model := state at: 'model'. model at: 1 put: 'simulation-portable-1/typed-1'; at: 2 put: 'typed-motion-probe'; at: 4 put: count.
 model := CSModelBundle fromSnapshot: model.
 state at: 'model' put: model snapshot; at: 'modelDigest' put: model digest.
 population := CSTypedPopulation capacity: count.
 0 to: count - 1 do: [:ordinal |
  id := helper idForOrdinal: ordinal.
  population at: id put: {id. {ordinal * 5 - 250000. ordinal negated. ordinal \\ 13}. {1003 + (ordinal \\ 7). -997. 13}. ''. 0. 'neutral'. 0. 0. #(0 0 0)}].
 state at: 'entities' put: population seal. ^ state
]

{ #category : 'typed population' }
CSTypedPopulationExamples >> testAcceleratedHashMatchesPortableFallback [
 #('' 'abc' 'CatalystSimulation-Model-1:') do: [:text |
  self assert: (CSSha256 hexDigestOf: text) equals: (CSSha256 portableHexDigestOf: text)]
]

{ #category : 'typed scale' }
CSTypedPopulationExamples >> testCompleteClosureCacheDoesNotValidateBadProjection [
 | source target state root node projection objects |
 state := self typedState: CSArtifactExamples new snapshot.
 source := CSArtifactStore new. root := source checkpoint: state.
 node := source objectAt: root. projection := source indexAt: (node at: 'projection').
 projection at: projection keys asArray sorted first put: (projection at: projection keys asArray sorted last).
 node at: 'projection' put: (source index: projection). root := source put: node.
 target := CSArtifactStore new. objects := source objects: (source closure: root) asArray sorted.
 1 to: objects size by: 8 do: [:start | target upload: (objects copyFrom: start to: ((start + 7) min: objects size))].
 target cacheComplete: root.
 self assert: (target missingFor: root limit: 4) isEmpty.
 self should: [target validateCheckpoint: root base: nil] raise: CSAuthorityError
]

{ #category : 'typed population' }
CSTypedPopulationExamples >> testPackedRangesCopyAndIsolation [
 | population id row copy |
 id := CSAuthorityExamples new id: 1. population := CSTypedPopulation capacity: 1025.
 row := {id. {-9223372036854775808. 9223372036854775807. -1}. #(-7 0 13). ''. 0. 'neutral'. 4294967295. 4294967295. #(999 0 1)}.
 row at: 6 put: row sixth copy.
 population at: id put: row. population seal.
 self assert: (population at: id) equals: row.
 row sixth at: 1 put: $x.
 population at: id put: (population at: id).
 self assert: (population statistics at: 'internedStrings') equals: 2.
 copy := population copy. row at: 2 put: #(0 0 0). copy at: id put: row.
 self assert: (population at: id) second first equals: -9223372036854775808.
 self assert: population packedBytes equals: 196608.
 self should: [copy at: (CSAuthorityExamples new id: 2) put: row] raise: CSKernelError
]

{ #category : 'typed population' }
CSTypedPopulationExamples >> testProfileCapacityIsExplicit [
 | model builder bundle |
 model := CSArtifactExamples new snapshot at: 'model'.
 model at: 4 put: 100000.
 self should: [CSModelBundle fromSnapshot: model] raise: CSKernelError.
 model at: 1 put: 'simulation-portable-1/typed-1'.
 self assert: (CSModelBundle fromSnapshot: model) isTyped.
 builder := CSModelBuilder named: 'typed-builder'.
 builder limitsEntities: 100000 events: 10000 evaluations: 1000000.
 (((CSArtifactExamples new sparseSnapshot: 1) at: 'model') sixth at: 'nodes') do: [:node | builder addNode: node].
 bundle := builder buildTyped.
 self assert: bundle isTyped. self assert: bundle entityLimit equals: 100000.
 self assert: ((bundle compatibilityReportFor: CSOperationRegistry portable) at: 'compatible').
 self should: [builder build] raise: CSKernelError.
 model at: 4 put: 1000001.
 self should: [CSModelBundle fromSnapshot: model] raise: CSKernelError
]

{ #category : 'typed scale' }
CSTypedPopulationExamples >> testPublicPopulationViewsCannotMutateIdentityIndex [
 | state backend snapshot id exposed |
 state := self typedState: CSArtifactExamples new snapshot.
 backend := CSTypedSmalltalkBackend fromPopulationState: state.
 snapshot := backend snapshot. id := (snapshot at: 'entities') keys asArray sorted first.
 exposed := (snapshot at: 'entities') keys asArray sorted first. exposed at: 1 put: $f.
 (snapshot at: 'entities') keysAndValuesDo: [:key :row | key at: 1 put: $e. row second at: 1 put: 999].
 self assert: (backend snapshot at: 'entities') size equals: (state at: 'entities') size.
 self assert: ((backend snapshot at: 'entities') at: id) equals: ((state at: 'entities') at: id)
]

{ #category : 'typed qualification' }
CSTypedPopulationExamples >> testTypedChunkBoundaryAndLargeIdentityIndex [
 | state p a b |
 state := self scaleState: 1025. p := state at: 'entities'.
 a := CSArtifactExamples new idForOrdinal: 1023. b := CSArtifactExamples new idForOrdinal: 1024.
 self deny: (p at: a) = (p at: b).
 p integrate: b milliseconds: 100.
 self assert: (p at: a) second first equals: 1023 * 5 - 250000.
 self assert: (p at: b) second first equals: (1024 * 5 - 250000) + 100
]

{ #category : 'typed population' }
CSTypedPopulationExamples >> testTypedFailureDoesNotPublish [
 | state typed before id row |
 state := self typedState: CSArtifactExamples new snapshot.
 id := (state at: 'entities') keys asArray sorted first.
 row := (state at: 'entities') at: id. row at: 2 put: {9223372036854775807. 0. 0}; at: 3 put: #(10000 0 0).
 (state at: 'entities') at: id put: row. typed := CSTypedSmalltalkBackend fromPopulationState: state.
 before := (typed snapshot at: 'entities') at: id.
 self should: [typed advance] raise: CSKernelError.
 self assert: typed tick equals: 0.
 self assert: ((typed snapshot at: 'entities') at: id) equals: before
]

{ #category : 'typed population' }
CSTypedPopulationExamples >> testTypedGraphMatchesBoundedGraphAndRestores [
 | legacy typed a b store root flat |
 legacy := CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: CSArtifactExamples new snapshot).
 typed := CSTypedSmalltalkBackend fromPopulationState: (self typedState: legacy snapshot).
 1 to: 12 do: [:tick |
  legacy advance. typed advance. a := legacy snapshot. b := typed snapshot. flat := Dictionary new.
  (b at: 'entities') keysAndValuesDo: [:id :row | flat at: id put: row].
  self assert: flat equals: (a at: 'entities').
  #('tick' 'seed' 'resources' 'events' 'outcomes') do: [:key | self assert: (b at: key) equals: (a at: key)]].
 store := CSArtifactStore new. root := store checkpoint: typed snapshot.
 store validateCheckpoint: root base: nil.
 self assert: (store checkpoint: (store typedBackendAt: root) snapshot) equals: root.
 self assert: store materializations equals: 0.
 self should: [typed checkpoint] raise: CSKernelError
]

{ #category : 'typed population' }
CSTypedPopulationExamples >> typedState: snapshot [
 | result population model |
 result := CSCanonicalCodec copy: snapshot. model := result at: 'model'.
 model at: 1 put: 'simulation-portable-1/typed-1'.
 result at: 'modelDigest' put: (CSModelBundle fromSnapshot: model) digest.
 population := CSTypedPopulation capacity: (((snapshot at: 'entities') size) max: 1).
 (snapshot at: 'entities') keysAndValuesDo: [:id :row | population at: id put: row].
 result at: 'entities' put: population seal. ^ result
]

{ #category : 'typed scale' }
CSTypedPopulationExamples >> writeScaleFixturesTo: directory [
 | state backend store roots objects initial path timings started initialObjects catalog archive |
 path := directory, '/typed100k'. path asFileReference ensureCreateDirectory.
 started := Time millisecondClockValue. state := self scaleState: 100000.
 backend := CSTypedSmalltalkBackend fromPopulationState: state. store := CSArtifactStore new.
 roots := Dictionary new. timings := Dictionary new. archive := Dictionary new.
 #(0 1 3 4 6 8 10 12) do: [:tick | | start root |
  start := Time millisecondClockValue. backend advanceThrough: tick.
  root := store checkpoint: backend snapshot. roots at: tick printString put: root.
  timings at: tick printString put: Time millisecondClockValue - start.
  tick = 0 ifTrue: [
   initial := root. initialObjects := store objects: (store closure: root) asArray sorted.
   CRPlatform current writeConnectEvidence: initialObjects to: path, '/initial-objects.json'.
   1 to: initialObjects size by: 8 do: [:i |
    CRPlatform current writeConnectEvidence: (initialObjects copyFrom: i to: ((i + 7) min: initialObjects size))
     to: path, '/upload-', ((i - 1) // 8 + 1) printString, '.json']].
  (store objects: (store closure: root) asArray sorted) do: [:object | archive at: (object at: 'hash') put: object].
  store collectKeeping: {root}.
  (Delay forMilliseconds: 1) wait.
  CRPlatform current writeConnectEvidence: (Dictionary new at: 'tick' put: tick; at: 'root' put: root; at: 'elapsedMillis' put: Time millisecondClockValue - started; yourself)
   to: path, '/progress.json'].
 objects := archive values asArray.
 CRPlatform current writeConnectEvidence: objects to: path, '/all-objects.json'.
 catalog := Dictionary new at: 'name' put: 'typed100k'; at: 'entities' put: 100000; at: 'initialRoot' put: initial;
 at: 'initialObjects' put: initialObjects size; at: 'uploadBatches' put: ((initialObjects size + 7) // 8);
 at: 'modelDigest' put: (state at: 'modelDigest'); at: 'roots' put: roots; at: 'population' put: backend populationStatistics;
 at: 'timings' put: timings; at: 'elapsedMillis' put: Time millisecondClockValue - started; yourself.
 CRPlatform current writeConnectEvidence: {catalog} to: directory, '/fixtures.json'. ^ catalog
]
