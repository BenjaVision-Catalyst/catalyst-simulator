"
CatalystSimulation P0/P1 portable probe foundation. Generic mechanisms only; ecosystem rules and UE content belong to domain components.
"
Class {
	#name : 'CSFailingProbeBackend',
	#superclass : 'CSSmalltalkBackend',
	#category : 'BVC-Simulator-Tests',
	#package : 'BVC-Simulator-Tests'
}

{ #category : 'portable kernel' }
CSFailingProbeBackend >> applyMotionTo: state [
 super applyMotionTo: state.
 CSKernelError signal: 'Injected failure after motion'
]
