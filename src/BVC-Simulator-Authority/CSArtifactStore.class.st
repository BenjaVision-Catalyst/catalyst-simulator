Class {
	#name : 'CSArtifactStore',
	#superclass : 'Object',
	#instVars : [
		'buckets',
		'summaries',
		'closures',
		'materializations',
		'lastValidation'
	],
	#category : 'BVC-Simulator-Authority',
	#package : 'BVC-Simulator-Authority'
}

{ #category : 'sharded checkpoints' }
CSArtifactStore >> assertHash: hash [
 CSAuthorityChecks require: (hash isString and: [hash size = 64 and: [hash allSatisfy: [:c | '0123456789abcdef' includes: c]]]) code: 'invalid-artifact-hash'
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> checkpoint: snapshot [
 | entities projection grouped |
 entities := Dictionary new. projection := Dictionary new. grouped := Dictionary new.
 (snapshot at: 'entities') keysAndValuesDo: [:id :row | (grouped at: (id last: 2) ifAbsentPut: [Dictionary new]) at: id put: row].
 grouped keysAndValuesDo: [:bucket :rows | | poses |
  poses := Dictionary new. rows keysAndValuesDo: [:id :row | poses at: id put: {row first. row second. row third. row sixth}].
  entities at: bucket put: (self rows: rows suffix: bucket projection: false).
  projection at: bucket put: (self rows: poses suffix: bucket projection: true)].
 ^ self put: (Dictionary new at: 'kind' put: 'checkpoint'; at: 'version' put: 1;
 at: 'model' put: (self value: (snapshot at: 'model')); at: 'modelDigest' put: (snapshot at: 'modelDigest');
 at: 'tick' put: (snapshot at: 'tick'); at: 'seed' put: (snapshot at: 'seed');
 at: 'entities' put: (self index: entities); at: 'projection' put: (self index: projection);
 at: 'entityCount' put: (snapshot at: 'entities') size; at: 'resources' put: (self value: (snapshot at: 'resources'));
 at: 'events' put: (self value: (snapshot at: 'events')); at: 'outcomes' put: (self value: (snapshot at: 'outcomes')); yourself)
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> closure: root [
 | seen pending |
 seen := Set new. pending := OrderedCollection with: {root. 0}.
 [pending notEmpty] whileTrue: [| item hash depth |
  item := pending removeLast. hash := item first. depth := item second.
  CSAuthorityChecks require: depth <= 64 code: 'artifact-depth'.
  (seen includes: hash) ifFalse: [
   seen add: hash. (self references: (self objectAt: hash)) do: [:child | pending add: {child. depth + 1}]]].
 ^ seen
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> collectKeeping: roots [
 | keep removed |
 keep := Set new. roots do: [:root | keep addAll: (self closure: root)].
 removed := self count - keep size.
 buckets keys asArray do: [:prefix | | bucket |
  bucket := (buckets at: prefix) select: [:raw | keep includes: (CSSha256 hexDigestOf: raw)].
  bucket isEmpty ifTrue: [buckets removeKey: prefix] ifFalse: [buckets at: prefix put: bucket]].
 summaries keys asArray do: [:hash | (keep includes: hash) ifFalse: [summaries removeKey: hash]].
 (closures isKindOf: Dictionary)
  ifTrue: [closures keys asArray do: [:hash | (keep includes: hash) ifFalse: [closures removeKey: hash]]]
  ifFalse: [closures := Dictionary new]. ^ removed
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> count [
 ^ buckets values inject: 0 into: [:sum :bucket | sum + bucket size]
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> includes: hash [
 | bucket |
 self assertHash: hash. bucket := buckets at: (hash first: 2) ifAbsent: [^ false].
 ^ bucket includesKey: hash
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> index: entries [
 | leaf keys middle left right |
 leaf := Dictionary new at: 'kind' put: 'index'; at: 'entries' put: entries; yourself.
 (CSCanonicalCodec encode: leaf) size <= 16384 ifTrue: [^ self put: leaf].
 keys := entries keys asArray sorted. middle := keys size // 2. left := Dictionary new. right := Dictionary new.
 (keys first: middle) do: [:key | left at: key put: (entries at: key)].
 (keys allButFirst: middle) do: [:key | right at: key put: (entries at: key)].
 ^ self put: (Dictionary new at: 'kind' put: 'indexBranch'; at: 'left' put: (self index: left); at: 'right' put: (self index: right); yourself)
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> indexAt: hash [
 | node left right |
 node := self objectAt: hash.
 (node at: 'kind') = 'index' ifTrue: [^ node at: 'entries'].
 CSAuthorityChecks require: (node at: 'kind') = 'indexBranch' code: 'artifact-index-kind'.
 left := self indexAt: (node at: 'left'). right := self indexAt: (node at: 'right').
 CSAuthorityChecks require: (left keys noneSatisfy: [:key | right includesKey: key]) code: 'artifact-duplicate'.
 right keysAndValuesDo: [:key :value | left at: key put: value]. ^ left
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> initialize [
 super initialize. buckets := Dictionary new. summaries := Dictionary new. closures := Dictionary new. materializations := 0. lastValidation := nil
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> lastValidation [
 ^ lastValidation ifNil: [Dictionary new] ifNotNil: [CSCanonicalCodec copy: lastValidation]
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> materializations [
 ^ materializations
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> materialize: root [
 | node entities |
 materializations := materializations + 1.
 node := self objectAt: root. entities := Dictionary new.
 (self indexAt: (node at: 'entities')) values do: [:hash | (self rowsAt: hash) keysAndValuesDo: [:id :row | entities at: id put: row]].
 ^ Dictionary new at: 'version' put: 2; at: 'model' put: (self valueAt: (node at: 'model')); at: 'modelDigest' put: (node at: 'modelDigest');
 at: 'tick' put: (node at: 'tick'); at: 'seed' put: (node at: 'seed'); at: 'entities' put: entities;
 at: 'resources' put: (self valueAt: (node at: 'resources')); at: 'events' put: (self valueAt: (node at: 'events')); at: 'outcomes' put: (self valueAt: (node at: 'outcomes')); yourself
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> missingFor: root limit: maximum [
 | missing seen pending |
 missing := OrderedCollection new. seen := Set new. pending := OrderedCollection with: {root. 0}.
 [pending notEmpty and: [missing size < maximum]] whileTrue: [| item hash depth |
  item := pending removeLast. hash := item first. depth := item second.
  CSAuthorityChecks require: depth <= 64 code: 'artifact-depth'.
  ((seen includes: hash) or: [(closures isKindOf: Dictionary) and: [closures includesKey: hash]]) ifFalse: [
   seen add: hash.
   (self includes: hash) ifTrue: [(self references: (self objectAt: hash)) do: [:child | pending add: {child. depth + 1}]] ifFalse: [missing add: hash]]].
 ^ missing asArray
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> newClosuresFor: root [
 | computed active visit |
 computed := Dictionary new. active := Set new.
 visit := [:hash | | height |
  (closures isKindOf: Dictionary) ifTrue: [(closures includesKey: hash) ifTrue: [height := closures at: hash]].
  height ifNil: [height := computed at: hash ifAbsent: [nil]].
  height ifNil: [
   CSAuthorityChecks require: (active includes: hash) not code: 'artifact-cycle'.
   CSAuthorityChecks require: active size <= 64 code: 'artifact-depth'.
   active add: hash. height := 0.
   (self references: (self objectAt: hash)) do: [:child | height := height max: (visit value: child) + 1].
   active remove: hash. CSAuthorityChecks require: height <= 64 code: 'artifact-depth'.
   computed at: hash put: height].
  height].
 visit value: root. ^ computed
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> objectAt: hash [
 ^ CSCanonicalCodec decode: (self rawAt: hash)
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> objects: hashes [
 ^ hashes collect: [:hash | | raw parts |
  raw := self rawAt: hash. parts := OrderedCollection new.
  1 to: raw size by: 4096 do: [:i | parts add: (raw copyFrom: i to: ((i + 4095) min: raw size))].
  Dictionary new at: 'hash' put: hash; at: 'parts' put: parts asArray; yourself]
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> projectionPage: root bucket: bucket after: cursor limit: limit [
 | manifest roots summary ids rows next candidate |
 CSAuthorityChecks require: (limit isInteger and: [limit between: 1 and: 64]) code: 'projection-page-limit'.
 manifest := self objectAt: root. roots := self indexAt: (manifest at: 'projection').
 (roots includesKey: bucket) ifFalse: [^ Dictionary new at: 'entities' put: #(); at: 'next' put: nil; yourself].
 summary := self summaryFor: (roots at: bucket) suffix: bucket projection: true.
 ids := (summary at: 'ids') select: [:id | cursor isNil or: [id > cursor]].
 rows := OrderedCollection new. next := nil.
 ids do: [:id |
  (rows size < limit and: [next isNil]) ifTrue: [
   candidate := (rows asArray copyWith: (self row: id at: (roots at: bucket))).
   (CSCanonicalCodec encode: candidate) size <= 32768
    ifTrue: [rows add: candidate last]
    ifFalse: [next := rows last first]]].
 rows size < ids size ifTrue: [next := rows last first].
 ^ Dictionary new at: 'entities' put: rows asArray; at: 'next' put: next; yourself
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> put: node [
 | raw | raw := CSCanonicalCodec encode: node. ^ self putRaw: raw hash: (CSSha256 hexDigestOf: raw)
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> putRaw: raw hash: hash [
 | bucket |
 self assertHash: hash.
 CSAuthorityChecks require: (raw size <= 16384 and: [(CSSha256 hexDigestOf: raw) = hash]) code: 'artifact-integrity'.
 self validateNode: (CSCanonicalCodec decode: raw).
 bucket := buckets at: (hash first: 2) ifAbsentPut: [Dictionary new].
 (bucket includesKey: hash) ifTrue: [CSAuthorityChecks require: (bucket at: hash) = raw code: 'artifact-collision'] ifFalse: [bucket at: hash copy put: raw copy].
 ^ hash
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> rawAt: hash [
 self assertHash: hash.
 ^ ((buckets at: (hash first: 2) ifAbsent: [CSAuthorityError signal: 'artifact-unavailable']) at: hash ifAbsent: [CSAuthorityError signal: 'artifact-unavailable']) copy
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> references: node [
 | kind |
 kind := node at: 'kind'.
 (#('array' 'map' 'indexBranch') includes: kind) ifTrue: [^ {node at: 'left'. node at: 'right'}].
 (#('item' 'entry') includes: kind) ifTrue: [^ {node at: 'value'}].
 (#('entitiesBranch' 'projectionBranch') includes: kind) ifTrue: [
  CSAuthorityChecks require: ((node at: 'children') isKindOf: Dictionary) code: 'artifact-children'.
  ^ (node at: 'children') values asArray].
 kind = 'index' ifTrue: [CSAuthorityChecks require: ((node at: 'entries') isKindOf: Dictionary) code: 'artifact-index'. ^ (node at: 'entries') values asArray].
 kind = 'checkpoint' ifTrue: [^ #('model' 'entities' 'projection' 'resources' 'events' 'outcomes') collect: [:key | node at: key]].
 ^ #()
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> row: id at: hash [
 | node suffix children digit |
 node := self objectAt: hash. suffix := node at: 'suffix'.
 (id endsWith: suffix) ifFalse: [^ nil].
 (node includesKey: 'rows') ifTrue: [^ (node at: 'rows') at: id ifAbsent: [nil]].
 children := node at: 'children'. digit := (id at: 32 - suffix size) asString.
 ^ children at: digit ifPresent: [:child | self row: id at: child] ifAbsent: [nil]
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> rows: rows suffix: suffix projection: projection [
 | kind leaf children |
 kind := projection ifTrue: ['projection'] ifFalse: ['entities'].
 leaf := Dictionary new at: 'kind' put: kind; at: 'suffix' put: suffix; at: 'rows' put: rows; yourself.
 (rows size <= 128 and: [(CSCanonicalCodec encode: leaf) size <= 16384]) ifTrue: [^ self put: leaf].
 CSAuthorityChecks require: suffix size < 32 code: 'artifact-row-too-large'.
 children := Dictionary new.
 '0123456789abcdef' do: [:digit | | selected tail |
  tail := digit asString, suffix. selected := Dictionary new. rows keysAndValuesDo: [:id :row | (id endsWith: tail) ifTrue: [selected at: id put: row]].
  selected notEmpty ifTrue: [children at: digit asString put: (self rows: selected suffix: tail projection: projection)]].
 ^ self put: (Dictionary new at: 'kind' put: kind, 'Branch'; at: 'suffix' put: suffix; at: 'children' put: children; yourself)
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> rowsAt: hash [
 | node result |
 node := self objectAt: hash.
 (node includesKey: 'rows') ifTrue: [^ node at: 'rows'].
 CSAuthorityChecks require: (#('entitiesBranch' 'projectionBranch') includes: (node at: 'kind')) code: 'artifact-row-kind'.
 result := Dictionary new.
 (node at: 'children') values do: [:child | (self rowsAt: child) keysAndValuesDo: [:id :row | result at: id put: row]].
 ^ result
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> summaryFor: hash suffix: suffix projection: projection [
 | cached node kind ids resources rows child prefix validator |
 cached := summaries at: hash ifAbsent: [nil].
 cached ifNotNil: [
  CSAuthorityChecks require: ((cached at: 'suffix') = suffix and: [(cached at: 'projection') = projection]) code: 'artifact-row-context'.
  ^ cached].
 node := self objectAt: hash. kind := projection ifTrue: ['projection'] ifFalse: ['entities'].
 CSAuthorityChecks require: ((node at: 'kind') = kind or: [(node at: 'kind') = (kind, 'Branch')]) code: 'artifact-row-kind'.
 CSAuthorityChecks require: (node at: 'suffix') = suffix code: 'artifact-row-suffix'.
 ids := OrderedCollection new. resources := Set new.
 (node at: 'kind') = kind
 ifTrue: [
  rows := node at: 'rows'. validator := CSSmalltalkBackend new.
  rows keysAndValuesDo: [:id :row |
   CSKernelMath identifier: id.
   CSAuthorityChecks require: (id endsWith: suffix) code: 'artifact-row-suffix'.
   projection ifTrue: [
    CSAuthorityChecks require: (row class == Array and: [row size = 4 and: [row first = id and: [row fourth isString]]]) code: 'projection-row'.
    CSKernelMath vector: row second; vector: row third]
   ifFalse: [
    CSAuthorityChecks require: (row class == Array and: [row size = 9]) code: 'artifact-row'.
    prefix := Dictionary new at: row fourth put: 0; yourself.
    validator validateEntity: row id: id resources: prefix.
    row fifth > 0 ifTrue: [resources add: row fourth]].
   ids add: id]]
 ifFalse: [
  CSAuthorityChecks require: (suffix size < 32 and: [(node at: 'children') size between: 1 and: 16]) code: 'artifact-branch'.
  (node at: 'children') keysAndValuesDo: [:digit :root |
   CSAuthorityChecks require: (digit isString and: [digit size = 1 and: ['0123456789abcdef' includes: digit first]]) code: 'artifact-branch-digit'.
   child := self summaryFor: root suffix: digit, suffix projection: projection.
   ids addAll: (child at: 'ids'). resources addAll: (child at: 'resources')]].
 cached := Dictionary new at: 'suffix' put: suffix; at: 'projection' put: projection;
 at: 'ids' put: ids asArray sorted; at: 'resources' put: resources asArray sorted; yourself.
 summaries at: hash put: cached. ^ cached
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> upload: objects [
 | decoded missing |
 CSAuthorityChecks require: (objects class == Array and: [objects size between: 1 and: 8]) code: 'artifact-batch-budget'.
 CSAuthorityChecks require: (CSCanonicalCodec encode: objects) size <= 196608 code: 'artifact-byte-budget'.
 decoded := objects collect: [:object | | raw hash |
  CSAuthorityChecks keys: object exactly: #('hash' 'parts'). hash := object at: 'hash'. self assertHash: hash.
  CSAuthorityChecks require: ((object at: 'parts') class == Array and: [((object at: 'parts') size between: 1 and: 4) and: [(object at: 'parts') allSatisfy: [:part | part isString and: [part size <= 4096]]]]) code: 'artifact-parts'.
  raw := String streamContents: [:stream | (object at: 'parts') do: [:part | stream nextPutAll: part]].
  CSAuthorityChecks require: (raw size <= 16384 and: [(CSSha256 hexDigestOf: raw) = hash]) code: 'artifact-integrity'.
  self validateNode: (CSCanonicalCodec decode: raw). {hash. raw}].
 missing := decoded count: [:pair | (self includes: pair first) not].
 CSAuthorityChecks require: self count + missing <= 65536 code: 'artifact-capacity-collect-required'.
 decoded do: [:pair | self putRaw: pair second hash: pair first].
 ^ decoded collect: #first
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> validateCheckpoint: root base: prior [
 | node model backend entities projection oldEntities oldProjection header index resources count summary poseSummary oldSummary oldNode newClosures checkedRows unchanged |
 self assertHash: root.
 CSAuthorityChecks require: (self missingFor: root limit: 1) isEmpty code: 'artifact-unavailable'.
 newClosures := self newClosuresFor: root.
 node := self objectAt: root.
 CSAuthorityChecks require: (node at: 'kind') = 'checkpoint' code: 'artifact-checkpoint-kind'.
 model := CSModelBundle fromSnapshot: (self valueAt: (node at: 'model')).
 CSAuthorityChecks require: (model isGraph and: [model digest = (node at: 'modelDigest')]) code: 'artifact-model'.
 backend := CSSmalltalkBackend model: model seed: (node at: 'seed').
 entities := self indexAt: (node at: 'entities'). projection := self indexAt: (node at: 'projection').
 CSAuthorityChecks require: entities keys asSet = projection keys asSet code: 'projection-buckets'.
 oldEntities := Dictionary new. oldProjection := Dictionary new.
 prior ifNotNil: [
  oldNode := self objectAt: prior.
  CSAuthorityChecks require: ((node at: 'modelDigest') = (oldNode at: 'modelDigest') and: [(node at: 'seed') = (oldNode at: 'seed')]) code: 'artifact-lineage'.
  oldEntities := self indexAt: (oldNode at: 'entities'). oldProjection := self indexAt: (oldNode at: 'projection').
  CSAuthorityChecks require: entities keys asSet = oldEntities keys asSet code: 'profile-fixed-population'].
 count := 0. checkedRows := 0. resources := self valueAt: (node at: 'resources').
 entities keysAndValuesDo: [:bucket :hash |
  summary := self summaryFor: hash suffix: bucket projection: false.
  unchanged := prior notNil and: [(oldEntities at: bucket) = hash and: [(oldProjection at: bucket) = (projection at: bucket)]].
  unchanged ifFalse: [poseSummary := self summaryFor: (projection at: bucket) suffix: bucket projection: true.
   CSAuthorityChecks require: (summary at: 'ids') = (poseSummary at: 'ids') code: 'projection-identities'].
  count := count + (summary at: 'ids') size.
  (summary at: 'resources') do: [:key | CSAuthorityChecks require: (resources includesKey: key) code: 'artifact-resource-reference'].
  (prior notNil and: [unchanged not]) ifTrue: [
   oldSummary := self summaryFor: (oldEntities at: bucket) suffix: bucket projection: false.
   CSAuthorityChecks require: (summary at: 'ids') = (oldSummary at: 'ids') code: 'profile-fixed-population'].
  unchanged ifFalse: [
   checkedRows := checkedRows + (summary at: 'ids') size.
   (summary at: 'ids') do: [:id | | row pose |
    row := self row: id at: hash. pose := self row: id at: (projection at: bucket).
    CSAuthorityChecks require: pose = {row first. row second. row third. row sixth} code: 'projection-state-mismatch']]].
 CSAuthorityChecks require: count = (node at: 'entityCount') code: 'artifact-entity-count'.
 index := CSArtifactEntityIndex new store: self index: entities count: count; yourself.
 header := Dictionary new at: 'version' put: 2; at: 'model' put: model snapshot; at: 'modelDigest' put: model digest;
 at: 'tick' put: (node at: 'tick'); at: 'seed' put: (node at: 'seed'); at: 'entities' put: index;
 at: 'resources' put: resources; at: 'events' put: (self valueAt: (node at: 'events')); at: 'outcomes' put: (self valueAt: (node at: 'outcomes')); yourself.
 backend validateHeader: header entities: index.
 (closures isKindOf: Dictionary) ifFalse: [closures := Dictionary new].
 newClosures keysAndValuesDo: [:hash :height | closures at: hash put: height].
 lastValidation := Dictionary new at: 'newObjects' put: newClosures size; at: 'checkedRows' put: checkedRows; at: 'totalEntities' put: count; yourself.
 ^ node
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> validateNode: node [
 | kind expected refs |
 CSAuthorityChecks require: (node isKindOf: Dictionary) code: 'artifact-node'.
 kind := node at: 'kind' ifAbsent: [CSAuthorityError signal: 'artifact-kind'].
 expected := kind = 'value' ifTrue: [#('kind' 'value')] ifFalse: [nil].
 (#('array' 'map' 'indexBranch') includes: kind) ifTrue: [expected := #('kind' 'left' 'right')].
 kind = 'item' ifTrue: [expected := #('kind' 'value')].
 kind = 'entry' ifTrue: [expected := #('kind' 'key' 'value')].
 kind = 'index' ifTrue: [expected := #('kind' 'entries')].
 (#('entities' 'projection') includes: kind) ifTrue: [expected := #('kind' 'suffix' 'rows')].
 (#('entitiesBranch' 'projectionBranch') includes: kind) ifTrue: [expected := #('kind' 'suffix' 'children')].
 kind = 'checkpoint' ifTrue: [expected := #('kind' 'version' 'model' 'modelDigest' 'tick' 'seed' 'entities' 'projection' 'entityCount' 'resources' 'events' 'outcomes')].
 CSAuthorityChecks require: expected notNil code: 'artifact-kind'.
 CSAuthorityChecks keys: node exactly: expected.
 refs := self references: node. refs do: [:hash | self assertHash: hash].
 (#('entities' 'projection') includes: kind) ifTrue: [
  CSAuthorityChecks require: ((node at: 'rows') isKindOf: Dictionary) code: 'artifact-rows'.
  CSAuthorityChecks require: (node at: 'rows') size <= 128 code: 'artifact-row-budget'].
 (#('entities' 'projection' 'entitiesBranch' 'projectionBranch') includes: kind) ifTrue: [
  CSAuthorityChecks require: ((node at: 'suffix') isString and: [((node at: 'suffix') size between: 2 and: 32) and: [(node at: 'suffix') allSatisfy: [:c | '0123456789abcdef' includes: c]]]) code: 'artifact-suffix'].
 kind = 'index' ifTrue: [
  CSAuthorityChecks require: ((node at: 'entries') isKindOf: Dictionary) code: 'artifact-index'.
  (node at: 'entries') keys do: [:bucket | CSAuthorityChecks require: (bucket size = 2 and: [bucket allSatisfy: [:c | '0123456789abcdef' includes: c]]) code: 'artifact-bucket']].
 kind = 'checkpoint' ifTrue: [
  CSAuthorityChecks require: (node at: 'version') = 1 code: 'artifact-version'.
  self assertHash: (node at: 'modelDigest'). CSKernelMath nonnegative: (node at: 'tick'); uint64: (node at: 'seed'); nonnegative: (node at: 'entityCount')]
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> value: value [
 | leaf keys middle left right |
 leaf := Dictionary new at: 'kind' put: 'value'; at: 'value' put: value; yourself.
 (CSCanonicalCodec encode: leaf) size <= 16384 ifTrue: [^ self put: leaf].
 value class == Array ifTrue: [
  value size = 1 ifTrue: [^ self put: (Dictionary new at: 'kind' put: 'item'; at: 'value' put: (self value: value first); yourself)].
  middle := value size // 2.
  ^ self put: (Dictionary new at: 'kind' put: 'array'; at: 'left' put: (self value: (value first: middle)); at: 'right' put: (self value: (value allButFirst: middle)); yourself)].
 CSAuthorityChecks require: ((value isKindOf: Dictionary) and: [value notEmpty]) code: 'artifact-value'.
 keys := value keys asArray sorted.
 keys size = 1 ifTrue: [^ self put: (Dictionary new at: 'kind' put: 'entry'; at: 'key' put: keys first; at: 'value' put: (self value: (value at: keys first)); yourself)].
 middle := keys size // 2. left := Dictionary new. right := Dictionary new.
 (keys first: middle) do: [:key | left at: key put: (value at: key)].
 (keys allButFirst: middle) do: [:key | right at: key put: (value at: key)].
 ^ self put: (Dictionary new at: 'kind' put: 'map'; at: 'left' put: (self value: left); at: 'right' put: (self value: right); yourself)
]

{ #category : 'sharded checkpoints' }
CSArtifactStore >> valueAt: hash [
 | node kind left right |
 node := self objectAt: hash. kind := node at: 'kind'.
 kind = 'value' ifTrue: [^ node at: 'value'].
 kind = 'item' ifTrue: [^ {self valueAt: (node at: 'value')}].
 kind = 'entry' ifTrue: [^ Dictionary new at: (node at: 'key') put: (self valueAt: (node at: 'value')); yourself].
 CSAuthorityChecks require: (#('array' 'map') includes: kind) code: 'artifact-value-kind'.
 left := self valueAt: (node at: 'left'). right := self valueAt: (node at: 'right').
 kind = 'array' ifTrue: [CSAuthorityChecks require: (left class == Array and: [right class == Array]) code: 'artifact-array'; yourself. ^ left, right].
 CSAuthorityChecks require: ((left isKindOf: Dictionary) and: [right isKindOf: Dictionary]) code: 'artifact-map'.
 CSAuthorityChecks require: (left keys noneSatisfy: [:key | right includesKey: key]) code: 'artifact-duplicate'.
 right keysAndValuesDo: [:key :value | left at: key put: value]. ^ left
]
