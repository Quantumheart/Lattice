# Discord vs Lattice: Feature Gap Analysis

_Generated: 2026-02-25_

This document compares Discord's feature set against Lattice's current implementation, identifies features Discord users have long requested but Discord hasn't delivered, and highlights Lattice's unique advantages as a Matrix-based client.

---

## Table of Contents

1. [Discord Features Lattice Does NOT Implement](#1-discord-features-lattice-does-not-implement)
2. [Most Requested Features Discord Won't Give Users](#2-most-requested-features-discord-wont-give-users)
3. [Lattice's Unique Advantages Over Discord](#3-lattices-unique-advantages-over-discord)
4. [Strategic Recommendations](#4-strategic-recommendations)

---

## 1. Discord Features Lattice Does NOT Implement

### Voice & Video (entirely absent in Lattice)

| Discord Feature | Description | Matrix SDK Support |
|----------------|-------------|-------------------|
| Voice channels | Persistent drop-in/drop-out voice rooms | Yes (VoIP/WebRTC) |
| Video calls | Webcam in voice channels and DMs | Yes (WebRTC) |
| Screen sharing / Go Live | Stream screen to channel, up to 50 viewers | Partial |
| Stage channels | Moderated audio events (Clubhouse-style) | No native equivalent |
| Soundboard | Play short audio clips in voice | No |
| Noise suppression (Krisp) | AI background noise removal | No |
| Activities | Embedded games/apps in voice (Watch Together, Poker, etc.) | No |
| Clips | Capture and share gameplay clips while streaming | No |
| Voice entry sounds | Custom sound when joining voice (Nitro) | No |

### Rich Messaging

| Discord Feature | Description | Lattice Status |
|----------------|-------------|----------------|
| Reactions | Emoji reactions on messages | SDK supports, **no UI** |
| Message editing | Edit sent messages | SDK supports, **no UI** |
| Message deletion | Delete/redact messages | SDK supports, **no UI** |
| Typing indicators | "User is typing..." | SDK supports, **no UI** |
| Read receipts | See who has read a message | SDK supports, **no UI** |
| Threads | Branching conversations off a message | Matrix supports, **no UI** |
| Forum channels | Structured Q&A with tags, list/gallery view | No equivalent |
| Polls | Native polling with up to 10 choices | No |
| Rich link previews | URL preview cards with images/descriptions | No |
| Markdown rendering | Bold, italic, code blocks, spoilers, headers, lists | No (plaintext only) |
| Custom emoji & stickers | Server-specific emoji packs | No |
| GIF picker | Integrated Tenor/GIPHY search | No |
| Slash commands | `/command` interface for bots and built-in actions | No |
| Pinned messages | Pin important messages with a pins panel | No UI |
| Voice messages | Record and send audio clips | No |
| Message components | Buttons, select menus, modals | No |
| Embeds | Rich embeds with titles, fields, images, footers | No |
| Announcement channels | Publish messages followable by other servers | No equivalent |

### Server/Space Management

| Discord Feature | Description | Lattice Status |
|----------------|-------------|----------------|
| Granular role permissions | 40+ individual permissions per role | Power levels only, no granular UI |
| Channel categories | Collapsible groups of channels | No (flat space hierarchy) |
| Channel permission overrides | Per-channel role overrides | No UI |
| Audit log | Track all admin/mod actions | No |
| Server templates | Clone server structure | No |
| Onboarding flow | Customizable new-member role/channel selection | No |
| Welcome screen | Custom landing page for new members | No |
| Rules screening | Require rule acceptance before chatting | No |
| Vanity URLs | Custom invite links | No |
| Server boosting / tiers | Community perks from boosters | No equivalent |
| Invite management | Track invite links, referrers, usage stats | No |
| Server insights / analytics | Member activity, growth trends, retention | No |
| "View server as" role | Preview server from any role's perspective | No |
| Linked roles | Auto-assign roles based on connected accounts | No |

### Moderation

| Discord Feature | Description | Lattice Status |
|----------------|-------------|----------------|
| AutoMod | Keyword filtering, spam detection, slur blocking | No |
| Timeouts | Temporarily restrict a user | No UI (power levels exist) |
| Ban/kick with reason | Remove members with logged reasons | No UI |
| Slow mode | Rate-limit messages per channel | No |
| NSFW channel gating | Age-restricted channels | No |
| Raid protection | Verification levels, DM spam filters | No |
| Message reporting | Report to Trust & Safety | No |
| Bulk message deletion | Delete multiple messages at once | No |

### Social & Discovery

| Discord Feature | Description | Lattice Status |
|----------------|-------------|----------------|
| Rich user profiles | Banners, bios, connected accounts, badges, effects | Basic profile only |
| Custom status | Status message with emoji and expiration | No |
| Activity status | "Playing...", "Listening to Spotify..." | No |
| Rich Presence | Detailed game activity with join buttons | No |
| Server Discovery | Browse/search public servers by category | No |
| Friend system | Add friends, friend requests, mutual servers | No |
| Group DMs (up to 10) | Group chat outside server context | Matrix supports, no dedicated UI |
| User notes | Private notes on other users | No |
| Scheduled events | Create events with RSVPs | No |
| Activities | HTML5 games in voice channels | No |
| Connected accounts | Link Spotify, YouTube, Twitch, GitHub, etc. | No |

### Bot & Integration Ecosystem

| Discord Feature | Description | Lattice Status |
|----------------|-------------|----------------|
| Bot framework / API | Webhook and bot-token automation | No (Matrix has bots, but no Lattice UI) |
| App Directory | Discoverable marketplace of verified apps | No |
| Webhooks | Post from external services | No UI |
| OAuth2 / "Login with Discord" | Third-party auth integration | No equivalent |
| Embedded App SDK | Build Activities inside voice channels | No |
| In-App Purchases | Native IAP for developers | No |

### Nitro / Monetization

| Discord Feature | Description | Lattice Status |
|----------------|-------------|----------------|
| Server subscriptions | Paid tiers ($2.99-$199.99/mo) | No |
| Server shop | Sell downloadable files & premium roles | No |
| Super Reactions | Animated premium reactions | No |
| Custom app icons/themes | Nitro-exclusive customization | No |
| Higher upload limits | Up to 500MB with Nitro | No |
| HD streaming | 4K 60fps for Nitro | No |
| Quests | Sponsored gameplay challenges | No |

### Platform & UX

| Discord Feature | Description | Lattice Status |
|----------------|-------------|----------------|
| Game overlay | In-game Discord widget (Windows) | No |
| Streamer mode | Hide personal info during streams | No |
| Multiple theme options | Light, Ash, Dark, Onyx | Light/Dark + Material You (advantage) |
| Message density | Spacious, Default, Compact | 3 density levels (parity) |
| Keyboard shortcuts | Extensive navigation shortcuts | Space nav only (Ctrl+0-9) |

---

## 2. Most Requested Features Discord Won't Give Users

These are features with years of community demand that Discord has been slow or unwilling to implement. Sources include Discord's feedback forums, Reddit, and tech press.

### Rank 1: End-to-End Encryption for Text Messages
Discord implemented E2EE for audio/video via the DAVE protocol (mandatory March 2026), but **text messages remain entirely unencrypted** and stored in plaintext on Discord's servers. This is one of the most consistently upvoted feature requests. Users frequently compare Discord unfavorably to WhatsApp, Signal, and Telegram. Community plugins like DiscordCrypt exist but violate Discord's ToS.

**Lattice advantage: Full text E2EE with cross-signing, key backup, device verification, and recovery keys.**

### Rank 2: Custom Themes / Full UI Theming
Users have requested full CSS/theme customization for 8+ years. Discord only offers Light/Ash/Dark/Onyx. Third-party mods like BetterDiscord fill the gap but violate ToS. Discord added the Onyx true-black theme in March 2025 but continues to resist user-created themes.

**Lattice advantage: Material You dynamic color theming extracts colors from the user's system wallpaper/accent.**

### Rank 3: Self-Hosting / Federation / Data Sovereignty
Privacy-conscious users want the ability to run their own server and own their data. Discord is entirely centralized with zero self-hosting capability. Alternatives like Matrix/Element, Rocket.Chat, Mattermost, and Revolt exist specifically because of this gap.

**Lattice advantage: Built on Matrix, which is inherently federated. Users can host their own homeserver and federate with the global network.**

### Rank 4: Read Receipts for DMs
One of the most debated requests. Users want to see when DMs have been read, similar to iMessage, WhatsApp, and Telegram. Proposals suggest making it opt-in. Discord has not implemented this despite years of requests.

### Rank 5: Message Scheduling
No built-in way to schedule messages for later delivery. Users rely on third-party bots. Competitors like Slack and Teams have had native message scheduling for years.

### Rank 6: Visible Edit History
Discord shows an "(edited)" marker but doesn't let users view previous versions of edited messages. Telegram and other platforms show full edit history.

### Rank 7: Nested Channels / Sub-Channels
Discord only supports two-tier hierarchy (Categories > Channels). Users want deeper nesting for complex communities. Guilded offered this as a differentiator before being acquired by Roblox.

### Rank 8: Larger Group DM Size
Group DMs are capped at 10 members with no way to increase, even with Nitro. Frequently complained about.

### Rank 9: Custom Notification / Call Sounds
Only one global notification sound. No per-channel, per-server, or per-contact customization. The only sound customization is Nitro-gated voice entry sounds.

### Rank 10: Better Search
Discord's search is notoriously limited — slow, poor filtering, no cross-server search, no saved queries. Slack's search is widely considered far superior.

### Rank 11: Multi-Account Support (proper)
Discord added a basic account switcher on desktop/web but mobile support remains limited. Many users maintain separate accounts for personal/professional/gaming use and find the experience clunky.

**Lattice advantage: ClientManager supports multiple simultaneous accounts natively.**

### Rank 12: Offline Message Access
No way to browse messages without a server connection. Everything requires internet access.

**Lattice advantage: Local SQLite database stores messages for offline access.**

### Rank 13: Rich Text Editor (WYSIWYG)
Users want a formatting toolbar instead of memorizing Markdown syntax. Particularly requested by non-technical users.

### Rank 14: Performance Over Feature Bloat
Recurring complaint: Discord keeps shipping monetization features (Super Reactions, entry sounds, Quests, cosmetics) while the client gets increasingly sluggish. Users say they want stability and performance over new paid features. PC Gamer ran the article "I am begging Discord to stop bombarding me with pointless new features."

### Rank 15: Privacy and Data Control
Intensified after the October 2025 breach exposing ~70,000 government ID photos via third-party vendor Persona. Users want granular data control, true data deletion, and less invasive collection. Discord's February 2026 age verification mandate (face scan / ID upload) further inflamed privacy concerns.

---

## 3. Lattice's Unique Advantages Over Discord

| Area | Discord | Lattice / Matrix |
|------|---------|-----------------|
| **Text E2EE** | Not available (audio/video only via DAVE) | Full E2EE: cross-signing, key backup, device verification, recovery keys, auto-unlock |
| **Self-hosting** | Impossible — fully centralized | Core Matrix feature — run your own homeserver |
| **Federation** | Walled garden — no interop | Federate with any Matrix homeserver globally |
| **Data sovereignty** | Discord owns and stores all data in plaintext | You own your data on your homeserver |
| **Open protocol** | Proprietary, closed source, API TOS restrictions | Open Matrix specification, fully interoperable |
| **Dynamic theming** | 4 fixed themes (Light/Ash/Dark/Onyx) | Material You: dynamic color from system wallpaper/accent |
| **Multi-account** | Basic switcher, poor mobile support | ClientManager with native multi-account support |
| **Offline access** | Requires internet connection | Local SQLite database for offline message browsing |
| **No feature bloat** | Increasingly cluttered with monetization features | Focused, lean client |
| **No ads / quests / upsells** | Constant Nitro prompts, Quests, Shop nudges | No monetization pressure |
| **Session recovery** | Standard session management | Advanced: OLM account backup, soft logout recovery, device re-registration |
| **No vendor lock-in** | Locked to Discord's platform | Any Matrix client can access your data |

---

## 4. Strategic Recommendations

### High Priority — Close the table-stakes gap
These features are expected in any modern chat client. The Matrix SDK already supports them; they only need UI implementation.

1. **Reactions** — emoji reactions on messages (SDK ready)
2. **Message editing** — edit sent messages with history (SDK ready)
3. **Message deletion/redaction** — delete messages (SDK ready)
4. **Typing indicators** — "User is typing..." display (SDK ready)
5. **Markdown rendering** — bold, italic, code blocks, spoiler tags
6. **Rich link previews** — URL preview cards with image/description
7. **Read receipts** — optional, toggleable (SDK ready)

### Medium Priority — Differentiate and delight
These features would make Lattice competitive with Discord for daily-driver use.

8. **Threads** — Matrix MSC3440 threading support
9. **Pinned messages** — pin panel in room details
10. **Voice/video calls** — Matrix VoIP via WebRTC (large effort)
11. **GIF picker** — Tenor/GIPHY integration
12. **Custom emoji** — Matrix custom emoji support
13. **User profiles** — richer profiles with bio, status, badges
14. **Custom status** — set a status message with emoji

### Lower Priority — Power features
These features would appeal to power users and community administrators.

15. **Moderation tools** — ban/kick/timeout UI using Matrix power levels
16. **AutoMod equivalent** — keyword filtering via Matrix bots or client-side
17. **Room directory / discovery** — browse public rooms on homeserver
18. **Audit log** — display Matrix room state history
19. **Scheduled events** — calendar events in rooms
20. **Bot/integration UI** — manage Matrix bots and webhooks

### Lean Into Your Strengths
Lattice should loudly market these advantages that Discord users have begged for but can't get:

- **E2EE for text** — Discord's #1 most-requested missing feature; Lattice has it
- **Self-hosting & federation** — growing demand from privacy-conscious users
- **Data sovereignty** — especially relevant post-Discord data breaches
- **No monetization bloat** — no Nitro upsells, no Quests, no feature gating
- **Open protocol** — no vendor lock-in, interoperable with all Matrix clients
- **Material You theming** — richer visual customization than Discord's 4 fixed themes
