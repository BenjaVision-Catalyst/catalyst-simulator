"
Native local batch transport. Invoked only by Runtime-owned nontransactional progress; never by authority WorkUnits.
"
Class {
	#name : 'CSGemStoneRepastTransport',
	#superclass : 'Object',
	#category : 'BVC-Simulator-Runtime',
	#package : 'BVC-Simulator-Runtime'
}

{ #category : 'repast integration' }
CSGemStoneRepastTransport >> invoke: request configuration: cfg [
 | json output |
 (System respondsTo: #performOnServer:) ifFalse: [CSAuthorityError signal: 'native-gemstone-transport-required'].
 json := STON toJsonString: request.
 CSAuthorityChecks require: json size <= 49152 code: 'native-batch-request-limit'.
 output := System performOnServer: (self shellQuote: cfg repastLauncher), ' --spool ', (self shellQuote: cfg repastDirectory), ' --request ', (self shellQuote: json).
 ^ STON fromString: output
]

{ #category : 'repast integration' }
CSGemStoneRepastTransport >> shellQuote: text [
 | quote |
 quote := (Character value: 39) asString.
 ^ quote, (text copyReplaceAll: quote with: quote, '"', quote, '"', quote), quote
]
