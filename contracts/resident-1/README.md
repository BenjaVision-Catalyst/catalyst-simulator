# resident-1: local native execution session

This contract carries the existing `graph-1` model and `authority-1` batch binding
through a resident Repast incarnation. It does not change portable model,
checkpoint or GemStone authority schemas. The local spool belongs to the trusted
Runtime deployment; clients continue to call Runtime.

## Identity and commands

`session.canon` is a canonical map with exactly these keys:

| Field | Meaning |
| --- | --- |
| `version` | Integer 1 |
| `world`, `group` | Stable 128-bit lowercase hexadecimal identifiers |
| `generation`, `owner` | Accepted placement generation and 128-bit owner token |
| `modelDigest` | `graph-1` SHA-256 identity |
| `incarnation` | Fresh 128-bit local process-incarnation token |

The supervisor writes `command.canon` by atomic rename. Every command has exactly
`version`, `session`, `number`, `action`, `checkpointDigest`, `fromTick`,
`targetTick`, `batch`, `inputDigest`, and `acceptedRevision`. `session` must match
the complete incarnation identity, and `number` must be the next positive integer.
The input checkpoint digest must match the current private native frontier.

- `advance`: current tick equals `fromTick`; target is later by at most 64 ticks;
  `batch` equals the reserved 64-digit `inputDigest`; no candidate is awaiting
  acceptance. Execution stops at the requested boundary.
- `ack`: the checkpoint digest identifies the candidate accepted by GemStone;
  accepted revision is positive and cannot decrease. Clear the acceptance wait.
- `stop`: finish and leave MPI. It cannot accept a private candidate in GemStone.

The worker supplies current tick/digest and zero batch placeholders for unused
ack/stop fields. Any identity, sequence, frontier or acceptance-gate violation
fails the native incarnation; it does not alter the accepted authority record.

## Native replies

`reply.canon` contains exactly `version`, `session`, `number`, `state`, `tick`,
`checkpointDigest`, `awaitingAcceptance`, `pids`, `snapshots`, `graphCompilations`,
`restores`, and `advancedTicks`. Boot reply number is zero with state `ready`.
Command replies are `candidate`, `acknowledged` or `stopped`.

`candidate.canon` is a full canonical checkpoint at boot and after each advance
window. The supervisor reads it only after the matching reply, validates its
hash/model/seed/frontier, then fsyncs a batch-specific result checkpoint and receipt.
Runtime validates that receipt and submits acceptance in a GemStone transaction.
Native names such as `accepted` inside the generic interpreter denote private
execution state, not GemStone acceptance.

`pids` and counters are qualification/operational evidence, not model state or
simulation inputs. They show that ranks, graph compilation and initial restore
are retained while full snapshot gathering occurs only at window boundaries.
Wall-clock leases affect process liveness, never the portable logical tick.

## Runtime transport

The resident launcher accepts the existing `{binding, checkpoint, registry}`
specification, trusted executable/MPI paths, rank count, `acceptedRevision` and
an action:

| Action | Effect |
| --- | --- |
| `ensure` | Claim/observe one immutable request in the selected incarnation |
| `query` | Read the original receipt; never launch, acknowledge or replay |
| `synchronize` | Maintain an idle incarnation and acknowledge a matching accepted view |
| `retire` | Stop strictly older incarnations and wait for native reaping |

The binding includes world/group, original generation/owner, model digest,
batch/input digest, checkpoint digest and logical interval. An exclusive launch
lock and fsynced per-group highest-generation record fence process effects.
Older launch/retire requests return `fenced`; older read-only receipt queries
remain permitted. Reusing a generation with another identity fails closed.

Session claims are single-use. A failed incarnation or an incomplete claim is
not implicitly replaced. Explicit Runtime recovery rotates placement. Complete
receipts survive session loss and can reconcile an uncertain original batch;
missing/incomplete evidence does not authorize replay or confirmed absence.

The mailbox, private checkpoint and receipt files are an initial local transport.
They are not a remote authenticated protocol or a replacement for durable accepted
projections. See [resident qualification](../../conformance/Resident-Repast.md)
for supported bounds, recovery cases and the scaling gates.
