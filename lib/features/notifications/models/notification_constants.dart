abstract class NotificationChannel {
  static const appId = 'io.github.quantumheart.kohera';
  static const appName = 'Kohera';
  static const windowsGuid = 'ef82b5e7-fd65-431d-bcbb-9c7fa9acb761';

  static const androidChannelId = 'kohera_messages';
  static const androidChannelName = 'Messages';
  static const androidChannelDescription = 'Chat message notifications';
  static const androidGroupKey = 'io.github.quantumheart.kohera.MESSAGES';

  static const linuxSoundName = 'message-new-instant';
  static const linuxDesktopEntry = 'kohera';
  static const linuxAppIcon = 'kohera';

  static const avatarTempPrefix = 'kohera_avatar_';

  static const defaultGatewayUrl =
      'https://matrix.gateway.unifiedpush.org/_matrix/push/v1/notify';
  static const defaultDeviceName = 'Android';
  static const iosDefaultDeviceName = 'iOS';
  static const defaultLang = 'en';

  static const webPushAppId = 'io.github.quantumheart.kohera.web';
  static const webDefaultDeviceName = 'Web';
}

abstract class NotificationText {
  static const encryptedMessage = 'Encrypted message';
  static const fallbackInviterName = 'Someone';
  static const inviteBody = 'invited you to join';
  static const newMessageTitle = 'New message';
  static const newMessageBody = 'You have a new message';
  static const replyAction = 'Reply';
  static const markAsReadAction = 'Mark as Read';

  static String callStarted(String sender) => '$sender started a call';
  static String callAnswered(String sender) => '$sender answered the call';
  static String callDeclined(String sender) => '$sender declined the call';
  static String callMissed(String sender) => 'Missed call from $sender';
  static const callEnded = 'Call ended';

  static String senderBody(String name, String body) => '$name: $body';

  static String moreMessages(int count) => '... and $count more';

  static String groupTitle(String roomName, int count) =>
      '$roomName \u00b7 $count messages';
}

abstract class InboxText {
  static const title = 'Inbox';
  static const filterAll = 'All';
  static const filterMentions = 'Mentions';
  static const filterInvitations = 'Invites';
  static const noNotifications = 'No notifications';
  static const failedToLoad = 'Failed to load notifications';
  static const retry = 'Retry';
  static const noPendingInvitations = 'No pending invitations';
  static const sectionSpaces = 'Spaces';
  static const sectionRooms = 'Rooms';
  static const tooltipMarkAsRead = 'Mark as read';
  static const tooltipOpen = 'Open';
  static const mediaImage = '📷 Image';
  static const mediaVideo = '🎥 Video';
  static const mediaAudio = '🎵 Audio';
  static const mediaFile = '📎 File';
  static const loadMore = 'Load more';

  static String invitationsWithCount(int count) => 'Invites ($count)';
}
