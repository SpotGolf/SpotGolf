# SwiftData models without encoding

Every saved value is a plain SwiftData property. No model encodes a value to `Data` itself, and no model keeps a decoded cache.

## How SwiftData stores a value

| Value | Stored as | Rule |
|---|---|---|
| Simple value or enum (`Date`, `Int`, `RoundStatus`, `LogDevice`) | One column | Enums work in `#Predicate` when the value is captured in a local first (`let device = LogDevice.watch`); a literal case in the predicate does not compile |
| Single struct (`DisplayHole`) | One column per stored property, nested structs flattened | Coding keys must match property names, and the struct must encode with a keyed container. No optional simple value (`String?`, `Double?`) anywhere inside it: reading change history after an update, which `@Query` does, stops the app with "Failed to materialize a keypath". Saving and fetching work, so only a history read catches it ([Apple forums 784036](https://developer.apple.com/forums/thread/784036)) |
| Struct marked `@Attribute(.codable)` (`CourseSelection`) | One encoded column | For types that don't fit the row above, such as `Course` from CourseDataSwift. Can't be used in predicates or sorts, and shape changes don't trigger a migration |
| Array (`[RoundHole]`, `[Date?]`, `[PinLocation?]`, `CoordinatePath` values) | One JSON column, through `Codable` | Custom `Codable` is fine |

Measured with the macOS 27 SDK: a repeated read of a stored array or of the whole course takes under 0.001 ms, so no cache is needed.

## Round

| Property | Type |
|---|---|
| `holes` | `[RoundHole]`, growing as play reaches each hole |
| `holeStarts` | `[Date?]`, one per hole by play index |
| `pins` | `[PinLocation?]`, one per hole by play index. `PinLocation` has no `holeIndex` |
| `displayHole` | `DisplayHole` |
| `courseSelection` | `@Attribute(.codable) CourseSelection`, holding the CourseDataSwift 0.4.0 `Course`, which has optional values (`teeName`, `startHoleIndex`, `Coordinate.ele`) |

`PinsMessage.pins` and `StartRound.pins` carry the same by-hole array; merging is per index with `PinLocation.isReplaced(by:)`.

## Other models

| Model | Note |
|---|---|
| `LogEntry` | `device: LogDevice`, `level: LogLevel` |
| `StreamEntry` | `record: Data` stays: it is the 25-byte record the watch sends, a wire format, not a storage workaround |
| `CarriedClub` | Unchanged |

## Breaking change

Stores from earlier builds don't open: the app stops at launch. Delete the app before installing.
