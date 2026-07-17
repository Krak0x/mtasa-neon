# Native world transport test

This resource exercises the version-gated three-file Bullworth transport,
closed client audit, and content-addressed cache publication. It does not
activate or register the pack.

Stage an audited format-1 Bullworth manifest, IDE, and IMG at the three paths
declared in `meta.xml`. The manifest must name `world.ide` and `world.img` and
contain their exact byte lengths and SHA-256 values. Generated payload files
are intentionally not committed.

Start the resource on a current Neon server and connect with a matching client.
The client log should show `state=audit-started`, followed by `state=cached`
with either `disposition=published` or `disposition=hit`. Every successful line
must retain `activation=no` and `lease=no`; cached and pending lines use
`restart-required=yes`, while revoked/cleared states use no.

This fixture requests an inert one-shot startup authorization after the cache
publication. Its logs must still report `activation=no lease=no`.
Use `nativeworldauth status` to inspect it or `nativeworldauth clear` to remove
it deliberately.

Reconnect to verify a cache hit with the same `contentId`, unchanged file
hashes, no duplicate cache object, and no quarantine residue.
