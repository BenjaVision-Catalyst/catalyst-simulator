Class {
	#name : 'CSColumnarExamples',
	#superclass : 'TestCase',
	#category : 'BVC-Simulator-Tests-Authority',
	#package : 'BVC-Simulator-Tests-Authority'
}

{ #category : 'columnar examples' }
CSColumnarExamples >> clusteredFixture: count [
 | state population source old row id helper backend root |
 state := CSTypedPopulationExamples new scaleState: count. old := state at: 'entities'. population := CSTypedPopulation capacity: count. helper := CSArtifactExamples new.
 0 to: count - 1 do: [:i | id := helper idForOrdinal: i * 256. row := old at: (helper idForOrdinal: i). row at: 1 put: id. population at: id put: row].
 state at: 'entities' put: population seal. backend := CSTypedSmalltalkBackend fromPopulationState: state. source := CSArtifactStore new.
 root := source checkpoint: backend snapshot. backend advanceThrough: 1. ^ {source. root. source checkpoint: backend snapshot}
]

{ #category : 'columnar examples' }
CSColumnarExamples >> copyRoot: root from: source to: target [
 (source objects: (source closure: root) asArray) do: [:object | target upload: {object}]. ^ target
]

{ #category : 'columnar examples' }
CSColumnarExamples >> fixture: size [
 | state backend store first second |
 state := CSTypedPopulationExamples new scaleState: size. backend := CSTypedSmalltalkBackend fromPopulationState: state. store := CSArtifactStore new.
 first := store checkpoint: backend snapshot. backend advanceThrough: 1. second := store checkpoint: backend snapshot.
 ^ {store. first. second}
]

{ #category : 'columnar examples' }
CSColumnarExamples >> testDenseBucketAtomBudgets [
 <gtExample>
 | fixture source target frame cursor |
 fixture := self clusteredFixture: 600. source := fixture first. target := CSArtifactStore new. cursor := 0.
 [frame := CSColumnarCodec frame: fixture second base: nil cursor: cursor store: source.
  self assert: ((frame at: 'buckets') first at: 'ids') size > 1.
  frame := CSCanonicalCodec copy: frame. target importColumnar: frame base: nil cursor: cursor.
  cursor := frame at: 'next'. cursor < (frame at: 'total')] whileTrue.
 self assert: (target validateCheckpoint: fixture second base: nil) equals: (source objectAt: fixture second).
 self assert: (CSColumnarCodec unpack: (CSColumnarCodec pack: 1 mode: 'set' values: (1 to: 600) asArray) count: 600 hasBase: false) third equals: (1 to: 600) asArray. ^ frame
]

{ #category : 'columnar examples' }
CSColumnarExamples >> testFullAndDelta [
 <gtExample>
 | fixture source target base root cursor frame fullBytes deltaBytes |
 fixture := self fixture: 1025. source := fixture first. base := fixture second. root := fixture third. target := CSArtifactStore new. cursor := 0. fullBytes := 0.
 [frame := CSColumnarCodec frame: base base: nil cursor: cursor store: source.
  target importColumnar: frame base: nil cursor: cursor. fullBytes := fullBytes + (CSCanonicalCodec encode: frame) size. cursor := frame at: 'next'. cursor < (frame at: 'total')] whileTrue.
 self assert: (target validateCheckpoint: base base: nil) = (source objectAt: base).
 cursor := 0. deltaBytes := 0.
 [frame := CSColumnarCodec frame: root base: base cursor: cursor store: source.
  target importColumnar: frame base: base cursor: cursor. deltaBytes := deltaBytes + (CSCanonicalCodec encode: frame) size. cursor := frame at: 'next'. cursor < (frame at: 'total')] whileTrue.
 self assert: (target validateCheckpoint: root base: base) = (source objectAt: root).
 self assert: (target typedBackendAt: root) populationStatistics = (source typedBackendAt: root) populationStatistics.
 self assert: deltaBytes < fullBytes. self assert: target materializations = 0. ^ frame
]

{ #category : 'columnar examples' }
CSColumnarExamples >> testIntegerEncodings [
 <gtExample>
 | values packet decoded |
 values := {-9223372036854775808. 9223372036854775807}, (1 to: 257) asArray.
 packet := CSColumnarCodec pack: 1 mode: 'set' values: values.
 self assert: packet third = 'int64'. decoded := CSColumnarCodec unpack: packet count: values size hasBase: false. self assert: decoded third = values.
 packet := CSColumnarCodec pack: 1 mode: 'add' values: #(1 1 -2 -2 1).
 self assert: (CSColumnarCodec unpack: packet count: 5 hasBase: true) third = #(1 1 -2 -2 1).
 self assert: (CSColumnarCodec pack: 14 mode: 'set' values: #('same' 'same')) third = 'constant'.
 self should: [CSColumnarCodec unpack: packet count: 5 hasBase: false] raise: CSAuthorityError. ^ packet
]

{ #category : 'columnar examples' }
CSColumnarExamples >> testMalformedColumns [
 <gtExample>
 | fixture source target frame before bad |
 fixture := self fixture: 300. source := fixture first. target := CSArtifactStore new. self copyRoot: fixture second from: source to: target.
 frame := CSColumnarCodec frame: fixture third base: fixture second cursor: 0 store: source. before := target count.
 bad := CSCanonicalCodec copy: frame. ((bad at: 'buckets') first) at: 'count' put: 4097.
 self should: [target importColumnar: bad base: fixture second cursor: 0] raise: CSAuthorityError.
 self assert: target count = before.
 self should: [CSColumnarCodec unpack: #(1 'add' 'palette8' #(0 1) #('ff')) count: 1 hasBase: true] raise: CSAuthorityError.
 self should: [CSColumnarCodec unpack: #(1 'set' 'int64' #() #('00')) count: 1 hasBase: false] raise: CSAuthorityError. ^ frame
]

{ #category : 'columnar examples' }
CSColumnarExamples >> testRejectedFrameIsAtomic [
 <gtExample>
 | fixture source target frame before bad |
 fixture := self fixture: 300. source := fixture first. target := CSArtifactStore new.
 self copyRoot: fixture second from: source to: target.
 frame := CSColumnarCodec frame: fixture third base: fixture second cursor: 0 store: source. before := target count.
 bad := CSCanonicalCodec copy: frame. ((bad at: 'buckets') last) at: 'projection' put: ('0' repeat: 64).
 self should: [target importColumnar: bad base: fixture second cursor: 0] raise: CSAuthorityError.
 self assert: target count = before.
 self should: [target importColumnar: frame base: fixture second cursor: 1] raise: CSAuthorityError.
 self assert: target count = before.
 self should: [target importColumnar: frame base: fixture third cursor: 0] raise: CSAuthorityError. self assert: target count = before. ^ target
]

{ #category : 'columnar examples' }
CSColumnarExamples >> testSparseFieldDelta [
 <gtExample>
 | fixture source base state id row root frame target before after |
 fixture := self fixture: 300. source := fixture first. base := fixture second.
 state := source materialize: base. id := (state at: 'entities') keys asArray sorted first.
 row := (state at: 'entities') at: id. row second at: 1 put: row second first + 1.
 state at: 'tick' put: 1. root := source checkpoint: state.
 frame := CSColumnarCodec frame: root base: base cursor: 0 store: source.
 self assert: (frame at: 'buckets') size equals: 1.
 self assert: (((frame at: 'buckets') first at: 'columns') collect: #first) equals: #(1).
 target := CSArtifactStore new. self copyRoot: base from: source to: target.
 target importColumnar: frame base: base cursor: 0.
 self assert: (target validateCheckpoint: root base: base) equals: (source objectAt: root).
 self assert: (target lastValidation at: 'checkedRows') < 300.
 before := source indexAt: ((source objectAt: base) at: 'projection').
 after := source indexAt: ((source objectAt: root) at: 'projection').
 self assert: (before keys count: [:bucket | (before at: bucket) ~= (after at: bucket)]) equals: 1.
 ^ frame
]

{ #category : 'columnar examples' }
CSColumnarExamples >> testStagedRecovery [
 <gtExample>
 | fixture source target helper request group frame payload before pending stale result |
 fixture := self fixture: 300. source := fixture first. target := CSArtifactStore new. self copyRoot: fixture second from: source to: target.
 helper := CSAuthorityExamples new. request := helper createRequest. request at: 'payload' put: ((helper placement: 'external' owner: 3) at: 'root' put: fixture second; yourself).
 group := CSShardedExecutionGroup create: request principal: 'admin' retention: 4 artifacts: target.
 group apply: 'prepare' request: (helper requestFor: group id: 'prepare' payload: (helper target: 1)) principal: 'admin' maxSteps: 4.
 pending := group view at: 'pending'. payload := Dictionary new at: 'batch' put: (pending at: 'batch'); at: 'inputDigest' put: (pending at: 'inputDigest'); yourself.
 group apply: 'dispatch' request: (helper requestFor: group id: 'dispatch' payload: payload) principal: 'executor' maxSteps: 4.
 frame := CSColumnarCodec frame: fixture third base: fixture second cursor: 0 store: source. payload at: 'root' put: fixture third; at: 'frame' put: frame.
 request := helper requestFor: group id: 'frame' payload: payload. result := group apply: 'stage' request: request principal: 'executor' maxSteps: 4.
 self assert: (group apply: 'stage' request: request principal: 'executor' maxSteps: 4) = result.
 self assert: (group view at: 'tick') = 0. self assert: ((group view at: 'pending') at: 'columnarComplete') not.
 before := group view. self should: [group apply: 'stage' request: (helper requestFor: group id: 'out-of-order' payload: payload) principal: 'executor' maxSteps: 4] raise: CSAuthorityError. self assert: group view = before.
 stale := helper requestFor: group id: 'stale' payload: (payload copy removeKey: 'frame'; yourself).
 group apply: 'recover' request: (helper requestFor: group id: 'recover' payload: ((helper placement: 'external' owner: 4) at: 'reason' put: 'columnar recovery'; yourself)) principal: 'admin' maxSteps: 4.
 self assert: (group view at: 'pending') = (before at: 'pending').
 self should: [group apply: 'result' request: stale principal: 'executor' maxSteps: 4] raise: CSAuthorityError.
 [(frame at: 'next') < (frame at: 'total')] whileTrue: [
  frame := CSColumnarCodec frame: fixture third base: fixture second cursor: (frame at: 'next') store: source.
  payload at: 'frame' put: frame.
  group apply: 'stage' request: (helper requestFor: group id: 'frame-', (frame at: 'cursor') printString payload: payload) principal: 'executor' maxSteps: 4].
 payload := payload copy. payload removeKey: 'frame'. payload at: 'decision' put: 'confirmed-result'; at: 'proof' put: 'columnar-receipt'.
 group apply: 'reconcile' request: (helper requestFor: group id: 'reconcile' payload: payload) principal: 'admin' maxSteps: 4.
 self assert: (group view at: 'tick') = 1. self assert: (group view at: 'checkpointDigest') = fixture third. ^ group
]

{ #category : 'columnar examples' }
CSColumnarExamples >> testUnchangedPopulation [
 <gtExample>
 | fixture source base node root frame target |
 fixture := self fixture: 300. source := fixture first. base := fixture second. node := source objectAt: base. node at: 'tick' put: 1. root := source put: node.
 frame := CSColumnarCodec frame: root base: base cursor: 0 store: source. self assert: (frame at: 'buckets') isEmpty.
 target := CSArtifactStore new. self copyRoot: base from: source to: target. target importColumnar: frame base: base cursor: 0.
 self assert: (target validateCheckpoint: root base: base) = node. ^ frame
]

{ #category : 'columnar examples' }
CSColumnarExamples >> testWireEscapingBudget [
 <gtExample>
 | raw frame |
 raw := String new: 4096 withAll: $".
 frame := (1 to: 32) collect: [:i | raw copy].
 self assert: (CSCanonicalCodec encode: frame) size > 131072.
 self assert: (CSColumnarCodec wireFits: ((1 to: 25) collect: [:i | raw copy])) not.
 self assert: (CSColumnarCodec wireFits: ((1 to: 20) collect: [:i | raw copy])).
 self should: [CSColumnarCodec joinParts: {String new: 4097 withAll: $0}] raise: CSAuthorityError.
 ^ raw
]

{ #category : 'columnar evidence' }
CSColumnarExamples >> writeAllFieldsFixturesTo: directory [
 | fixture state source initial target ids frames cursor frame receiver report i row objects typed |
 fixture := self clusteredFixture: 300.
 state := fixture first materialize: fixture second. source := CSArtifactStore new.
 state at: 'seed' put: 18446744073709551615;
  at: 'resources' put: (Dictionary new at: 'capacity-a' put: 100000; at: 'capacity-b' put: 200000; yourself).
 ids := (state at: 'entities') keys asArray sorted.
 typed := [:dictionary | | converted population |
  converted := dictionary copy. population := CSTypedPopulation capacity: 300.
  (dictionary at: 'entities') keysAndValuesDo: [:id :value | population at: id put: value].
  converted at: 'entities' put: population seal. CSTypedSmalltalkBackend fromPopulationState: converted].
 1 to: ids size do: [:ordinal |
  i := ordinal - 1. row := (state at: 'entities') at: (ids at: ordinal).
  row at: 2 put: {i. i negated - 2. i * 3}; at: 3 put: {i negated. i + 100. i * -2};
   at: 4 put: 'capacity-a'; at: 5 put: i + 1; at: 6 put: 'before-', i printString;
   at: 7 put: i + 2; at: 8 put: 900000 + i; at: 9 put: {i \\ 1000. (i + 17) \\ 1000. (i + 42) \\ 1000}].
 ((state at: 'entities') at: ids first) second at: 1 put: -9223372036854775808.
 ((state at: 'entities') at: ids second) second at: 1 put: 9223372036854775807.
 initial := source checkpoint: (typed value: state) snapshot.
 1 to: ids size do: [:ordinal |
  i := ordinal - 1. row := (state at: 'entities') at: (ids at: ordinal).
  row at: 2 put: {i * 111. i * -17. i + 1234}; at: 3 put: {i negated - 10000. i * 29. i + 87};
   at: 4 put: 'capacity-b'; at: 5 put: i + 20;
   at: 6 put: 'after-', i printString, (String with: $"), (String with: (Character value: 92));
   at: 7 put: 4294967295 - i; at: 8 put: i * 17;
   at: 9 put: {(i * 3) \\ 1000. (i * 7) \\ 1000. (i * 11) \\ 1000}].
 ((state at: 'entities') at: ids first) second at: 1 put: 9223372036854775807.
 ((state at: 'entities') at: ids second) second at: 1 put: -9223372036854775808.
 state at: 'tick' put: 1; at: 'outcomes' put: {{1. 'capacity-b'. ids first. 17}}.
 target := source checkpoint: (typed value: state) snapshot.
 frames := OrderedCollection new. receiver := CSArtifactStore new.
 {{initial. nil}. {target. initial}} do: [:pair |
  cursor := 0.
  [frame := CSColumnarCodec frame: pair first base: pair second cursor: cursor store: source.
   frame := CSCanonicalCodec copy: frame. frames add: frame.
   receiver importColumnar: frame base: pair second cursor: cursor.
   cursor := frame at: 'next'. cursor < (frame at: 'total')] whileTrue.
  receiver validateCheckpoint: pair first base: pair second.
  self assert: (receiver checkpoint: (receiver typedBackendAt: pair first) snapshot) equals: pair first].
 objects := source objects: ((source closure: initial) union: (source closure: target)) asArray sorted.
 report := Dictionary new at: 'initial' put: initial; at: 'target' put: target; at: 'objects' put: objects; at: 'frames' put: frames asArray;
  at: 'passed' put: true; at: 'entities' put: 300; at: 'fields' put: 14; yourself.
 directory asFileReference ensureCreateDirectory.
 CRPlatform current writeConnectEvidence: (CSCanonicalCodec copy: report) to: directory, '/gt-wire.json'. ^ {initial. target}
]

{ #category : 'columnar examples' }
CSColumnarExamples >> writeWireFixturesTo: directory [
 | fixture source frames cursor frame result |
 fixture := self clusteredFixture: 600. source := fixture first. frames := OrderedCollection new.
 { {fixture second. nil}. {fixture third. fixture second} } do: [:pair |
  cursor := 0.
  [frame := CSColumnarCodec frame: pair first base: pair second cursor: cursor store: source.
   frames add: frame. cursor := frame at: 'next'. cursor < (frame at: 'total')] whileTrue].
 result := Dictionary new at: 'initial' put: fixture second; at: 'target' put: fixture third;
  at: 'objects' put: (source objects: ((source closure: fixture second) union: (source closure: fixture third)) asArray sorted);
  at: 'frames' put: frames asArray; yourself.
 directory asFileReference ensureCreateDirectory.
 CRPlatform current writeConnectEvidence: (CSCanonicalCodec copy: result) to: directory, '/gt-wire.json'. ^ frames size
]
