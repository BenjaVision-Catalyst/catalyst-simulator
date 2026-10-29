"
Smalltalk authoring facade for portable graph data; build freezes and validates a detached bundle.
"
Class {
	#name : 'CSModelBuilder',
	#superclass : 'Object',
	#instVars : [
		'name',
		'tickMillis',
		'entityLimit',
		'eventLimit',
		'budget',
		'nodes'
	],
	#category : 'BVC-Simulator-Core',
	#package : 'BVC-Simulator-Core'
}

{ #category : 'portable graph' }
CSModelBuilder class >> named: modelName [
 ^ self new initializeNamed: modelName
]

{ #category : 'portable graph' }
CSModelBuilder >> addNode: description [
 nodes add: (CSCanonicalCodec copy: description). ^ self
]

{ #category : 'portable graph' }
CSModelBuilder >> build [
 ^ CSModelBundle fromSnapshot: {
  'simulation-portable-1/graph-1'. name. tickMillis. entityLimit. eventLimit.
  (Dictionary new at: 'version' put: 1; at: 'nodes' put: nodes asArray; at: 'maxNodeEvaluations' put: budget; yourself) }
]

{ #category : 'portable graph' }
CSModelBuilder >> initializeNamed: modelName [
 name := modelName copy. tickMillis := 100. entityLimit := 10000. eventLimit := 10000.
 budget := 1000000. nodes := OrderedCollection new. ^ self
]

{ #category : 'portable graph' }
CSModelBuilder >> limitsEntities: entityCount events: eventCount evaluations: evaluationCount [
 entityLimit := entityCount. eventLimit := eventCount. budget := evaluationCount. ^ self
]

{ #category : 'portable graph' }
CSModelBuilder >> node: nodeId operation: op stage: stage scope: scope type: type inputs: inputs after: dependencies parameters: parameters [
 ^ self addNode: (Dictionary new
  at: 'id' put: nodeId; at: 'operation' put: op; at: 'version' put: 1;
  at: 'stage' put: stage; at: 'scope' put: scope; at: 'type' put: type;
  at: 'inputs' put: inputs; at: 'after' put: dependencies; at: 'parameters' put: parameters; yourself)
]

{ #category : 'portable graph' }
CSModelBuilder >> tickMilliseconds: milliseconds [
 tickMillis := milliseconds. ^ self
]
