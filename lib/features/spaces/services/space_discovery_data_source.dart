import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

abstract class SpaceDiscoveryDataSource {
  Future<QueryPublicRoomsResponse> queryPublicRooms({
    int? limit,
    String? since,
    String? server,
    PublicRoomQueryFilter? filter,
  });

  Future<GetSpaceHierarchyResponse> getSpaceHierarchy(
    String roomId, {
    int? maxDepth,
    bool? suggestedOnly,
  });

  /// Joins [roomIdOrAlias] and waits until the resulting room is in the
  /// local sync. Returns the joined room id.
  Future<String> joinRoom(String roomIdOrAlias, {List<String>? via});

  /// True if the user is already a `join` member of [roomId].
  bool isMember(String roomId);

  /// True when [roomId] resolves to a space (room type `m.space`). Used
  /// by the dialog after a join to decide whether to select the space
  /// and pop, or remain in the preview.
  bool isSpace(String roomId);
}

class LiveSpaceDiscoveryDataSource implements SpaceDiscoveryDataSource {
  LiveSpaceDiscoveryDataSource(this._client);

  final Client _client;

  @override
  Future<QueryPublicRoomsResponse> queryPublicRooms({
    int? limit,
    String? since,
    String? server,
    PublicRoomQueryFilter? filter,
  }) {
    return _client.queryPublicRooms(
      limit: limit,
      since: since,
      server: server,
      filter: filter,
    );
  }

  @override
  Future<GetSpaceHierarchyResponse> getSpaceHierarchy(
    String roomId, {
    int? maxDepth,
    bool? suggestedOnly,
  }) {
    return _client.getSpaceHierarchy(
      roomId,
      maxDepth: maxDepth,
      suggestedOnly: suggestedOnly,
    );
  }

  @override
  Future<String> joinRoom(String roomIdOrAlias, {List<String>? via}) async {
    final joinedId = await _client.joinRoom(roomIdOrAlias, via: via);
    await _client
        .waitForRoomInSync(joinedId, join: true)
        .timeout(const Duration(seconds: 30));
    return joinedId;
  }

  @override
  bool isMember(String roomId) {
    final room = _client.getRoomById(roomId);
    return room != null && room.membership == Membership.join;
  }

  @override
  bool isSpace(String roomId) =>
      _client.getRoomById(roomId)?.isSpace ?? false;
}

// ── Fake fixture ────────────────────────────────────────────────

class FakeSpaceDiscoveryDataSource implements SpaceDiscoveryDataSource {
  FakeSpaceDiscoveryDataSource({
    this.delay = const Duration(milliseconds: 400),
    this.failHierarchyForRoomId = '!fake-broken:example.org',
    this.failingServers = const {},
  });

  final Duration delay;
  final String failHierarchyForRoomId;
  final Set<String> failingServers;
  final Set<String> _joined = {};

  static final List<PublishedRoomsChunk> _allSpaces = _generateSpaces();
  static final List<PublishedRoomsChunk> _matrixOrgSpaces =
      _generateMatrixOrgSpaces();
  static final Map<String, GetSpaceHierarchyResponse> _hierarchies =
      _generateHierarchies();
  static final Set<String> _spaceIds = {
    ..._allSpaces.map((c) => c.roomId),
    ..._matrixOrgSpaces.map((c) => c.roomId),
    '!fake-subspace-tech:example.org',
    '!fake-subspace-deep:example.org',
  };

  @override
  Future<QueryPublicRoomsResponse> queryPublicRooms({
    int? limit,
    String? since,
    String? server,
    PublicRoomQueryFilter? filter,
  }) async {
    await Future<void>.delayed(delay);
    if (server != null && failingServers.contains(server)) {
      throw MatrixException.fromJson(<String, Object?>{
        'errcode': 'M_FORBIDDEN',
        'error': 'Federation denied by $server',
      });
    }
    final source = switch (server) {
      null => _allSpaces,
      'matrix.org' => _matrixOrgSpaces,
      _ => const <PublishedRoomsChunk>[],
    };
    final term = filter?.genericSearchTerm?.trim().toLowerCase();
    final filtered = (term == null || term.isEmpty)
        ? source
        : source.where((c) {
            final hay = [
              c.name,
              c.topic,
              c.canonicalAlias,
            ].whereType<String>().map((s) => s.toLowerCase());
            return hay.any((s) => s.contains(term));
          }).toList();
    final pageSize = limit ?? 20;
    final start = since == null ? 0 : int.tryParse(since) ?? 0;
    final end = math.min(start + pageSize, filtered.length);
    final chunk = start >= filtered.length
        ? <PublishedRoomsChunk>[]
        : filtered.sublist(start, end);
    final nextBatch = end < filtered.length ? end.toString() : null;
    return QueryPublicRoomsResponse(
      chunk: chunk,
      nextBatch: nextBatch,
      totalRoomCountEstimate: filtered.length,
    );
  }

