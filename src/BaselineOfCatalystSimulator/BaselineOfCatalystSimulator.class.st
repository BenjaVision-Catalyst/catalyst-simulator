"
CatalystSimulation P0/P1 portable probe foundation. Generic mechanisms only; ecosystem rules and UE content belong to domain components.
"
Class {
	#name : 'BaselineOfCatalystSimulator',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfCatalystSimulator',
	#package : 'BaselineOfCatalystSimulator'
}

{ #category : 'portable kernel' }
BaselineOfCatalystSimulator >> baseline: spec [
 <baseline>
 spec for: #common do: [
  spec package: 'BVC-Simulator-Core'.
  spec package: 'BVC-Simulator-Tests' with: [ spec requires: #('BVC-Simulator-Core') ].
  spec group: 'Core' with: #('BVC-Simulator-Core').
  spec group: 'Tests' with: #('BVC-Simulator-Tests').
  spec group: 'default' with: #('Core') ]
]
