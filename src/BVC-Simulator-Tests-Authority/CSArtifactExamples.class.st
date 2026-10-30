Class {
	#name : 'CSArtifactExamples',
	#superclass : 'TestCase',
	#category : 'BVC-Simulator-Tests-Authority',
	#package : 'BVC-Simulator-Tests-Authority'
}

{ #category : 'sharded tests' }
CSArtifactExamples >> idForOrdinal: ordinal [
 | text value |
 text := String new: 32 withAll: $0. value := ordinal.
 32 to: 1 by: -1 do: [:i | text at: i put: ('0123456789abcdef' at: (value bitAnd: 15) + 1). value := value bitShift: -4].
 ^ text
]

{ #category : 'sharded tests' }
CSArtifactExamples >> snapshot [
 ^ CSAuthorityExamples new checkpoint
]

{ #category : 'sharded tests' }
CSArtifactExamples >> sparseSnapshot: population [
 | model graph nodes guard motion events snapshot rows id |
 model := CSCanonicalCodec copy: (self snapshot at: 'model').
 graph := model at: 6.
 guard := (graph at: 'nodes') detect: [:node | (node at: 'operation') = 'core.constant' and: [((node at: 'parameters') at: 'value') = true]].
 motion := (graph at: 'nodes') detect: [:node | (node at: 'operation') = 'core.motion.integrate'].
 events := (graph at: 'nodes') detect: [:node | (node at: 'operation') = 'core.events.apply'].
 guard := CSCanonicalCodec copy: guard. motion := CSCanonicalCodec copy: motion. events := CSCanonicalCodec copy: events.
 motion at: 'inputs' put: {guard at: 'id'}.
 graph at: 'nodes' put: {events. guard. motion}; at: 'maxNodeEvaluations' put: 1000000.
 model at: 2 put: 'sparse-checkpoint-probe'; at: 4 put: 10000; at: 5 put: 10000.
 model := CSModelBundle fromSnapshot: model.
 snapshot := (CSSmalltalkBackend model: model seed: 42) snapshot. rows := Dictionary new.
 0 to: population - 1 do: [:ordinal |
  id := self idForOrdinal: ordinal.
  rows at: id put: {id. {ordinal. 0. 0}. {(ordinal < 16 ifTrue: [1000] ifFalse: [0]). 0. 0}. ''. 0. 'neutral'. 0. 0. {0. 0. 0}}].
 snapshot at: 'entities' put: rows. ^ snapshot
]

{ #category : 'sharded tests' }
CSArtifactExamples >> testFixedPopulationAndMetadataReferences [
 <gtExample>
 | store first snapshot second id |
 snapshot := self snapshot. store := CSArtifactStore new. first := store checkpoint: snapshot. store validateCheckpoint: first base: nil.
 id := (snapshot at: 'entities') keys asArray sorted first. (snapshot at: 'entities') removeKey: id.
 second := store checkpoint: snapshot. self should: [store validateCheckpoint: second base: first] raise: CSAuthorityError.
 snapshot := self snapshot. ((snapshot at: 'entities') at: id) at: 4 put: 'absent'; at: 5 put: 1.
 second := store checkpoint: snapshot. self should: [store validateCheckpoint: second base: first] raise: CSAuthorityError
]

{ #category : 'sharded tests' }
CSArtifactExamples >> testProjectionByteBudget [
 <gtExample>
 | snapshot rows store root page |
 snapshot := self sparseSnapshot: 32. rows := Dictionary new.
 (snapshot at: 'entities') values do: [:row | | id |
  id := self idForOrdinal: rows size * 256. row at: 1 put: id; at: 6 put: (String new: 4096 withAll: $x). rows at: id put: row].
 snapshot at: 'entities' put: rows.
 store := CSArtifactStore new. root := store checkpoint: snapshot. store validateCheckpoint: root base: nil.
 page := store projectionPage: root bucket: '00' after: nil limit: 64.
 self assert: (page at: 'entities') size < 32.
 self assert: (CSCanonicalCodec encode: (page at: 'entities')) size <= 32768.
 self assert: (page at: 'next') notNil
]

{ #category : 'sharded tests' }
CSArtifactExamples >> testProjectionCannotDisagreeWithCheckpoint [
 <gtExample>
 | store first second snapshot node forged |
 snapshot := self snapshot. store := CSArtifactStore new. first := store checkpoint: snapshot.
 store validateCheckpoint: first base: nil.
 (((snapshot at: 'entities') values asArray first) second) at: 1 put: 500.
 second := store checkpoint: snapshot.
 node := store objectAt: second. node at: 'projection' put: ((store objectAt: first) at: 'projection').
 forged := store put: node.
 self should: [store validateCheckpoint: forged base: first] raise: CSAuthorityError
]

{ #category : 'sharded tests' }
CSArtifactExamples >> testProjectionIgnoresRandomCounters [
 <gtExample>
 | store first second snapshot id node prior |
 snapshot := self snapshot. store := CSArtifactStore new. first := store checkpoint: snapshot.
 store validateCheckpoint: first base: nil.
 id := (snapshot at: 'entities') keys asArray sorted first. ((snapshot at: 'entities') at: id) at: 7 put: 1.
 second := store checkpoint: snapshot. store validateCheckpoint: second base: first.
 self deny: first = second.
 node := store objectAt: second. prior := store objectAt: first.
 self assert: (node at: 'projection') equals: (prior at: 'projection').
 self assert: store materializations equals: 0
]

{ #category : 'sharded tests' }
CSArtifactExamples >> testProjectionPageLimitAndStableCursor [
 <gtExample>
 | snapshot store root page |
 snapshot := self sparseSnapshot: 300. store := CSArtifactStore new. root := store checkpoint: snapshot. store validateCheckpoint: root base: nil.
 page := store projectionPage: root bucket: '00' after: nil limit: 1.
 self assert: (page at: 'entities') size equals: 1. self assert: (page at: 'next') notNil.
 self assert: ((store projectionPage: root bucket: '00' after: (page at: 'next') limit: 1) at: 'entities') size equals: 1.
 self should: [store projectionPage: root bucket: '00' after: nil limit: 65] raise: CSAuthorityError
]

{ #category : 'sharded tests' }
CSArtifactExamples >> testRoundTripAndCanonicalRoot [
 <gtExample>
 | store root snapshot |
 snapshot := self snapshot. store := CSArtifactStore new. root := store checkpoint: snapshot.
 self assert: root equals: '589473510e942cb810d309c34d0c3c5412e83f5c52f9946a5154762a3ce0f93f'.
 store validateCheckpoint: root base: nil.
 self assert: store materializations equals: 0.
 self assert: (store materialize: root) equals: snapshot.
 self assert: (store missingFor: root limit: 4) isEmpty
]

{ #category : 'sharded tests' }
CSArtifactExamples >> testSparseUpdateReusesPages [
 <gtExample>
 | snapshot backend store first second before projection count |
 snapshot := self sparseSnapshot: 512. backend := CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: snapshot).
 store := CSArtifactStore new. first := store checkpoint: snapshot. store validateCheckpoint: first base: nil. before := store count.
 backend advance. second := store checkpoint: backend snapshot. store validateCheckpoint: second base: first.
 projection := store indexAt: ((store objectAt: first) at: 'projection').
 count := (store indexAt: ((store objectAt: second) at: 'projection')) keys count: [:bucket | ((store indexAt: ((store objectAt: second) at: 'projection')) at: bucket) ~= (projection at: bucket)].
 self assert: count equals: 16. self assert: store count - before < 50. self assert: store materializations equals: 0
]

{ #category : 'sharded tests' }
CSArtifactExamples >> testUploadIntegrityAndPartialClosure [
 <gtExample>
 | source target root objects bad before |
 source := CSArtifactStore new. root := source checkpoint: self snapshot. target := CSArtifactStore new.
 self assert: (target missingFor: root limit: 4) equals: {root}.
 objects := source objects: {root}. bad := CSCanonicalCodec copy: objects.
 (bad first at: 'parts') at: 1 put: 'n'.
 self should: [target upload: bad] raise: CSAuthorityError.
 self assert: target count equals: 0.
 target upload: objects. self assert: (target missingFor: root limit: 4) notEmpty.
 before := target count.
 self should: [target validateCheckpoint: root base: nil] raise: CSAuthorityError.
 self assert: target count equals: before.
 [(target missingFor: root limit: 4) notEmpty] whileTrue: [target upload: (source objects: (target missingFor: root limit: 4))].
 target validateCheckpoint: root base: nil. self assert: (target materialize: root) equals: self snapshot
]

{ #category : 'sharded tests' }
CSArtifactExamples >> testValidationReusesVerifiedSubtrees [
 <gtExample>
 | snapshot store first second backend |
 snapshot := self sparseSnapshot: 512. store := CSArtifactStore new. first := store checkpoint: snapshot.
 store validateCheckpoint: first base: nil. self assert: (store lastValidation at: 'checkedRows') equals: 512.
 backend := CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: snapshot). backend advance.
 second := store checkpoint: backend snapshot. store validateCheckpoint: second base: first.
 self assert: (store lastValidation at: 'checkedRows') equals: 32.
 self assert: (store lastValidation at: 'newObjects') < 50.
 self assert: store materializations equals: 0
]

{ #category : 'sharded tests' }
CSArtifactExamples >> testValueAndIndexPaging [
 <gtExample>
 | store value root entries |
 store := CSArtifactStore new. value := (1 to: 1500) collect: [:i | (String new: 40 withAll: $x), i printString].
 root := store value: value asArray.
 self assert: (store valueAt: root) equals: value asArray.
 entries := Dictionary new.
 0 to: 255 do: [:i | entries at: ((self idForOrdinal: i) last: 2) put: (store rows: Dictionary new suffix: ((self idForOrdinal: i) last: 2) projection: false)].
 root := store index: entries.
 self assert: (store indexAt: root) equals: entries.
 (store closure: root) do: [:hash | self assert: (store rawAt: hash) size <= 16384]
]
