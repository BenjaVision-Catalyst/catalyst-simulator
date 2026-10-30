"
Portable simulation kernel and acceptance authority with optional Runtime service integration. Core remains independent of Runtime and domain behaviour.
"
Class {
	#name : 'BaselineOfCatalystSimulator',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfCatalystSimulator',
	#package : 'BaselineOfCatalystSimulator'
}

{ #category : 'baseline' }
BaselineOfCatalystSimulator >> baseline: spec [
 <baseline>
 spec for: #common do: [
  spec baseline: 'CatalystRuntime' with: [
   self runtimeRepositoryDescriptions do: [:repository | spec repository: repository].
   spec loads: #('runtime')].
  spec project: 'CatalystRuntime test support' copyFrom: 'CatalystRuntime' with: [spec loads: #('test-support')].
  spec package: 'BVC-Simulator-Core'.
  spec package: 'BVC-Simulator-Authority' with: [spec requires: #('BVC-Simulator-Core')].
  spec package: 'BVC-Simulator-Runtime' with: [spec requires: #('BVC-Simulator-Authority' 'CatalystRuntime')].
  spec package: 'BVC-Simulator-Tests' with: [spec requires: #('BVC-Simulator-Core')].
  spec package: 'BVC-Simulator-Tests-Authority' with: [spec requires: #('BVC-Simulator-Authority' 'BVC-Simulator-Tests')].
  spec package: 'BVC-Simulator-Tests-Runtime' with: [spec requires: #('BVC-Simulator-Runtime' 'BVC-Simulator-Tests-Authority' 'CatalystRuntime test support')].
  spec group: 'Core' with: #('BVC-Simulator-Core').
  spec group: 'Authority' with: #('BVC-Simulator-Authority').
  spec group: 'Runtime' with: #('BVC-Simulator-Runtime').
  spec group: 'Tests' with: #('BVC-Simulator-Tests' 'BVC-Simulator-Tests-Authority').
  spec group: 'RuntimeTests' with: #('Tests' 'BVC-Simulator-Tests-Runtime').
  spec group: 'default' with: #('Core')]
]

{ #category : 'baseline' }
BaselineOfCatalystSimulator >> runtimeRepositoryDescriptions [
 | registered |
 registered := MetacelloProjectRegistration projectSpecForClassNamed: 'BaselineOfCatalystRuntime'
 ifAbsent: [^ #('github://BenjaVisionPro/CatalystRuntime:main/src')].
 ^ registered repositoryDescriptions
]
