| directory worlds raw prototype cross cases tests |
directory := (Smalltalk globals at: #CSRepastP2FixtureDirectory ifAbsent: [FileLocator temp / 'catalyst-repast-p2-input']) asFileReference.
directory ensureCreateDirectory.
tests := 0.
#(CSKernelExamples CSGraphExamples) do: [:name | | cls |
 cls := Smalltalk at: name.
 (cls selectors select: [:s | s asString beginsWith: 'test']) do: [:selector | cls new perform: selector. tests := tests + 1]].
worlds := CSGraphExamples new fixtureWorlds.
raw := (worlds at: 'conditional-graph') snapshot.
prototype := (raw at: 'entities') values first.
raw at: 'entities' put: Dictionary new.
0 to: 15 do: [:i | | id row |
 id := (String new: 31 withAll: $0), ('0123456789abcdef' at: i + 1) asString.
 row := CSCanonicalCodec copy: prototype.
 row at: 1 put: id; at: 2 put: {i - 2. 0. 0}; at: 3 put: #(13 -3 0); at: 4 put: 'charge'; at: 5 put: 0.
 (raw at: 'entities') at: id put: row].
cross := CSSmalltalkBackend fromCheckpoint: (CSCanonicalCodec encode: raw).
cross cancel: (CSKernelExamples new id: 8).
cross schedule: (CSKernelExamples new id: 8) at: 3 entity: (CSKernelExamples new id: 0) mode: 'obsolete'.
cross cancel: (CSKernelExamples new id: 8).
cross schedule: (CSKernelExamples new id: 9) at: 5 entity: (CSKernelExamples new id: 0) mode: 'late'.
0 to: 15 do: [:i | | suffix entity event |
 suffix := ('0123456789abcdef' at: i + 1) asString.
 entity := (String new: 31 withAll: $0), suffix.
 event := (String new: 30 withAll: $0), '1', suffix.
 cross schedule: event at: 2 entity: entity mode: 'active'].
worlds at: 'cross-rank' put: cross.
cases := OrderedCollection new.
worlds keys asArray sorted do: [:name | | world record checkpoints |
 world := worlds at: name.
 record := Dictionary new at: 'name' put: name; at: 'model' put: world model canonicalBytes;
 at: 'modelDigest' put: world model digest; at: 'initial' put: world checkpoint; yourself.
 checkpoints := Dictionary new.
 1 to: 12 do: [:tick | world advance. checkpoints at: tick printString put: world checkpoint].
 record at: 'checkpoints' put: checkpoints. cases add: record].
(directory / 'registry.canon') writeStreamDo: [:out | out nextPutAll: (CSCanonicalCodec encode: CSOperationRegistry portable snapshot)].
(directory / 'manifest.json') writeStreamDo: [:out | out nextPutAll: (STONJSON toString: (Dictionary new at: 'cases' put: cases asArray; at: 'compatibility' put: CSGraphExamples new compatibilityFixtures; at: 'gtTests' put: tests; yourself))].
{tests. cases collect: [:c | {c at: 'name'. c at: 'modelDigest'}]}