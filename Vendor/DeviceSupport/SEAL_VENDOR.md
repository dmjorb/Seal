# Vendored Device Support

Seal vendors the same libimobiledevice source revisions used by SideStore:

- libimobiledevice: `e7cc53a65b0f975754760032015f58dfbb87e1a0`
- libimobiledevice-glue: `214bafdde6a1434ead87357afe6cb41b32318495`
- libplist: `258d3c24aa05ade06aac4b5dd5148fd04c02893e`
- libusbmuxd: `30e678d4e76a9f4f8a550c34457dab73909bdd92`
- SideStore integration reference: `4deda9229c6746234f1ace7df16eb9af9e19f3fd`

The included C and C++ sources provide the native symbols required by the
vendored Minimuxer Rust bridge. They are compiled into Seal as an iOS static
library using SideStore's source list, header paths, and feature definitions.
