# Tour

`biscuit-zig` is split into a number of modules. The following description should provide helpful orientation:

- `biscuit-schema`
  - Contains the `schema.proto` from the official biscuit repo
  - Contains `schema.pb.zig` which is generated from `schema.proto` using https://github.com/Arwalk/zig-protobuf. This powers the biscuit deserialization.
- `biscuit-format`
  - Provides an intermediate `SerializedBiscuit` type that deserializes the protobuf format and verifies biscuit.
- `biscuit`
  - Provides runtime representation of biscuit, this is the main interface a consumer of the library will use.
  - A `Biscuit` can be initialized
