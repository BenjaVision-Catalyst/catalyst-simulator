Class {
	#name : 'CSTypedPopulation',
	#superclass : 'Object',
	#instVars : [
		'columns',
		'widths',
		'index',
		'strings',
		'symbols',
		'capacity',
		'sealed'
	],
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'typed population' }
CSTypedPopulation class >> capacity: maximum [
 ^ self new initializeCapacity: maximum
]

{ #category : 'typed population' }
CSTypedPopulation >> at: id [
 | slot position velocity remainders |
 slot := index at: id.
 position := (1 to: 3) collect: [:axis | self numberAt: slot column: axis].
 velocity := (4 to: 6) collect: [:axis | self numberAt: slot column: axis].
 remainders := (10 to: 12) collect: [:axis | self numberAt: slot column: axis].
 ^ {id copy. position asArray. velocity asArray. (strings at: (self numberAt: slot column: 13)) copy.
 self numberAt: slot column: 7. (strings at: (self numberAt: slot column: 14)) copy.
 self numberAt: slot column: 8. self numberAt: slot column: 9. remainders asArray}
]

{ #category : 'typed scale' }
CSTypedPopulation >> at: id put: row [
 | slot request mode validator |
 CSKernelMath require: (row class == Array and: [row size = 9]) message: 'Typed row shape'.
 self validateText: row fourth. self validateText: row sixth.
 validator := CSSmalltalkBackend new.
 validator validateEntity: row id: id resources: (Dictionary new at: row fourth put: 0; yourself).
 slot := index at: id ifAbsent: [nil].
 slot ifNil: [
  CSKernelMath require: (sealed not and: [index size < capacity]) message: 'Typed population membership/capacity'.
  slot := index size + 1].
 request := self intern: row fourth. mode := self intern: row sixth.
 (index includesKey: id) ifFalse: [index at: id copy put: slot].
 1 to: 3 do: [:axis |
  self numberAt: slot column: axis put: (row second at: axis).
  self numberAt: slot column: axis + 3 put: (row third at: axis).
  self numberAt: slot column: axis + 9 put: ((row at: 9) at: axis)].
 self numberAt: slot column: 7 put: row fifth.
 self numberAt: slot column: 8 put: row seventh.
 self numberAt: slot column: 9 put: row eighth.
 self numberAt: slot column: 13 put: request.
 self numberAt: slot column: 14 put: mode.
 ^ row
]

{ #category : 'typed population' }
CSTypedPopulation >> includesKey: id [ ^ index includesKey: id
]

{ #category : 'typed population' }
CSTypedPopulation >> initializeCapacity: maximum [
 CSKernelMath require: (maximum isInteger and: [maximum between: 1 and: 1000000]) message: 'Typed population capacity'.
 capacity := maximum. widths := #(8 8 8 8 8 8 8 4 4 8 8 8 4 4).
 columns := widths collect: [:width | (1 to: ((maximum + 1023) // 1024)) collect: [:chunk | ByteArray new: 1024 * width]].
 index := Dictionary new. strings := OrderedCollection new. symbols := Dictionary new. sealed := false. ^ self
]

{ #category : 'typed population' }
CSTypedPopulation >> integrate: id milliseconds: millis [
 | slot positions remainders |
 slot := index at: id. positions := Array new: 3. remainders := Array new: 3.
 1 to: 3 do: [:axis | | wide |
  wide := (self numberAt: slot column: axis + 3) * millis + (self numberAt: slot column: axis + 9).
  positions at: axis put: (CSKernelMath int64: (self numberAt: slot column: axis) + (wide // 1000)).
  remainders at: axis put: wide \\ 1000].
 1 to: 3 do: [:axis |
  self numberAt: slot column: axis put: (positions at: axis).
  self numberAt: slot column: axis + 9 put: (remainders at: axis)]
]

{ #category : 'typed population' }
CSTypedPopulation >> intern: text [
 | owned code |
 self validateText: text.
 ^ symbols at: text ifAbsent: [
  code := CSKernelMath uint32: strings size + 1. owned := text copy.
  strings add: owned. symbols at: owned put: code. code]
]

{ #category : 'typed scale' }
CSTypedPopulation >> keys [ ^ index keys asArray collect: [:id | id copy]
]

{ #category : 'typed scale' }
CSTypedPopulation >> keysAndValuesDo: block [
 index keysDo: [:id | block value: id copy value: (self at: id)]
]

{ #category : 'typed population' }
CSTypedPopulation >> numberAt: slot column: column [
 | width bytes offset low value |
 width := widths at: column. bytes := (columns at: column) at: (slot - 1) // 1024 + 1.
 offset := ((slot - 1) \\ 1024) * width + 1.
 low := bytes unsignedLongAt: offset bigEndian: false.
 width = 4 ifTrue: [^ low].
 value := ((bytes unsignedLongAt: offset + 4 bigEndian: false) bitShift: 32) + low.
 ^ value >= 9223372036854775808 ifTrue: [value - 18446744073709551616] ifFalse: [value]
]

{ #category : 'typed population' }
CSTypedPopulation >> numberAt: slot column: column put: value [
 | width bytes offset unsigned |
 width := widths at: column.
 width = 4 ifTrue: [CSKernelMath uint32: value] ifFalse: [CSKernelMath int64: value].
 bytes := (columns at: column) at: (slot - 1) // 1024 + 1.
 offset := ((slot - 1) \\ 1024) * width + 1.
 unsigned := value < 0 ifTrue: [value + 18446744073709551616] ifFalse: [value].
 bytes unsignedLongAt: offset put: (unsigned bitAnd: 4294967295) bigEndian: false.
 width = 8 ifTrue: [bytes unsignedLongAt: offset + 4 put: (unsigned bitShift: -32) bigEndian: false].
 ^ value
]

{ #category : 'typed population' }
CSTypedPopulation >> packedBytes [
 ^ widths inject: 0 into: [:sum :width | sum + (((capacity + 1023) // 1024) * 1024 * width)]
]

{ #category : 'typed population' }
CSTypedPopulation >> postCopy [
 super postCopy.
 columns := columns collect: [:chunks | chunks collect: [:chunk | chunk copy]].
 sealed ifFalse: [index := index copy].
 strings := strings copy. symbols := symbols copy
]

{ #category : 'typed population' }
CSTypedPopulation >> seal [ sealed := true. ^ self
]

{ #category : 'typed population' }
CSTypedPopulation >> size [ ^ index size
]

{ #category : 'typed population' }
CSTypedPopulation >> statistics [
 ^ Dictionary new at: 'layout' put: 'columns-1'; at: 'entities' put: self size; at: 'capacity' put: capacity; at: 'packedBytes' put: self packedBytes; at: 'numericBytesPerSlot' put: 96; at: 'internedStrings' put: strings size; at: 'idIndexEntries' put: index size; yourself
]

{ #category : 'typed scale' }
CSTypedPopulation >> validateText: text [
 CSKernelMath require: (text isString and: [text isSymbol not and: [text size <= 4096 and: [text allSatisfy: [:c | c asciiValue between: 32 and: 126]]]]) message: 'Typed string'
]
