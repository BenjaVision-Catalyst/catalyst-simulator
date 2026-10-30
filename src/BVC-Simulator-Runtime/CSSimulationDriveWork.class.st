Class {
	#name : 'CSSimulationDriveWork',
	#superclass : 'CRServiceWorkUnit',
	#category : 'BVC-Simulator-Runtime',
	#package : 'BVC-Simulator-Runtime'
}

{ #category : 'simulation runtime' }
CSSimulationDriveWork class >> allowsConflictReplay [
 ^ false
]

{ #category : 'simulation runtime' }
CSSimulationDriveWork class >> requiredCapabilities [
 ^ {CSSimulationCapability}
]

{ #category : 'simulation runtime' }
CSSimulationDriveWork class >> requiresTransaction [
 ^ false
]

{ #category : 'simulation runtime' }
CSSimulationDriveWork class >> serviceClass [
 ^ CSSimulationService
]

{ #category : 'simulation runtime' }
CSSimulationDriveWork >> executeServiceWorkInContext: context [
 ^ (context capability: CSSimulationCapability) driveIn: context
]
