# Sharing a Solitaire deal

A competition replays the original deal. A help request forks the current position. Both can play locally after the recipient loads the share.

## Local entry points

| Action | API | Starting state |
| --- | --- | --- |
| Choose an ordinary deal | `KlondikeGame()` or `game.newDeal()` | Fresh seed. New Deal carries forward remaining power-ups. |
| Create a time or moves challenge | Read `completedDeal` from the page state, then call `BeatChallenge.fromCompleted(goal, result)` | The owner must have won a fresh-start attempt. Store both metrics and the chosen goal. |
| Play a challenge | `SolitaireGamePage.fromDeal(challenge.owner.deal)` | Original shuffled deck, opening inventory, zero moves, score and time. |
| Request help | `pageState.captureHelp().encode()` | All piles, cumulative stats, remaining inventory, elapsed play and active Freeze. |
| Play a help copy | `SolitaireGamePage.fromHelp(HelpSnapshot.decode(text))` | Detached cards and local undo history beginning at the handoff. |
| Compare completed attempts | `challenge.compare(completedDeal)` | Lower wins on the selected metric. An equal metric ties regardless of the secondary metric. |

Attach a `GlobalKey<SolitaireGamePageState>` to the owner's page. Capture synchronously before awaiting a network request. Read the latched elapsed time after the final move and present the share action while the board is still won. Undoing a win makes the board incomplete again. Show millisecond precision on the result screen when two displayed whole-second times would appear tied. On receipt, decode first, then push a fresh page route. Keep the owner's route or saved session intact. Use a separate route identity when opening a second link while the app is running. If the router keeps the owner's page mounted underneath, pause its clock on route coverage when adding the router. An app lifecycle callback alone cannot detect a covered route.

```dart
// Within the share-button handler after a win.
final result = ownerPageKey.currentState!.completedDeal;
if (result == null) return;
final challenge = BeatChallenge.fromCompleted(BeatGoal.moves, result);
final wire = challenge.toJson();

// In the route that receives the decoded competition payload.
final incoming = BeatChallenge.fromJson(wire);
final challengerPage = SolitaireGamePage.fromDeal(incoming.owner.deal);
```

For a help request the corresponding two expressions are `ownerPageKey.currentState!.captureHelp().encode()` and `SolitaireGamePage.fromHelp(HelpSnapshot.decode(payload))`. The helper can take a new snapshot of their own board. An imported board's eventual victory is a help result. The app can launch an ordinary fresh attempt through New Deal.

## Reproduce version 1

- Card IDs are 0–51, in hearts, diamonds, clubs, spades order, Ace through King in each suit. All serialized piles are bottom-to-top. The final stock element is the next draw.
- The five fields of a deal are `version`, `rules`, `seed`, `initialFreezeCount`, and `initialWandCount`. Version 1 pins the algorithm and layout. The rules ID `relaxed-draw1-v1` includes draw-one/recycle, descending rank regardless of color, and any card on an empty column. Keep the current tap, Wand, undo and move-count semantics when validating a V1 attempt.
- Start with card IDs in ascending order. For Fisher–Yates indices 51 down to 1, take the next Park–Miller state `(48271 * state) % 2147483647`, starting at the supplied seed (1–2147483646). Subtract one for the sample. For a bound of `i + 1`, retry if the sample is at least `2147483646 - (2147483646 % bound)`. Swap index `i` with `sample % bound`. The largest product fits exactly in a JavaScript number.
- Pop from the end to fill columns 0–6 consecutively, giving column i exactly i+1 cards. Only each column's last card starts face-up. Pop the rest from the end into the face-down stock. The seed-1 test pins all 52 positions. Preserve V1 readers and vectors when introducing later versions.
- `BoardSnapshot` stores exact ordered stock, waste, four foundations, seven tableau columns, each card's face flag, score, moves and power-up counts. Capture and decode validate the same invariants. The visible tableau can contain gaps after extraction. Undo stacks and animation objects stay local.
- `HelpSnapshot` adds a versioned clock envelope. The game page measures foreground play. It carries milliseconds already played and remaining Freeze duration across handoff, with zero time added in transit. If the owner had started, time resumes when the helper's board opens in the foreground. A fresh challenge starts on the first game interaction. Freeze retains the existing ten-through-zero display sequence. A new deal clears any active Freeze interval while retaining the remaining charge counts. Competition time stops on victory.
- The old app held boards in memory without a recorded seed or portable save. Previously played random deals cannot be reconstructed retroactively. The new wire contract starts with deals created by this patch.

## Connect one HTTPS link

1. Choose the Solitaire HTTPS origin and production app IDs. This base uses `com.example.solitaire` on both platforms. Publish an opaque, randomly generated share ID at `/s/<id>`. The ID identifies one invitation, even when multiple players challenge the same seed.
2. Configure iOS Associated Domains and serve `/.well-known/apple-app-site-association` with the Apple application identifier and the share path. Configure an Android verified HTTPS intent filter and serve `/.well-known/assetlinks.json` with the production package name and app-signing SHA-256 fingerprint. Firebase Hosting should serve the two static association files directly and rewrite `/s/**` to the Flutter Web entry point. Use Flutter's path URL strategy for the browser and handle both cold-start and warm incoming URIs. Preserve the link through the current splash transition.
3. Load one immutable document at `shares/{shareId}` per open. Use a server-controlled `kind` of `beat` or `help` to select the decoder. A beat record carries `BeatChallenge.toJson()` in `challenge`. A help record carries `HelpSnapshot.encode()` in `snapshotJson`. Keep owner UID, creation time and expiry in separate fields. A callable create action can validate the schema, enforce payload size, set the server timestamp/expiry, and return a share ID. Exempt `snapshotJson` from indexing. Firestore Standard restricts nested arrays, which the encoded string preserves. Enforce expiry on reads and give malformed, expired and unsupported shares a recovery screen.
4. Keep draws, moves, timers and undo on-device. Store results separately by share and attempt ID, with retry-safe writes. Use anonymous authentication where ownership is needed, restrict writes, and apply App Check and rate limits to share creation/submission. The server should never accept client-reported victory, time or moves as verified simply because the JSON decoded successfully.
5. For verified moves, record ordered commands using stable card IDs, source/destination and depth as needed. Replay them against the same rules, including undo, automatic flips and Wand effects, and derive completion and moves from the final state. For verified time, separately define evidence for elapsed play, pause and Freeze. A replay proves a move sequence, while offline clients can report arbitrary clock values. For casual friend challenges, label submitted times as client-reported until a trusted timing policy exists.
6. A helper's reply should reference the exact immutable parent snapshot and its own attempt. Replay the helper's commands into a new copy. Mark a solved result only when all four foundations contain 13 cards. Partial help can carry a best line. Returning a reply must never overwrite the owner's active board.

Exercise installed/uninstalled Android and iOS, a direct browser open and refresh, warm and cold starts, duplicate submission, expired and malformed links, and a helper reply after the owner has continued playing. Device association, share UI, hosting and backend are the next integration stage.

Platform references include [Apple associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains), [Android App Links](https://developer.android.com/training/app-links/verify-applinks), [Firebase Hosting rewrites](https://firebase.google.com/docs/hosting/full-config), [Firestore value types](https://firebase.google.com/docs/firestore/manage-data/data-types).
