const kCallInvite = 'm.call.invite';
const kCallAnswer = 'm.call.answer';
const kCallHangup = 'm.call.hangup';
const kCallReject = 'm.call.reject';
const kCallMember = 'com.famedly.call.member';
const kCallMemberMsc = 'org.matrix.msc3401.call.member';

const kHangupUserHangup = 'user_hangup';
const kHangupInviteTimeout = 'invite_timeout';

const kIoKoheraIsVideo = 'io.kohera.is_video';
const kPushRuleCallMember = '.io.kohera.call_member';
const ringPhaseExpiresMs = 60000;

const Set<String> callEventTypes = {
  kCallInvite,
  kCallAnswer,
  kCallHangup,
  kCallReject,
};
