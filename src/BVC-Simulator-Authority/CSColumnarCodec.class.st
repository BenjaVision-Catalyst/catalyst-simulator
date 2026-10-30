"
Bounded columnar checkpoint/delta transport. Reconstructs exact checkpoint-1 hashes in an owned scratch store before atomic bulk merge; no alternate acceptance authority.
"
Class {
	#name : 'CSColumnarCodec',
	#superclass : 'Object',
	#category : 'BVC-Simulator-Authority',
	#package : 'BVC-Simulator-Authority'
}

{ #category : 'columnar transport' }
CSColumnarCodec class >> bucket: unit store: store [
 | rows old ids current previous columns |
 rows := store rowsAt: unit fourth. old := unit second ifNil: [nil] ifNotNil: [store rowsAt: unit second].
 ids := rows keys asArray sorted.
 CSAuthorityChecks require: ((ids size between: 1 and: 4096) and: [old isNil or: [ids = old keys asArray sorted]]) code: 'columnar-membership'.
 current := ids collect: [:id | self fields: (rows at: id)]. previous := old ifNil: [nil] ifNotNil: [ids collect: [:id | self fields: (old at: id)]]. columns := OrderedCollection new.
 1 to: 14 do: [:i | | values same packet deltas added |
  values := current collect: [:fields | fields at: i]. same := previous notNil and: [(1 to: ids size) allSatisfy: [:n | (values at: n) = ((previous at: n) at: i)]].
  same ifFalse: [packet := self pack: i mode: 'set' values: values.
   (previous notNil and: [i <= 12]) ifTrue: [deltas := (1 to: ids size) collect: [:n | (values at: n) - ((previous at: n) at: i)].
    (deltas allSatisfy: [:value | value between: -9223372036854775808 and: 9223372036854775807]) ifTrue: [added := self pack: i mode: 'add' values: deltas.
     (CSCanonicalCodec encode: added) size < (CSCanonicalCodec encode: packet) size ifTrue: [packet := added]]]. columns add: packet]].
 ^ Dictionary new at: 'bucket' put: unit first; at: 'baseEntities' put: unit second; at: 'baseProjection' put: unit third;
  at: 'entities' put: unit fourth; at: 'projection' put: unit fifth; at: 'count' put: ids size;
  at: 'ids' put: (old ifNil: [self parts: (String streamContents: [:stream | ids do: [:id | stream nextPutAll: id]])] ifNotNil: [#()]); at: 'columns' put: columns asArray; yourself
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> fields: row [
 ^ row second, row third, {row fifth. row seventh. row eighth}, (row at: 9), {row fourth. row sixth}
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> frame: root base: base cursor: cursor store: store [
 | units frame next rows bytes measure packet field candidate |
 units := self plan: root base: base store: store.
 CSAuthorityChecks require: (cursor isInteger and: [cursor between: 0 and: units size]) code: 'columnar-cursor'.
 frame := Dictionary new at: 'profile' put: 'columnar-1'; at: 'root' put: root; at: 'base' put: base; at: 'cursor' put: cursor; at: 'next' put: cursor; at: 'total' put: units size; at: 'buckets' put: #(); at: 'objects' put: #(); yourself.
 next := cursor. rows := 0. bytes := 0.
 [next < units size and: [next - cursor < 128]] whileTrue: [
  measure := self measure: (units at: next + 1) store: store.
  (rows + measure first > 4096 or: [bytes + measure second > 4194304]) ifTrue: [^ self requireProgress: frame].
  (units at: next + 1) class == Array
   ifTrue: [packet := self bucket: (units at: next + 1) store: store. field := 'buckets']
   ifFalse: [packet := (store objects: {units at: next + 1}) first. field := 'objects'].
  candidate := frame copy. candidate at: field put: ((frame at: field) copyWith: packet); at: 'next' put: next + 1.
  (self wireFits: candidate) ifFalse: [^ self requireProgress: frame].
  frame := candidate. rows := rows + measure first. bytes := bytes + measure second. next := next + 1].
 ^ self requireProgress: frame
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> hex: value width: width [
 | result unsigned digits |
 digits := '0123456789abcdef'. result := String new: width.
 unsigned := value < 0 ifTrue: [value + 18446744073709551616] ifFalse: [value].
 width to: 1 by: -1 do: [:i | result at: i put: (digits at: (unsigned bitAnd: 15) + 1). unsigned := unsigned bitShift: -4].
 ^ result
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> joinParts: parts [
 CSAuthorityChecks require: (parts class == Array and: [parts size <= 32 and: [parts allSatisfy: [:part | part isString and: [part size between: 1 and: 4096]]]]) code: 'columnar-parts'.
 ^ String streamContents: [:stream | parts do: [:part | stream nextPutAll: part]]
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> measure: unit store: store [
 | seen pending count bytes |
 unit isString ifTrue: [^ {0. (store rawAt: unit) size}].
 seen := Set new. pending := OrderedCollection with: unit fourth with: unit fifth. count := 0. bytes := 0.
 [pending notEmpty] whileTrue: [| hash raw node |
  hash := pending removeLast.
  (seen includes: hash) ifFalse: [seen add: hash. raw := store rawAt: hash. node := CSCanonicalCodec decode: raw.
   (node at: 'kind') = 'entities' ifTrue: [count := count + (node at: 'rows') size]. bytes := bytes + raw size.
   (count > 4096 or: [bytes > 4194304]) ifTrue: [^ {count. bytes}]. pending addAll: (store references: node)]].
 ^ {count. bytes}
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> metadata: root store: store [
 | node hashes pending |
 node := store objectAt: root.
 CSAuthorityChecks require: ((node at: 'kind') = 'checkpoint' and: [(node at: 'version') = 1]) code: 'columnar-checkpoint'.
 CSAuthorityChecks require: (CSModelBundle fromSnapshot: (store valueAt: (node at: 'model'))) isTyped code: 'columnar-profile'.
 hashes := Set with: root.
 #('model' 'resources' 'events' 'outcomes') do: [:key | hashes addAll: (store closure: (node at: key))].
 pending := OrderedCollection with: (node at: 'entities') with: (node at: 'projection').
 [pending notEmpty] whileTrue: [| hash index | hash := pending removeLast. hashes add: hash. index := store objectAt: hash.
  CSAuthorityChecks require: (#('index' 'indexBranch') includes: (index at: 'kind')) code: 'columnar-index'.
  (index at: 'kind') = 'indexBranch' ifTrue: [pending add: (index at: 'left'); add: (index at: 'right')]].
 ^ {node. hashes}
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> pack: column mode: mode values: values [
 | palette indices seen |
 palette := OrderedCollection new. indices := OrderedCollection new. seen := Dictionary new.
 values do: [:value | | code | code := seen at: value ifAbsent: [| next | next := palette size. palette add: value. seen at: value put: next. next]. indices add: code].
 palette size = 1 ifTrue: [^ {column. mode. 'constant'. palette asArray. #()}].
 palette size <= 256 ifTrue: [^ {column. mode. 'palette8'. palette asArray. (self parts: (String streamContents: [:stream | indices do: [:code | stream nextPutAll: (self hex: code width: 2)]]))}].
 column <= 12 ifTrue: [^ {column. mode. 'int64'. #(). (self parts: (String streamContents: [:stream | values do: [:value | stream nextPutAll: (self hex: value width: 16)]]))}].
 ^ {column. mode. 'text'. values. #()}
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> parts: text [
 | result |
 result := OrderedCollection new.
 1 to: text size by: 4096 do: [:i | result add: (text copyFrom: i to: ((i + 4095) min: text size))]. ^ result asArray
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> plan: root base: base store: store [
 | metadata node hashes entities poses oldEntities oldPoses before units |
 metadata := self metadata: root store: store. node := metadata first. hashes := metadata second.
 entities := store indexAt: (node at: 'entities'). poses := store indexAt: (node at: 'projection').
 CSAuthorityChecks require: entities keys asSet = poses keys asSet code: 'columnar-buckets'.
 oldEntities := Dictionary new. oldPoses := Dictionary new.
 base ifNotNil: [metadata := self metadata: base store: store. before := metadata first.
  CSAuthorityChecks require: ((node at: 'model') = (before at: 'model') and: [(node at: 'modelDigest') = (before at: 'modelDigest') and: [(node at: 'seed') = (before at: 'seed')]]) code: 'columnar-lineage'.
  oldEntities := store indexAt: (before at: 'entities'). oldPoses := store indexAt: (before at: 'projection').
  CSAuthorityChecks require: (entities keys asSet = oldEntities keys asSet and: [entities keys asSet = oldPoses keys asSet]) code: 'columnar-membership'.
  metadata second do: [:hash | hashes remove: hash ifAbsent: []]].
 units := OrderedCollection new.
 entities keys asArray sorted do: [:bucket |
  ((entities at: bucket) ~= (oldEntities at: bucket ifAbsent: [nil]) or: [(poses at: bucket) ~= (oldPoses at: bucket ifAbsent: [nil])]) ifTrue: [
   units add: {bucket. oldEntities at: bucket ifAbsent: [nil]. oldPoses at: bucket ifAbsent: [nil]. entities at: bucket. poses at: bucket}]].
 units addAll: hashes asArray sorted. ^ units asArray
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> reconstruct: frame base: base cursor: cursor store: store [
 | before oldEntities oldPoses scratch rowsSeen seen |
 self validateFrame: frame base: base cursor: cursor.
 before := base ifNil: [nil] ifNotNil: [store objectAt: base].
 oldEntities := before ifNil: [Dictionary new] ifNotNil: [store indexAt: (before at: 'entities')].
 oldPoses := before ifNil: [Dictionary new] ifNotNil: [store indexAt: (before at: 'projection')].
 scratch := CSColumnarScratchStore new. rowsSeen := 0. seen := Set new.
 (frame at: 'buckets') do: [:packet | | bucket count ids values old last rows poses columns raw |
  CSAuthorityChecks keys: packet exactly: #('bucket' 'baseEntities' 'baseProjection' 'entities' 'projection' 'count' 'ids' 'columns').
  bucket := packet at: 'bucket'. count := packet at: 'count'.
  CSAuthorityChecks require: (bucket isString and: [bucket size = 2 and: [bucket allSatisfy: [:c | '0123456789abcdef' includes: c]]]) code: 'columnar-bucket'.
  CSAuthorityChecks require: (seen includes: bucket) not code: 'columnar-duplicate-bucket'. seen add: bucket.
  CSAuthorityChecks require: (count isInteger and: [count between: 1 and: 4096]) code: 'columnar-row-budget'.
  rowsSeen := rowsSeen + count. CSAuthorityChecks require: rowsSeen <= 4096 code: 'columnar-row-budget'.
  CSAuthorityChecks require: ((packet at: 'baseEntities') = (oldEntities at: bucket ifAbsent: [nil]) and: [(packet at: 'baseProjection') = (oldPoses at: bucket ifAbsent: [nil])]) code: 'columnar-base-bucket'.
  before ifNotNil: [old := store rowsAt: (packet at: 'baseEntities'). ids := old keys asArray sorted.
   CSAuthorityChecks require: (ids size = count and: [(packet at: 'ids') = #()]) code: 'columnar-membership'.
   values := ids collect: [:id | self fields: (old at: id)]]
  ifNil: [raw := self joinParts: (packet at: 'ids'). CSAuthorityChecks require: (raw isString and: [raw size = (count * 32)]) code: 'columnar-identities'.
   ids := (1 to: count) collect: [:i | raw copyFrom: i * 32 - 31 to: i * 32].
   CSAuthorityChecks require: ids = ids asSet asArray sorted code: 'columnar-identities'.
   values := (1 to: count) collect: [:i | #(0 0 0 0 0 0 0 0 0 0 0 0 '' '') copy]].
  ids do: [:id | CSKernelMath identifier: id. CSAuthorityChecks require: (id endsWith: bucket) code: 'columnar-suffix'].
  columns := packet at: 'columns'. CSAuthorityChecks require: (columns class == Array and: [columns size <= 14]) code: 'columnar-columns'. last := 0.
  columns do: [:column | | decoded number mode | decoded := self unpack: column count: count hasBase: before notNil. number := decoded first. mode := decoded second.
   CSAuthorityChecks require: number > last code: 'columnar-column-order'. last := number.
   1 to: count do: [:i | | value fields | fields := values at: i. value := decoded third at: i.
    mode = 'add' ifTrue: [value := (fields at: number) + value]. number <= 12 ifTrue: [CSKernelMath int64: value]. fields at: number put: value]].
  before ifNil: [CSAuthorityChecks require: (columns collect: #first) = (1 to: 14) asArray code: 'columnar-complete-columns'].
  rows := Dictionary new. poses := Dictionary new.
  1 to: count do: [:i | | row id | id := ids at: i. row := self row: id fields: (values at: i). rows at: id put: row. poses at: id put: {id. row second. row third. row sixth}].
  CSAuthorityChecks require: (scratch rows: rows suffix: bucket projection: false) = (packet at: 'entities') code: 'columnar-entity-hash'.
  CSAuthorityChecks require: (scratch rows: poses suffix: bucket projection: true) = (packet at: 'projection') code: 'columnar-projection-hash'].
 (frame at: 'objects') do: [:object | scratch upload: {object}].
 CSAuthorityChecks require: scratch rawByteCount <= 4194304 code: 'columnar-expanded-budget'. ^ scratch
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> requireProgress: frame [
 CSAuthorityChecks require: ((frame at: 'next') > (frame at: 'cursor') or: [(frame at: 'cursor') = (frame at: 'total')]) code: 'columnar-bucket-too-large'. ^ frame
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> row: id fields: values [
 ^ {id. (values copyFrom: 1 to: 3). (values copyFrom: 4 to: 6). (values at: 13). (values at: 7). (values at: 14). (values at: 8). (values at: 9). (values copyFrom: 10 to: 12)}
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> unhex: text [
 | result digit |
 CSAuthorityChecks require: (text isString and: [text allSatisfy: [:c | '0123456789abcdef' includes: c]]) code: 'columnar-hex'.
 result := 0. text do: [:c | digit := ('0123456789abcdef' indexOf: c) - 1. result := result * 16 + digit]. ^ result
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> unpack: packet count: count hasBase: hasBase [
 | column mode encoding values data result |
 CSAuthorityChecks require: (packet class == Array and: [packet size = 5]) code: 'columnar-column'.
 column := packet first. mode := packet second. encoding := packet third. values := packet fourth. data := self joinParts: packet fifth.
 CSAuthorityChecks require: (column isInteger and: [column between: 1 and: 14]) code: 'columnar-column'.
 CSAuthorityChecks require: (#('set' 'add') includes: mode) code: 'columnar-mode'.
 CSAuthorityChecks require: (mode ~= 'add' or: [hasBase and: [column <= 12]]) code: 'columnar-base'.
 CSAuthorityChecks require: (values class == Array and: [data isString and: [data allSatisfy: [:c | '0123456789abcdef' includes: c]]]) code: 'columnar-values'.
 values do: [:value | column <= 12 ifTrue: [CSKernelMath int64: value] ifFalse: [CSTypedPopulation new validateText: value]].
 encoding = 'constant' ifTrue: [
  CSAuthorityChecks require: (values size = 1 and: [data isEmpty]) code: 'columnar-constant'. result := (1 to: count) collect: [:i | values first]].
 encoding = 'palette8' ifTrue: [
  CSAuthorityChecks require: ((values size between: 2 and: 256) and: [values asSet size = values size and: [data size = (count * 2)]]) code: 'columnar-palette'.
  result := (1 to: count) collect: [:i | | code | code := self unhex: (data copyFrom: i * 2 - 1 to: i * 2).
   CSAuthorityChecks require: code < values size code: 'columnar-palette-index'. values at: code + 1]].
 encoding = 'int64' ifTrue: [
  CSAuthorityChecks require: (column <= 12 and: [values isEmpty and: [data size = (count * 16)]]) code: 'columnar-integer'.
  result := (1 to: count) collect: [:i | | unsigned | unsigned := self unhex: (data copyFrom: i * 16 - 15 to: i * 16).
   unsigned >= 9223372036854775808 ifTrue: [unsigned - 18446744073709551616] ifFalse: [unsigned]]].
 encoding = 'text' ifTrue: [
  CSAuthorityChecks require: (column > 12 and: [values size = count and: [data isEmpty]]) code: 'columnar-text'. result := values].
 CSAuthorityChecks require: result notNil code: 'columnar-encoding'. ^ {column. mode. result asArray}
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> validateFrame: frame base: base cursor: cursor [
 CSAuthorityChecks keys: frame exactly: #('profile' 'root' 'base' 'cursor' 'next' 'total' 'buckets' 'objects').
 CSAuthorityChecks require: ((CSCanonicalCodec encode: frame) size <= 131072 and: [(frame at: 'profile') = 'columnar-1']) code: 'columnar-frame-budget'.
 CSArtifactStore new assertHash: (frame at: 'root'). base ifNotNil: [CSArtifactStore new assertHash: base].
 CSAuthorityChecks require: (frame at: 'base') = base code: 'columnar-base'.
 #('cursor' 'next' 'total') do: [:key | CSAuthorityChecks require: (frame at: key) isInteger code: 'columnar-cursor'].
 CSAuthorityChecks require: ((frame at: 'cursor') = cursor and: [cursor >= 0 and: [cursor < (frame at: 'next') and: [(frame at: 'next') <= (frame at: 'total') and: [(frame at: 'total') <= 65792]]]]) code: 'columnar-cursor'.
 CSAuthorityChecks require: ((frame at: 'buckets') class == Array and: [(frame at: 'objects') class == Array]) code: 'columnar-units'.
 CSAuthorityChecks require: ((frame at: 'buckets') size + (frame at: 'objects') size = ((frame at: 'next') - cursor) and: [(frame at: 'next') - cursor <= 128]) code: 'columnar-unit-budget'
]

{ #category : 'columnar transport' }
CSColumnarCodec class >> wireFits: frame [
 | raw escaped |
 raw := CSCanonicalCodec encode: frame. escaped := raw count: [:c | c = $" or: [c asciiValue = 92]].
 ^ raw size <= 131072 and: [raw size + escaped + 2048 <= 196608]
]
