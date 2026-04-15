enum KoheraCallState {
  idle,
  ringingOutgoing,
  ringingIncoming,
  joining,
  connected,
  reconnecting,
  disconnecting,
  failed,
}

const Map<KoheraCallState, Set<KoheraCallState>> validCallTransitions = {
  KoheraCallState.idle: {
    KoheraCallState.joining,
    KoheraCallState.ringingOutgoing,
    KoheraCallState.ringingIncoming,
  },
  KoheraCallState.ringingOutgoing: {
    KoheraCallState.joining,
    KoheraCallState.connected,
    KoheraCallState.idle,
    KoheraCallState.failed,
  },
  KoheraCallState.ringingIncoming: {
    KoheraCallState.joining,
    KoheraCallState.idle,
  },
  KoheraCallState.joining: {
    KoheraCallState.connected,
    KoheraCallState.idle,
    KoheraCallState.failed,
  },
  KoheraCallState.connected: {
    KoheraCallState.reconnecting,
    KoheraCallState.disconnecting,
    KoheraCallState.failed,
  },
  KoheraCallState.reconnecting: {
    KoheraCallState.connected,
    KoheraCallState.disconnecting,
    KoheraCallState.failed,
  },
  KoheraCallState.disconnecting: {
    KoheraCallState.idle,
  },
  KoheraCallState.failed: {
    KoheraCallState.idle,
    KoheraCallState.joining,
    KoheraCallState.ringingOutgoing,
  },
};
