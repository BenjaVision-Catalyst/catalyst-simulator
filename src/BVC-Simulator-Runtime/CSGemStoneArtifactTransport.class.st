Class {
	#name : 'CSGemStoneArtifactTransport',
	#superclass : 'CSGemStoneRepastTransport',
	#category : 'BVC-Simulator-Runtime',
	#package : 'BVC-Simulator-Runtime'
}

{ #category : 'sharded runtime' }
CSGemStoneArtifactTransport >> invoke: request configuration: cfg [
 | json path file output |
 (System respondsTo: #performOnServer:) ifFalse: [CSAuthorityError signal: 'native-gemstone-transport-required'].
 json := STON toJsonString: request.
 CSAuthorityChecks require: json size <= 196608 code: 'artifact-control-byte-limit'.
 path := cfg repastDirectory, '/control/', UUID new asString36, '.json'.
 file := (Smalltalk at: #GsFile) openWriteOnServer: path.
 [file nextPutAll: json] ensure: [file close].
 output := System performOnServer: (self shellQuote: cfg repastLauncher), ' --spool ', (self shellQuote: cfg repastDirectory), ' --request-file ', (self shellQuote: path).
 CSAuthorityChecks require: output size <= 196608 code: 'artifact-response-byte-limit'.
 ^ STON fromString: output
]
