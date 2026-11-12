---
summary: "Proposed: keep the data protection Keychain as the only durable PDT credential store; hold a credential the store refuses in memory instead of dropping it; optionally use it for the session."
read_when:
  - Changing where or how the PDT credential is stored
  - Changing what happens when the Keychain refuses a write (unsigned or unprovisioned builds)
  - Changing Check again, relaunch, refresh, or disconnect behaviour around storage failures
---

# ADR-0003: Credential storage and unsaved connections

- **Status:** Proposed (parts marked [needs sign-off] wait for Bram)
- **Date:** 2026-11-12
- **Deciders:** Bram

## Context

A local `make start` build is ad-hoc signed with no provisioning profile, so it has no keychain access group. Bram signed in with PDT on such a build, then clicked Check again and was signed out (#301).

Measured on an ad-hoc signed probe against the data protection keychain: a read of a missing item answers `errSecItemNotFound` (-25300); add, update, and delete answer `errSecMissingEntitlement` (-34018). No prompt appears. An unentitled build therefore launches as *Not connected*, not as *Keychain unavailable* as the docs said, and offers Sign in. The session PDT granted is then dropped when the save fails, the menu shows *Keychain unavailable*, and Check again re-reads "nothing stored". The scripted SecItem fake answered one status to every call, so the split was never tested.

A second defect sits behind it. A refreshed pair the store refuses is held (`unpersisted`), but every later token request first tries to store it and throws. Even a fix that kept the sign-in would fail all requests after the first refresh, about an hour later.

`gh release list` is empty: no packaged build has shipped, so no installed user holds a Keychain item. The Developer ID provisioning profile that release signing requires (ADR-0002, "Keychain entitlement") does not exist yet.

## Options considered

Labels: **M** measured this session, **D** documented (Apple or this repo), **I** inferred, not probed.

- **Data protection Keychain (today).** Security: item bound to PDTBar's access group, this device only, never synced or restored to another Mac (D). Prompts: none (D, M). Unsigned dev builds cannot write at all (M). Release and Homebrew need the Developer ID provisioning profile embedded; `package_app.sh` already does it and refuses a notarized build without it (M); a cask ships that signed bundle unchanged (I). Migration: none, nothing shipped (M).
- **Legacy login keychain, no access group.** Security: per-item ACL bound to the signing identity's designated requirement; ignores `ThisDeviceOnly`, so the item moves with `login.keychain-db` backups and Migration Assistant (D, I). No profile needed (D). Prompts: none for a stable Developer ID identity across updates (D). An ad-hoc build's designated requirement is its cdhash, so every rebuild prompts on its first read, which is at launch (I, not probed because it prompts). Breaks "launch never prompts" for the dev loop and gains nothing for releases once a profile exists.
- **File in Application Support.** Plain 0600: no prompts, works on any signing, already the dev store behind `--pdt-credential-file` (M). Every process running as the user reads it silently, and Time Machine copies it unless excluded (D). Encrypted: the key needs a home, which is the Keychain again or a key in the binary (obfuscation) (I). Contradicts ADR-0002 decision 6.
- **In memory only.** Nothing at rest; works on any build (I). A sign-in per launch fails plug-and-play for a menu bar app that relaunches at every login (I). Acceptable only as a fallback inside one session.

## Decision

1. **Keep the data protection Keychain as the only durable store.** It is the only option that is both silent and private. The Keychain was not the defect; treating "could not save" as "not connected" was.
2. **Hold, never drop (bug fix, merge by default).** `PDTConnection` keeps the latest change the store refused (sign-in, pasted token, refreshed pair, server rejection, disconnect) in one private slot and retries the save at the start of every operation. A check reads that slot before the store, so Check again, relaunch-free retries, refresh, and 401 handling never turn a held connection into *Not connected*. Only PDT signs a user out. Under this decision alone an unsaved credential is not handed to the API, which extends ADR-0002 decision 3's then rule for refused rotated pairs to every change, and the menu says so right after sign-in. Decision 3 changes both. A `-34018` on a read stays an access error, never "nothing stored".
3. **[needs sign-off] Use a held credential for the session.** When the store refuses a sign-in or pasted token, PDTBar stays connected until it quits and says *Connection not saved* from the moment sign-in returns. A refreshed pair the store refused is used from memory and retried. This changes ADR-0002 decision 3 ("the rotated pair is stored before it is used") to "stored before use when the store accepts it; otherwise used from memory, retried on every later operation, and lost on quit". Nothing is written anywhere new. Done by the commit `feat(auth): stay connected for the session when the Keychain refuses the sign-in`, which also rewords ADR-0002 decision 3. It stays Proposed until Bram signs off; reverting that commit restores decision 2's behaviour. As built: `connected` carries `saved` or `thisSessionOnly`, a refresh or rejection of a held credential is held behind it, a rejected or disconnected credential is never used again, every sync end reports how the credential is kept, and Data health reads `Connected, not saved` without raising a cause.
4. **[needs sign-off] Durable local builds come from signing, not a new store.** Create the Developer ID provisioning profile (already an ADR-0002 open item). With `PDTBAR_APP_IDENTITY` and `PDTBAR_PROVISIONING_PROFILE` set, `make start` keeps the sign-in across rebuilds with no prompts; access goes by access group, not cdhash (D; not yet proved on this Mac). Without a profile a local build is session-only (after 3) and `--pdt-credential-file` stays the durable dev path.

The login keychain and an Application Support file stay rejected for shipped builds.

## Consequences

- #301 is fixed by 2 alone: Check again never signs out, and an unsaved sign-in is named at sign-in. Without 3, an unentitled build shows *Sign-in not saved* and cannot fetch.
- With 3, an unsigned `make start` build is a working app that asks for one browser sign-in per launch.
- One mechanism replaces `unpersisted`: a single owner for "what the store refused", replayed over the stored state through the existing event table, so a newer sign-in stored by another process still wins.
- The scripted SecItem fake gains the measured read/write split, and `formal/launch-runtime` distinguishes a held credential from an empty store.
- Revisit if PDT adds a revoke API (disconnect could then revoke an unsaved session server-side).
