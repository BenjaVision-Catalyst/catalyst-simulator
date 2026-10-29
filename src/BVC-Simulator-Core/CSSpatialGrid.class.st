"
CatalystSimulation P0/P1 portable probe foundation. Generic mechanisms only; ecosystem rules and UE content belong to domain components.
"
Class {
	#name : 'CSSpatialGrid',
	#superclass : 'Object',
	#instVars : [
		'width',
		'cells',
		'positions'
	],
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'portable kernel' }
CSSpatialGrid class >> width: size positions: entities [
 ^ self new initializeWidth: size positions: entities
]

{ #category : 'portable kernel' }
CSSpatialGrid >> cellFor: point [
 ^ point collect: [ :coordinate | coordinate // width ]
]

{ #category : 'portable kernel' }
CSSpatialGrid >> initializeWidth: size positions: entities [
 CSKernelMath int64: size. CSKernelMath require: size > 0 message: 'Positive cell width required'.
 CSKernelMath require: (entities isKindOf: Dictionary) message: 'Positions dictionary required'.
 width := size. positions := CSCanonicalCodec copy: entities. cells := Dictionary new.
 positions keysAndValuesDo: [ :id :point |
  CSKernelMath identifier: id. CSKernelMath vector: point.
  (cells at: (self cellFor: point) ifAbsentPut: [ OrderedCollection new ]) add: id ]. ^ self
]

{ #category : 'portable kernel' }
CSSpatialGrid >> within: radius of: point [
 | low high volume found distance |
 CSKernelMath vector: point. CSKernelMath nonnegative: radius.
 low := self cellFor: (point collect: [ :v | v - radius ]).
 high := self cellFor: (point collect: [ :v | v + radius ]).
 volume := 1. 1 to: 3 do: [ :i | volume := volume * ((high at: i) - (low at: i) + 1) ].
 CSKernelMath require: volume <= 4096 message: 'Spatial query cell budget exceeded'.
 found := OrderedCollection new.
 low first to: high first do: [ :x | low second to: high second do: [ :y | low third to: high third do: [ :z |
  (cells at: { x. y. z } ifAbsent: [ #() ]) do: [ :id |
   distance := 0. 1 to: 3 do: [ :i | distance := distance + (((positions at: id) at: i) - (point at: i)) squared ].
   distance <= radius squared ifTrue: [ found add: id ] ] ] ] ].
 ^ found asArray sorted: [ :a :b | CSKernelMath string: a precedes: b ]
]
