Class {
	#name : 'CSSimulationFailAfterAdvanceWorkUnit',
	#superclass : 'CSAdvanceSimulationWorkUnit',
	#category : 'BVC-Simulator-Tests-Runtime',
	#package : 'BVC-Simulator-Tests-Runtime'
}

{ #category : 'simulation tests' }
CSSimulationFailAfterAdvanceWorkUnit >> executeInContext: context [
 super executeInContext: context. CSAuthorityError signal: 'qualification-failure-after-advance'
]
