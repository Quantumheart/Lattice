enum LatticeCallState {
  idle,
  ringingOutgoing,
  ringingIncoming,
  joining,
  connected,
  reconnecting,
  disconnecting,
  failed,
}

const Map<LatticeCallState, Set<LatticeCallState>> validCallTransitions = {
  LatticeCallState.idle: {
    LatticeCallState.joining,
    LatticeCallState.ringingOutgoing,
    LatticeCallState.ringingIncoming,
  },
  LatticeCallState.ringingOutgoing: {
    LatticeCallState.joining,
    LatticeCallState.connected,
    LatticeCallState.idle,
    LatticeCallState.failed,
  },
  LatticeCallState.ringingIncoming: {
    LatticeCallState.joining,
    LatticeCallState.idle,
  },
  LatticeCallState.joining: {
    LatticeCallState.connected,
    LatticeCallState.idle,
    LatticeCallState.failed,
  },
  LatticeCallState.connected: {
    LatticeCallState.reconnecting,
    LatticeCallState.disconnecting,
    LatticeCallState.failed,
  },
  LatticeCallState.reconnecting: {
    LatticeCallState.connected,
    LatticeCallState.disconnecting,
    LatticeCallState.failed,
  },
  LatticeCallState.disconnecting: {
    LatticeCallState.idle,
  },
  LatticeCallState.failed: {
    LatticeCallState.idle,
    LatticeCallState.joining,
    LatticeCallState.ringingOutgoing,
  },
};