  @override
  Future<GetSpaceHierarchyResponse> getSpaceHierarchy(
    String roomId, {
    int? maxDepth,
    bool? suggestedOnly,
  }) async {
    await Future<void>.delayed(delay);
    if (roomId == failHierarchyForRoomId) {
      throw Exception('Fake hierarchy failure for $roomId');
    }
    final hit = _hierarchies[roomId];
    if (hit != null) return hit;
    return _hierarchyForUnknownSpace(roomId);
  }

  // ── Fixture generation ───────────────────────────────────────

  static List<PublishedRoomsChunk> _generateSpaces() {
    const themes = [
      ['Quantum HQ', 'Default home for quantum-matrix users.'],
      ['Linux', 'All things Linux: distros, kernels, tooling.'],
      ['Self-Hosted', 'Run your own services. Helpful tips and rants.'],
      ['Flutter Devs', 'Cross-platform UI talk, package showcases.'],
      ['Homelab', 'Racks, hypervisors, weird DIY networking.'],
      ['Photography', 'Gear, technique, critique.'],
      ['Music Lounge', 'Sharing what we listen to.'],
      ['Cooking', 'Recipes, kitchen disasters, sourdough.'],
      ['Books', 'Fiction, nonfiction, recommendations.'],
      ['Movies & TV', null],
      ['Gaming', 'Discussion across platforms and genres.'],
      ['Indie Web', 'Personal sites, RSS, the open web.'],
      ['Privacy', 'Threat models, OPSEC, tooling.'],
      ['Cycling', 'Routes, mechanicals, n+1.'],
      ['Coffee', null],
      ['Open Source', 'Contributing, maintaining, governance.'],
      ['News & Current Events', 'Mostly civil discussion.'],
      ['Travel', 'Trip reports and planning.'],
      ['Languages', 'Polyglots and learners.'],
      ['Dev Tools', 'Editors, terminals, CLIs.'],
      ['Astro', null],
      ['Fediverse', 'Mastodon, Lemmy, the rest.'],
      ['Crypto', 'Cryptography, not coins.'],
      ['Math', 'From arithmetic to algebraic topology.'],
      ['Birding', 'eBird logs, field marks.'],
      ['Woodworking', null],
      ['3D Printing', 'Prints, slicers, filament.'],
      ['DIY Electronics', 'Hand-soldered fun.'],
      ['Mech Keyboards', 'Switches, layouts, group buys.'],
      ['Retro Gaming', null],
      ['Movies (Foreign)', 'World cinema appreciation.'],
      ['Whisky', 'Tasting notes and bottle hunts.'],
      ['Tea', null],
      ['Hiking', 'Trails and trip reports.'],
      ['Climbing', 'Routes, gyms, gear.'],
      ['Running', 'Training plans and race reports.'],
      ['Yoga', null],
      ['Stoicism', 'Practical philosophy.'],
      ['Productivity', 'Systems and habits.'],
      ['Note-taking', 'Org, Obsidian, Logseq, paper.'],
      ['Esoteric Programming', null],
      ['Functional Programming', 'Haskell, OCaml, Rust folks too.'],
      ['Rust', 'Systems programming with rustc.'],
      ['Go', 'Goroutines, channels, build tags.'],
      ['Zig', null],
      ['Game Dev', 'Engines, art, design.'],
      ['Pixel Art', 'Aseprite, palettes, animation.'],
      ['Synthesizers', 'Modular, soft, vintage.'],
      ['Electronic Music', null],
      ['Classical Music', 'Performances, recordings, scores.'],
      ['Jazz', 'Standards and adventurous corners.'],
      ['Plants', 'Houseplants and gardens.'],
      ['Aquariums', 'Freshwater, planted, reef.'],
      ['Star Trek', null],
      ['Star Wars', null],
      ['Anime', 'Currently airing and classics.'],
      ['Tabletop RPG', 'D&D, indie systems, GM advice.'],
      ['Board Games', 'Heavy euros to filler.'],
      ['Puzzle Hunts', null],
      ['Math Puzzles', 'Riddles and Olympiad problems.'],
    ];
    final rng = math.Random(42);
    return [
      for (var i = 0; i < themes.length; i++)
        PublishedRoomsChunk(
          guestCanJoin: false,
          numJoinedMembers: 5 + rng.nextInt(11000),
          roomId: '!fake-space-$i:example.org',
          worldReadable: true,
          name: themes[i][0],
          topic: themes[i][1],
          canonicalAlias:
              '#${themes[i][0]!.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-')}'
              ':example.org',
          roomType: 'm.space',
        ),
    ];
  }

  static List<PublishedRoomsChunk> _generateMatrixOrgSpaces() {
    const themes = [
      ['matrix.org Lounge', 'General chat for matrix.org users.'],
      ['Synapse', 'Discussion of the Synapse homeserver.'],
      ['Element', 'Element client community.'],
      ['Matrix Spec', 'Spec process and proposals.'],
      ['Bridges', 'IRC, XMPP, Discord, Slack bridges.'],
      ['Federation', 'Cross-server topics.'],
      ['New to Matrix', 'Newcomer questions and pointers.'],
    ];
    final rng = math.Random(7);
    return [
      for (var i = 0; i < themes.length; i++)
        PublishedRoomsChunk(
          guestCanJoin: false,
          numJoinedMembers: 200 + rng.nextInt(40000),
          roomId: '!fake-mxorg-$i:matrix.org',
          worldReadable: true,
          name: themes[i][0],
          topic: themes[i][1],
          canonicalAlias:
              '#${themes[i][0].toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-')}'
              ':matrix.org',
          roomType: 'm.space',
        ),
    ];
  }

  static Map<String, GetSpaceHierarchyResponse> _generateHierarchies() {
    final out = <String, GetSpaceHierarchyResponse>{};

    SpaceRoomsChunk$2 chunk({
      required String roomId,
      required String name,
      String? topic,
      int members = 50,
      String? roomType,
      String? alias,
    }) {
      return SpaceRoomsChunk$2(
        guestCanJoin: false,
        numJoinedMembers: members,
        roomId: roomId,
        worldReadable: true,
        childrenState: const [],
        name: name,
        topic: topic,
        canonicalAlias: alias,
        roomType: roomType,
      );
    }

    // Quantum HQ — rich hierarchy with a subspace.
    out['!fake-space-0:example.org'] = GetSpaceHierarchyResponse(
      rooms: [
        chunk(
          roomId: '!fake-space-0:example.org',
          name: 'Quantum HQ',
          topic: 'Default home for quantum-matrix users.',
          members: 1247,
          roomType: 'm.space',
          alias: '#quantum-hq:example.org',
        ),
        chunk(
          roomId: '!fake-room-lounge:example.org',
          name: 'lounge',
          topic: 'Casual hangout.',
          members: 412,
          alias: '#lounge:example.org',
        ),
        chunk(
          roomId: '!fake-room-offtopic:example.org',
          name: 'offtopic',
          members: 138,
          alias: '#offtopic:example.org',
        ),
        chunk(
          roomId: '!fake-room-devtalk:example.org',
          name: 'dev-talk',
          topic: 'Technical chatter.',
          members: 201,
          alias: '#dev-talk:example.org',
        ),
        chunk(
          roomId: '!fake-subspace-tech:example.org',
          name: 'Tech',
          topic: 'Subspace for technical rooms.',
          members: 320,
          roomType: 'm.space',
          alias: '#tech:example.org',
        ),
        chunk(
          roomId: '!fake-room-announcements:example.org',
          name: 'announcements',
          members: 87,
          alias: '#announcements:example.org',
        ),
      ],
    );

    // Tech subspace under Quantum HQ.
    out['!fake-subspace-tech:example.org'] = GetSpaceHierarchyResponse(
      rooms: [
        chunk(
          roomId: '!fake-subspace-tech:example.org',
          name: 'Tech',
          topic: 'Subspace for technical rooms.',
          members: 320,
          roomType: 'm.space',
          alias: '#tech:example.org',
        ),
        chunk(
          roomId: '!fake-room-linux-tech:example.org',
          name: 'linux',
          members: 144,
          alias: '#linux-tech:example.org',
        ),
        chunk(
          roomId: '!fake-room-homelab:example.org',
          name: 'homelab',
          members: 98,
          alias: '#homelab-tech:example.org',
        ),
        chunk(
          roomId: '!fake-subspace-deep:example.org',
          name: 'Deep dive',
          topic: 'Nested subspace for testing recursion.',
          members: 12,
          roomType: 'm.space',
          alias: '#deep:example.org',
        ),
      ],
    );

    // Deep nested subspace.
    out['!fake-subspace-deep:example.org'] = GetSpaceHierarchyResponse(
      rooms: [
        chunk(
          roomId: '!fake-subspace-deep:example.org',
          name: 'Deep dive',
          topic: 'Nested subspace for testing recursion.',
          members: 12,
          roomType: 'm.space',
          alias: '#deep:example.org',
        ),
        chunk(
          roomId: '!fake-room-deeper:example.org',
          name: 'deeper',
          members: 4,
          alias: '#deeper:example.org',
        ),
      ],
    );

    // Empty space — preview shows "No rooms yet".
    out['!fake-space-9:example.org'] = GetSpaceHierarchyResponse(
      rooms: [
        chunk(
          roomId: '!fake-space-9:example.org',
          name: 'Movies & TV',
          members: 88,
          roomType: 'm.space',
          alias: '#movies-tv:example.org',
        ),
      ],
    );

    return out;
  }

  @override
  Future<String> joinRoom(String roomIdOrAlias, {List<String>? via}) async {
    await Future<void>.delayed(delay);
    var id = roomIdOrAlias;
    if (id.startsWith('#')) {
      final match = _allSpaces.firstWhere(
        (s) => s.canonicalAlias == id,
        orElse: () => _allSpaces.first,
      );
      id = match.roomId;
    }
    _joined.add(id);
    return id;
  }

  @override
  bool isMember(String roomId) => _joined.contains(roomId);

  @override
  bool isSpace(String roomId) => _spaceIds.contains(roomId);

  GetSpaceHierarchyResponse _hierarchyForUnknownSpace(String roomId) {
    final spaceMatch = _allSpaces.firstWhere(
      (s) => s.roomId == roomId,
      orElse: () => _allSpaces.first,
    );
    return GetSpaceHierarchyResponse(
      rooms: [
        SpaceRoomsChunk$2(
          guestCanJoin: false,
          numJoinedMembers: spaceMatch.numJoinedMembers,
          roomId: spaceMatch.roomId,
          worldReadable: true,
          childrenState: const [],
          name: spaceMatch.name,
          topic: spaceMatch.topic,
          canonicalAlias: spaceMatch.canonicalAlias,
          roomType: 'm.space',
        ),
        SpaceRoomsChunk$2(
          guestCanJoin: false,
          numJoinedMembers: 64,
          roomId: '!fake-room-${roomId.hashCode}-a:example.org',
          worldReadable: true,
          childrenState: const [],
          name: 'general',
        ),
        SpaceRoomsChunk$2(
          guestCanJoin: false,
          numJoinedMembers: 21,
          roomId: '!fake-room-${roomId.hashCode}-b:example.org',
          worldReadable: true,
          childrenState: const [],
          name: 'meta',
        ),
      ],
    );
  }
}

// ── Selector ────────────────────────────────────────────────────

/// Build-time flag. Run with
/// `flutter run --dart-define=KOHERA_FAKE_DISCOVERY=true` to swap the
/// live Matrix client for canned data.
const bool kFakeSpaceDiscovery = bool.fromEnvironment(
  'KOHERA_FAKE_DISCOVERY',
);

SpaceDiscoveryDataSource defaultSpaceDiscoveryDataSource(Client client) {
  if (kFakeSpaceDiscovery) {
    debugPrint('[Kohera] SpaceDiscovery: using fake data source');
    return FakeSpaceDiscoveryDataSource();
  }
  return LiveSpaceDiscoveryDataSource(client);
}
