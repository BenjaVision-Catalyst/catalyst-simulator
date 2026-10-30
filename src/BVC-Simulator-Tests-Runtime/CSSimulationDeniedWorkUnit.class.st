Class {
	#name : 'CSSimulationDeniedWorkUnit',
	#superclass : 'CRWorkUnit',
	#category : 'BVC-Simulator-Tests-Runtime',
	#package : 'BVC-Simulator-Tests-Runtime'
}

{ #category : 'simulation tests' }
CSSimulationDeniedWorkUnit class >> requiredCapabilities [
 ^ {CSSimulationCapability}
]

{ #category : 'simulation tests' }
CSSimulationDeniedWorkUnit class >> requiresTransaction [
 ^ true
]

{ #category : 'simulation tests' }
CSSimulationDeniedWorkUnit class >> serviceClass [
 ^ CSSimulationService
]

{ #category : 'simulation tests' }
CSSimulationDeniedWorkUnit >> executeInContext: context [
 ^ context capability: CSSimulationCapability
]
