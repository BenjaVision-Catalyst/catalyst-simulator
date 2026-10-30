# projection-1: accepted client pages and changes

Clients use the existing named Runtime Simulation service for local and external
placement. Projection data is read from accepted GemStone pages; neither private
native candidates nor partially staged objects are client views.

`CSReadSimulationWorkUnit` / `CSCheckpointSimulationWorkUnit` return a compact
schema-2 view for sharded groups: world/group, model identity, authority revision,
data revision, placement, logical tick, entity count, manifest digest and projection
root. They do not return a population-sized `checkpoint` member. Legacy schema-1
groups retain their original shape. Clients select the profile explicitly.

## Snapshot pages

`CSReadSimulationProjectionWorkUnit` uses the existing read envelope
`{world, group, minimumRevision, argument}`. Its argument is:

```text
{root: acceptedManifestHash, bucket: twoHexDigits, after: entityIdOrNil, limit: 1..64}
```

Response: `{world, group, root, revision, tick, entities, next}`. Here `revision`
is the accepted **data** revision associated with the requested root. Each entity
is `[id, position3, velocity3, mode]`, with signed integer millimetres and
millimetres/second as in `probe-1`/`graph-1`. Rows are ordered by ID. The encoded
entity array is bounded to 32 KiB as well as 64 rows; large fields shorten the
page. `next` is the last returned ID when another page remains, otherwise nil.

The supplied root pins the whole read. A retained older root can be read while a
new frame publishes. An expired or unaccepted root returns
`accepted-view-expired-resnapshot`; it cannot leak staged data. `minimumRevision`
is a freshness constraint on the service's authority view, while `root` explicitly
selects the data snapshot.

`CSReadSimulationManifestWorkUnit`, argument `{root}`, returns the retained
manifest and its data revision. It does not make unaccepted artifact roots
readable or bypass the retained-root check.

## Incremental changes

`CSReadSimulationProjectionChangesWorkUnit` takes the last consumed data revision
as its read argument. The response has world/group, current data revision/root,
`resnapshot` and a bounded list of:

```text
{baseRevision, revision, baseRoot, root, tick, changedBuckets}
```

Changed buckets are derived by comparing accepted projection roots, independently
of checkpoint-only changes. Clients refresh just those pages. An empty bucket
list can still carry a new logical tick. Staging, placement changes and retry
receipts increase the authority revision without inventing a new data frame.

History uses the configured 1..64 retention bound. A gap sets `resnapshot: true`
and identifies the latest root. Clients discard their incomplete page view and
resnapshot; they do not silently apply a delta to the wrong base. Queries are
bounded without retaining per-client history on the server.

ID buckets are a first portable partition, not spatial AOI subscriptions or UE
representation policy. Spatial interest management, quantized visual LOD and UE
Mass binding remain separate presentation/serving work. Ecosystem meshes,
materials and behaviour remain in the ecosystem components; NPCs and automation
are deferred.
