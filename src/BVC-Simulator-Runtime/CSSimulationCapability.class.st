Class {
	#name : 'CSSimulationCapability',
	#superclass : 'CRServiceBoundCapability',
	#instVars : [
		'epoch'
	],
	#category : 'BVC-Simulator-Runtime',
	#package : 'BVC-Simulator-Runtime'
}

{ #category : 'simulation runtime' }
CSSimulationCapability class >> canBeGrantedToServiceClass: serviceClass [
 ^ false
]

{ #category : 'simulation runtime' }
CSSimulationCapability class >> canBeGrantedToWorkUnitClass: unitClass [
 ^ (unitClass inheritsFrom: CSSimulationWorkUnit) or: [unitClass == CSSimulationDriveWork]
]

{ #category : 'simulation runtime' }
CSSimulationCapability >> assertCurrent [
 (service isCurrentResultEpoch: epoch) ifFalse: [CRCapabilityDeniedException signal: 'Simulation capability has expired']
]

{ #category : 'simulation runtime' }
CSSimulationCapability >> bindService: instance [
 super bindService: instance. epoch := instance resultEpoch
]

{ #category : 'simulation runtime' }
CSSimulationCapability >> driveIn: context [
 self assertCurrent. ^ service driveIn: context
]

{ #category : 'simulation runtime' }
CSSimulationCapability >> execute: kind request: request principal: principal [
 self assertCurrent.
 ^ service execute: kind request: request principal: principal
]
