# The PBX owns signalling and media for SIP calls, so the agent actions inherited from
# Whatsapp::CallService only move local state: there is no SDP to relay and no provider to call.
class Voice::Provider::Sip::CallService < Whatsapp::CallService
  def accept
    call.with_lock do
      transition_to_in_progress!
      update_message_status('in_progress')
      claim_conversation_and_set_call_status
      broadcast(:accepted, accepted_by_agent_id: agent.id)
    end
    call
  end

  private

  # The PBX reports the pickup too and can get here first; when it did, the agent whose browser
  # answered still has to be able to claim the call.
  def transition_to_in_progress!
    return super unless call.in_progress? && [nil, agent.id].include?(call.accepted_by_agent_id)

    call.update!(accepted_by_agent_id: agent.id)
  end

  # Whoever answers the phone takes the thread: a call can ring past an assignee who has no
  # extension, and the dashboard drops a call on a conversation assigned to someone else.
  def claim_conversation_and_set_call_status
    conversation = call.conversation
    conversation.assignee = agent if call.incoming? && conversation.assignee.present?
    super
  end

  def forward_answer_to_meta!; end

  def invoke_provider!(*)
    true
  end
end
