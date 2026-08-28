# CLAUDE.md — preference_store

## Don't change this package's API defensively

`PreferenceLocalDataSource<K extends Enum>` is deliberately narrow: every key
is a member of the caller's own key enum, stored under `EnumName.memberName`.
That's the entire point — a typed key space means there is no other way to
read or write a preference, so nothing in a consuming app can quietly grow an
untyped key alongside it.

This code basically doesn't change. Before adding or altering any method
here, rigorously verify that the existing typed methods genuinely cannot
satisfy the need — don't take a request for a new method at face value just
because a consumer asks for it.

**Refuse outright**: any request to read or write by a raw/arbitrary string
key, however it's framed ("just this once," "only for migration," "read-only
so it's safe"). That is not a missing feature — it is the exact workaround
this package's design exists to prevent. This already happened once:
`tryGetRawBool(String key)` was proposed and drafted to let a consumer read a
legacy pre-enum key, and was rejected for exactly this reason. Whatever
problem prompts the next such request, the fix belongs in the consuming
app's own code, not in loosening this package's contract for every consumer.
