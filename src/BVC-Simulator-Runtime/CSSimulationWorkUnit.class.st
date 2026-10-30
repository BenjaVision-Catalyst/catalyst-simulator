"
Inert canonical Simulation input. The trusted ingress supplies an authenticated principal separately from client data; this service checks configured roles, not transport authentication. GemStone Runtime owns the transaction and never automatically replays the body.
"
Class {
	#name : 'CSSimulationWorkUnit',
	#superclass : 'CRWorkUnit',
	#instVars : [
		'requestBytes',
		'principal'
	],
	#category : 'BVC-Simulator-Runtime',
	#package : 'BVC-Simulator-Runtime'
}

{ #category : 'simulation runtime' }
CSSimulationWorkUnit class >> allowsConflictReplay [
 ^ false
]

{ #category : 'simulation runtime' }
CSSimulationWorkUnit class >> request: data principal: trustedPrincipal [
 ^ self new initializeRequest: data principal: trustedPrincipal
]

{ #category : 'simulation runtime' }
CSSimulationWorkUnit class >> requiredCapabilities [
 ^ {CSSimulationCapability}
]

{ #category : 'simulation runtime' }
CSSimulationWorkUnit class >> requiresTransaction [
 ^ true
]

{ #category : 'simulation runtime' }
CSSimulationWorkUnit class >> serviceClass [
 ^ CSSimulationService
]

{ #category : 'simulation runtime' }
CSSimulationWorkUnit >> executeInContext: context [
 ^ (context capability: CSSimulationCapability) execute: self operation request: self request principal: principal
]

{ #category : 'simulation runtime' }
CSSimulationWorkUnit >> initializeRequest: data principal: trustedPrincipal [
 requestBytes ifNotNil: [CSAuthorityError signal: 'request-already-bound'].
 principal := CSAuthorityChecks text: trustedPrincipal.
 requestBytes := CSCanonicalCodec encode: data.
 CSAuthorityChecks require: requestBytes size <= 262144 code: 'request-byte-limit'.
 ^ self
]

{ #category : 'simulation runtime' }
CSSimulationWorkUnit >> operation [
 self subclassResponsibility
]

{ #category : 'simulation runtime' }
CSSimulationWorkUnit >> principal [
 ^ principal copy
]

{ #category : 'simulation runtime' }
CSSimulationWorkUnit >> request [
 ^ CSCanonicalCodec decode: requestBytes
]
