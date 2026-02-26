import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:lattice/widgets/chat/mention_autocomplete_controller.dart';

@GenerateNiceMocks([
  MockSpec<Room>(),
  MockSpec<User>(),
  MockSpec<Client>(),
])
import 'mention_autocomplete_controller_test.mocks.dart';

MockUser _makeUser(String id, String? displayName, {Uri? avatarUrl}) {
  final user = MockUser();
  when(user.id).thenReturn(id);
  when(user.displayName).thenReturn(displayName);
  when(user.avatarUrl).thenReturn(avatarUrl);
  return user;
}

MockRoom _makeJoinedRoom(String id, String name, {String alias = ''}) {
  final room = MockRoom();
  when(room.id).thenReturn(id);
  when(room.getLocalizedDisplayname()).thenReturn(name);
  when(room.canonicalAlias).thenReturn(alias);
  when(room.avatar).thenReturn(null);
  return room;
}

void main() {
  group('MentionAutocompleteController', () {
    late TextEditingController textCtrl;
    late MockRoom mockRoom;
    late MockClient mockClient;
    late List<MockUser> members;
    late List<Room> joinedRooms;

    setUp(() {
      textCtrl = TextEditingController();
      mockRoom = MockRoom();
      mockClient = MockClient();

      members = [
        _makeUser('@alice:example.com', 'Alice'),
        _makeUser('@bob:example.com', 'Bob'),
        _makeUser('@charlie:example.com', 'Charlie'),
      ];

      when(mockRoom.client).thenReturn(mockClient);
      when(mockRoom.getParticipants()).thenReturn(members);
      when(mockRoom.requestParticipants())
          .thenAnswer((_) async => members);

      joinedRooms = [
        _makeJoinedRoom('!general:example.com', 'General',
            alias: '#general:example.com'),
        _makeJoinedRoom('!random:example.com', 'Random',
            alias: '#random:example.com'),
        _makeJoinedRoom('!dev:example.com', 'Development'),
      ];
    });

    tearDown(() {
      textCtrl.dispose();
    });

    // ── Trigger detection ──────────────────────────────────

    test('typing @ activates user autocomplete', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@',
        selection: TextSelection.collapsed(offset: 1),
      );

      expect(ctrl.isActive, isTrue);
      expect(ctrl.triggerType, MentionTriggerType.user);
      expect(ctrl.query, '');

      ctrl.dispose();
    });

    test('typing # activates room autocomplete', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '#',
        selection: TextSelection.collapsed(offset: 1),
      );

      expect(ctrl.isActive, isTrue);
      expect(ctrl.triggerType, MentionTriggerType.room);

      ctrl.dispose();
    });

    test('@ after whitespace activates', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: 'hello @',
        selection: TextSelection.collapsed(offset: 7),
      );

      expect(ctrl.isActive, isTrue);

      ctrl.dispose();
    });

    test('@ inside a word does not activate', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: 'test@example',
        selection: TextSelection.collapsed(offset: 12),
      );

      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test('space in query dismisses autocomplete', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@alice ',
        selection: TextSelection.collapsed(offset: 7),
      );

      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test('no trigger character means inactive', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: 'hello world',
        selection: TextSelection.collapsed(offset: 11),
      );

      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    // ── Filtering ──────────────────────────────────────────

    test('filters users by display name', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@ali',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(ctrl.suggestions.length, 1);
      expect(ctrl.suggestions[0].displayName, 'Alice');

      ctrl.dispose();
    });

    test('filters users by MXID when displayName is null', () {
      members.add(_makeUser('@dave:example.com', null));
      when(mockRoom.getParticipants()).thenReturn(members);

      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@dave',
        selection: TextSelection.collapsed(offset: 5),
      );

      expect(ctrl.suggestions.length, 1);
      expect(ctrl.suggestions[0].displayName, '@dave:example.com');
      expect(ctrl.suggestions[0].id, '@dave:example.com');

      ctrl.dispose();
    });

    test('empty query shows all members', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@',
        selection: TextSelection.collapsed(offset: 1),
      );

      expect(ctrl.suggestions.length, 3);

      ctrl.dispose();
    });

    test('filters rooms by name', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '#gen',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(ctrl.suggestions.length, 1);
      expect(ctrl.suggestions[0].displayName, 'General');
      expect(ctrl.suggestions[0].id, '#general:example.com');

      ctrl.dispose();
    });

    test('room suggestions use canonical alias when available', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '#dev',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(ctrl.suggestions.length, 1);
      // No canonical alias → falls back to room ID.
      expect(ctrl.suggestions[0].id, '!dev:example.com');

      ctrl.dispose();
    });

    // ── Selection ──────────────────────────────────────────

    test('selectSuggestion inserts mention text and dismisses', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@ali',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(ctrl.suggestions.isNotEmpty, isTrue);
      ctrl.selectSuggestion(ctrl.suggestions[0]);

      expect(textCtrl.text, '@Alice ');
      expect(textCtrl.selection.baseOffset, 7);
      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test('selectSuggestion uses brackets for names with spaces', () {
      members.add(_makeUser('@john.doe:example.com', 'John Doe'));
      when(mockRoom.getParticipants()).thenReturn(members);

      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@john',
        selection: TextSelection.collapsed(offset: 5),
      );

      final john = ctrl.suggestions.firstWhere(
          (s) => s.displayName == 'John Doe');
      ctrl.selectSuggestion(john);

      expect(textCtrl.text, '@[John Doe] ');

      ctrl.dispose();
    });

    test('selectSuggestion for room with alias inserts alias', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '#gen',
        selection: TextSelection.collapsed(offset: 4),
      );

      ctrl.selectSuggestion(ctrl.suggestions[0]);

      expect(textCtrl.text, '#general:example.com ');

      ctrl.dispose();
    });

    test('selectSuggestion preserves text around trigger', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: 'hey @ali thanks',
        selection: TextSelection.collapsed(offset: 8),
      );

      expect(ctrl.suggestions.isNotEmpty, isTrue);
      ctrl.selectSuggestion(ctrl.suggestions[0]);

      expect(textCtrl.text, 'hey @Alice  thanks');

      ctrl.dispose();
    });

    // ── Keyboard navigation ────────────────────────────────

    test('moveDown increments selectedIndex', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@',
        selection: TextSelection.collapsed(offset: 1),
      );

      expect(ctrl.selectedIndex, 0);
      ctrl.moveDown();
      expect(ctrl.selectedIndex, 1);
      ctrl.moveDown();
      expect(ctrl.selectedIndex, 2);

      ctrl.dispose();
    });

    test('moveUp decrements selectedIndex', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@',
        selection: TextSelection.collapsed(offset: 1),
      );

      ctrl.moveDown();
      ctrl.moveDown();
      expect(ctrl.selectedIndex, 2);

      ctrl.moveUp();
      expect(ctrl.selectedIndex, 1);

      ctrl.dispose();
    });

    test('moveDown clamps at end of suggestions', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@',
        selection: TextSelection.collapsed(offset: 1),
      );

      for (var i = 0; i < 10; i++) {
        ctrl.moveDown();
      }
      expect(ctrl.selectedIndex, 2); // 3 members, max index 2.

      ctrl.dispose();
    });

    test('moveUp clamps at 0', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@',
        selection: TextSelection.collapsed(offset: 1),
      );

      ctrl.moveUp();
      expect(ctrl.selectedIndex, 0);

      ctrl.dispose();
    });

    test('confirmSelection does nothing when suggestions empty', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@zzzznotamember',
        selection: TextSelection.collapsed(offset: 15),
      );

      expect(ctrl.suggestions, isEmpty);
      ctrl.confirmSelection(); // Should not throw.
      expect(textCtrl.text, '@zzzznotamember');

      ctrl.dispose();
    });

    // ── Dismissal ──────────────────────────────────────────

    test('dismiss clears state', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@ali',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(ctrl.isActive, isTrue);
      ctrl.dismiss();
      expect(ctrl.isActive, isFalse);
      expect(ctrl.suggestions, isEmpty);
      expect(ctrl.selectedIndex, 0);

      ctrl.dispose();
    });

    // ── hasSuggestions ──────────────────────────────────────

    test('hasSuggestions is true only when active with suggestions', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      expect(ctrl.hasSuggestions, isFalse);

      textCtrl.value = const TextEditingValue(
        text: '@ali',
        selection: TextSelection.collapsed(offset: 4),
      );
      expect(ctrl.hasSuggestions, isTrue);

      textCtrl.value = const TextEditingValue(
        text: '@zzzzz',
        selection: TextSelection.collapsed(offset: 6),
      );
      expect(ctrl.isActive, isTrue);
      expect(ctrl.hasSuggestions, isFalse);

      ctrl.dispose();
    });

    // ── Async member loading ───────────────────────────────

    test('requestParticipants updates suggestions when complete', () async {
      final completer = Completer<List<User>>();
      when(mockRoom.requestParticipants())
          .thenAnswer((_) => completer.future);

      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@',
        selection: TextSelection.collapsed(offset: 1),
      );

      // Initially has members from getParticipants().
      expect(ctrl.suggestions.length, 3);

      // Add a new member via requestParticipants.
      final newMembers = [
        ...members,
        _makeUser('@eve:example.com', 'Eve'),
      ];
      completer.complete(newMembers);
      await Future.delayed(Duration.zero);

      expect(ctrl.suggestions.length, 4);

      ctrl.dispose();
    });

    test('requestParticipants callback does not throw after dispose', () async {
      final completer = Completer<List<User>>();
      when(mockRoom.requestParticipants())
          .thenAnswer((_) => completer.future);

      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@',
        selection: TextSelection.collapsed(offset: 1),
      );

      ctrl.dispose();

      // Complete after dispose — should not throw.
      completer.complete(members);
      await Future.delayed(Duration.zero);
    });

    // ── selectedIndex resets on new query ───────────────────

    test('selectedIndex resets when query changes', () {
      final ctrl = MentionAutocompleteController(
        textController: textCtrl,
        room: mockRoom,
        joinedRooms: joinedRooms,
      );

      textCtrl.value = const TextEditingValue(
        text: '@',
        selection: TextSelection.collapsed(offset: 1),
      );

      ctrl.moveDown();
      expect(ctrl.selectedIndex, 1);

      // Change query — selectedIndex should reset.
      textCtrl.value = const TextEditingValue(
        text: '@a',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(ctrl.selectedIndex, 0);

      ctrl.dispose();
    });
  });
}
