# Native static-world v2 startup test

This metadata-only resource exercises the authorized format-2
`static-world-v1` route. Keep the publish-only E1 harness separate: clients
that support v2 transport but not the appended v2 startup capability must
still receive its inert `N` descriptor.

Stage exactly three files below `native/`: a closed format-2
`native-world.json`, one IDE, and one IMG. The initial live gate deliberately
reuses the audited Bullworth payload and manifest from
`native-world-static-transport-test`. This proves that the generic policy can
authorize and activate one exact cache-v2 object; it does not prove a second
city or aggregate multi-pack startup.

The server declaration is engine-owned and has no Lua surface. A successful
first session must publish a pending authorization with no native mutation.
Only an explicit clean restart to the exact numeric endpoint may consume the
ticket, acquire the existing cache-v2 lease, and enter the native registrar.
Missing or corrupt cache content must be refused without repair.
